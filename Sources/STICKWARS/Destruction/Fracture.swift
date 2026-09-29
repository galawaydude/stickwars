import CoreGraphics

struct FractureCell {
    var poly: [CGPoint]   // with the jagged rim point, CCW
    var core: [CGPoint]   // convex version for the physics body
    var ring: Int         // 1 = innermost
}

struct FractureResult {
    var cells: [FractureCell]
    var outline: [CGPoint]  // jagged crater rim, CCW
    var cracks: [[CGPoint]]
    var rings: Int
}

/// Radial fracture: jittered spokes x 1-3 rings -> triangles and quads, with a jagged outer rim
/// and zig-zag cracks growing outward.
enum Fracture {
    static func make(center c: CGPoint, radius R: CGFloat, rng g: inout RNG) -> FractureResult {
        let n = 5 + g.int(10)
        let m = 1 + g.int(3)
        let base = g.range(0, .pi * 2)
        let step = .pi * 2 / CGFloat(n)
        var ang = [CGFloat](repeating: 0, count: n)
        for i in 0..<n { ang[i] = base + CGFloat(i) * step + g.range(-0.35, 0.35) * step }
        // v[k][i], k = 0..m-1 (ring k+1). Radii strictly increase outward along each spoke.
        var v = [[CGPoint]](repeating: [], count: m)
        for k in 0..<m {
            for i in 0..<n {
                let u = k == m - 1 ? g.range(0.85, 1.0) : g.range(0.6, 1.0)
                let r = R * (CGFloat(k) + u) / CGFloat(m)
                v[k].append(CGPoint(x: c.x + cos(ang[i]) * r, y: c.y + sin(ang[i]) * r))
            }
        }
        // Jagged rim: displaced midpoint on each outer edge.
        var mid = [CGPoint](repeating: .zero, count: n)
        for i in 0..<n {
            let a = v[m - 1][i], b = v[m - 1][(i + 1) % n]
            let mp = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let d = mp - c
            mid[i] = c + d.normalized * (d.length + R * g.range(-0.05, 0.15))
        }
        var outline: [CGPoint] = []
        for i in 0..<n { outline.append(v[m - 1][i]); outline.append(mid[i]) }

        var cells: [FractureCell] = []
        for k in 0..<m {
            for i in 0..<n {
                let j = (i + 1) % n
                let outer = k == m - 1
                if k == 0 {
                    let core = [c, v[0][i], v[0][j]]
                    cells.append(FractureCell(poly: outer ? [c, v[0][i], mid[i], v[0][j]] : core, core: core, ring: 1))
                } else {
                    let core = [v[k - 1][i], v[k][i], v[k][j], v[k - 1][j]]
                    let poly = outer ? [v[k - 1][i], v[k][i], mid[i], v[k][j], v[k - 1][j]] : core
                    cells.append(FractureCell(poly: poly, core: core, ring: k + 1))
                }
            }
        }

        // Cracks from some outer vertices, with occasional branches.
        var cracks: [[CGPoint]] = []
        func grow(_ start: CGPoint, _ dir: CGFloat, _ len: CGFloat, _ depth: Int) {
            var p = start, a = dir, left = len
            var line = [p]
            while left > 0 {
                let s = min(left, R * g.range(0.12, 0.28))
                a += g.range(-0.5, 0.5)
                p = CGPoint(x: p.x + cos(a) * s, y: p.y + sin(a) * s)
                line.append(p)
                left -= s
                if depth == 0, g.chance(0.2) { grow(p, a + (g.chance(0.5) ? 0.7 : -0.7), left * 0.5, 1) }
            }
            cracks.append(line)
        }
        for i in 0..<n where g.chance(0.6) { grow(v[m - 1][i], ang[i], R * g.range(0.6, 1.4), 0) }
        return FractureResult(cells: cells, outline: outline, cracks: cracks, rings: m)
    }

    /// Signed shoelace area (positive = CCW).
    static func area(_ p: [CGPoint]) -> CGFloat {
        var a: CGFloat = 0
        for i in 0..<p.count { let q = p[i], r = p[(i + 1) % p.count]; a += q.x * r.y - r.x * q.y }
        return a / 2
    }

    static func bounds(_ p: [CGPoint]) -> CGRect {
        var x0 = CGFloat.infinity, y0 = CGFloat.infinity, x1 = -CGFloat.infinity, y1 = -CGFloat.infinity
        for q in p { x0 = min(x0, q.x); y0 = min(y0, q.y); x1 = max(x1, q.x); y1 = max(y1, q.y) }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    static func isConvex(_ p: [CGPoint]) -> Bool {
        guard p.count >= 3 else { return false }
        var sign: CGFloat = 0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count], c = p[(i + 2) % p.count]
            let cr = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cr) < 1e-6 { continue }
            if sign == 0 { sign = cr } else if sign * cr < 0 { return false }
        }
        return true
    }
}
