import CoreGraphics
import Foundation

enum NavLink: UInt8 { case walk, jump, doubleJump, drop, fall, jet }

struct NavNode {
    var x0: CGFloat, x1: CGFloat, y: CGFloat
    var floor: Bool
}

struct NavEdge {
    var to: Int32
    var kind: NavLink
    var takeoff: CGFloat   // x on the source ledge where the move starts
    var land: CGFloat      // x to steer to on the target
    var cost: Float
}

/// Ledge segments (merged element tops) linked by moves validated against the controller's
/// real jump and fall arcs. Built off the main thread from a snapshot of the tops.
final class NavGraph {
    private(set) var nodes: [NavNode] = []
    private(set) var edges: [[NavEdge]] = []

    /// Horizontal reach tables from simulating the controller: (dy, maxDx) samples while descending.
    struct Arc { var pts: [(CGFloat, CGFloat)] } // (y, x) along the trajectory
    static let single = simulate(jump: true, double: false)
    static let double = simulate(jump: true, double: true)
    static let fallArc = simulate(jump: false, double: false)

    static func simulate(jump: Bool, double: Bool) -> Arc {
        let dt: CGFloat = 1 / 120
        let vx = Move.run
        var x: CGFloat = 0, y: CGFloat = 0, vy: CGFloat = jump ? Move.jump : 0
        var used = !double
        var pts: [(CGFloat, CGFloat)] = []
        for _ in 0..<600 {
            if !used && vy <= 60 { vy = Move.doubleJump; used = true }
            vy -= Move.gravity * dt
            vy = max(vy, -Move.maxFall)
            x += vx * dt; y += vy * dt
            pts.append((y, x))
            if y < -700 { break }
        }
        return Arc(pts: pts)
    }

    /// Max horizontal distance covered by the time the arc comes down through height dy (nil = unreachable).
    static func reach(_ arc: Arc, dy: CGFloat) -> CGFloat? {
        var apex = -CGFloat.infinity
        for (y, _) in arc.pts { apex = max(apex, y) }
        guard apex >= dy + 6 else { return nil }
        var passedApex = false
        var prevY = -CGFloat.infinity
        for (y, x) in arc.pts {
            if y < prevY { passedApex = true }
            if passedApex && y <= dy { return x }
            prevY = y
        }
        return nil
    }

    /// Tops of solid elements plus the floor, as (x0, x1, y).
    static func tops(_ level: Level) -> [NavNode] {
        var out: [NavNode] = [NavNode(x0: 0, x1: level.size.width, y: 0, floor: true)]
        out.reserveCapacity(level.solidCount + 1)
        for e in level.elements where e.state == .solid && e.rect.width >= 6 && e.rect.maxY < level.size.height - 40 {
            out.append(NavNode(x0: e.rect.minX, x1: e.rect.maxX, y: e.rect.maxY, floor: false))
        }
        return out
    }

    static func build(tops raw: [NavNode], size: CGSize) -> NavGraph {
        let g = NavGraph()
        // Merge tops at the same height that nearly touch (words on one line -> one ledge).
        let sorted = raw.dropFirst().sorted { abs($0.y - $1.y) > 2 ? $0.y < $1.y : $0.x0 < $1.x0 }
        var merged: [NavNode] = [raw[0]]
        for t in sorted {
            if var last = merged.last, !last.floor, abs(last.y - t.y) <= 2, t.x0 - last.x1 <= 8 {
                last.x1 = max(last.x1, t.x1); last.y = max(last.y, t.y)
                merged[merged.count - 1] = last
            } else { merged.append(t) }
        }
        g.nodes = merged.filter { $0.x1 - $0.x0 >= 4 || $0.floor }
        let n = g.nodes.count
        g.edges = [[NavEdge]](repeating: [], count: n)
        let halfW = Move.halfW
        for a in 0..<n {
            let A = g.nodes[a]
            // Drops: for sample x on A, the highest node below that x.
            if !A.floor {
                var x = A.x0 + 8
                var lastTarget = -1
                while x <= A.x1 - 4 {
                    var best = -1, bestY = -CGFloat.infinity
                    for b in 0..<n where b != a {
                        let B = g.nodes[b]
                        if B.y < A.y - 4, B.y > bestY, B.x0 - halfW < x, B.x1 + halfW > x { best = b; bestY = B.y }
                    }
                    if best >= 0 && best != lastTarget {
                        g.edges[a].append(NavEdge(to: Int32(best), kind: .drop, takeoff: x, land: x, cost: Float(A.y - bestY) * 0.4 + 15))
                        lastTarget = best
                    }
                    x += 36
                }
            }
            for b in 0..<n where b != a {
                let B = g.nodes[b]
                let dy = B.y - A.y
                if dy > 440 || dy < -520 { continue }
                let gapR = B.x0 - A.x1, gapL = A.x0 - B.x1
                let gap = max(gapR, gapL, 0)
                if gap > 420 { continue }
                if gap <= 0 {
                    // overlapping: jump straight up onto B
                    guard dy > 4, !B.floor else { continue }
                    let ox0 = max(A.x0, B.x0), ox1 = min(A.x1, B.x1)
                    let mid = (ox0 + ox1) / 2
                    if dy <= 125 {
                        g.edges[a].append(NavEdge(to: Int32(b), kind: .jump, takeoff: mid, land: mid, cost: Float(dy) + 30))
                    } else if dy <= 250 {
                        g.edges[a].append(NavEdge(to: Int32(b), kind: .doubleJump, takeoff: mid, land: mid, cost: Float(dy) + 70))
                    } else {
                        // jump + jetpack (fuel lifts ~450 pt)
                        g.edges[a].append(NavEdge(to: Int32(b), kind: .jet, takeoff: mid, land: mid, cost: Float(dy) * 1.5 + 160))
                    }
                    continue
                }
                let right = gapR > 0
                let takeoff = right ? A.x1 - 4 : A.x0 + 4
                let land = right ? B.x0 + min(24, (B.x1 - B.x0) / 2) : B.x1 - min(24, (B.x1 - B.x0) / 2)
                let dist = Float(gap + abs(dy))
                if abs(dy) <= 3 && gap <= 14 {
                    g.edges[a].append(NavEdge(to: Int32(b), kind: .walk, takeoff: takeoff, land: land, cost: dist + 2))
                    continue
                }
                if dy < 0, let r = reach(fallArc, dy: dy), gap + halfW <= r - 12 {
                    g.edges[a].append(NavEdge(to: Int32(b), kind: .fall, takeoff: takeoff, land: land, cost: dist + 10))
                } else if let r = reach(single, dy: dy), gap <= r - 20 {
                    g.edges[a].append(NavEdge(to: Int32(b), kind: .jump, takeoff: takeoff, land: land, cost: dist + 35))
                } else if let r = reach(double, dy: dy), gap <= r - 30 {
                    g.edges[a].append(NavEdge(to: Int32(b), kind: .doubleJump, takeoff: takeoff, land: land, cost: dist + 75))
                } else if dy > 0, gap <= 260 {
                    g.edges[a].append(NavEdge(to: Int32(b), kind: .jet, takeoff: takeoff, land: land, cost: dist * 1.5 + 160))
                }
            }
        }
        return g
    }

    /// The ledge a grounded fighter at p stands on (nearest top at p.y within reach).
    func node(at p: CGPoint) -> Int {
        var best = -1, bestD = CGFloat.infinity
        for (i, n) in nodes.enumerated() where p.x >= n.x0 - Move.halfW && p.x <= n.x1 + Move.halfW {
            let d = abs(n.y - p.y)
            if d < bestD { bestD = d; best = i }
        }
        return bestD < 6 ? best : -1
    }

    /// Nearest ledge at or below p (where something at p would end up standing).
    func node(below p: CGPoint) -> Int {
        var best = 0, bestY = -CGFloat.infinity
        for (i, n) in nodes.enumerated() where p.x >= n.x0 - 4 && p.x <= n.x1 + 4 && n.y <= p.y + 4 && n.y > bestY {
            best = i; bestY = n.y
        }
        return best
    }

    // A* scratch (reused)
    private var gScore: [Float] = [], fromEdge: [Int32] = [], fromNode: [Int32] = [], closed: [Bool] = []
    private var heap: [(Float, Int32)] = []

    /// A* from a to b; fills `out` with the edges to take, in order.
    func path(from a: Int, to b: Int, into out: inout [NavEdge]) -> Bool {
        out.removeAll(keepingCapacity: true)
        let n = nodes.count
        guard a >= 0, b >= 0, a < n, b < n else { return false }
        if a == b { return true }
        if gScore.count != n {
            gScore = [Float](repeating: 0, count: n); fromEdge = [Int32](repeating: -1, count: n)
            fromNode = [Int32](repeating: -1, count: n); closed = [Bool](repeating: false, count: n)
        }
        for i in 0..<n { gScore[i] = .infinity; fromEdge[i] = -1; fromNode[i] = -1; closed[i] = false }
        heap.removeAll(keepingCapacity: true)
        let goal = nodes[b]
        func h(_ i: Int) -> Float {
            let m = nodes[i]
            return Float(abs((m.x0 + m.x1) / 2 - (goal.x0 + goal.x1) / 2) * 0.5 + abs(m.y - goal.y))
        }
        gScore[a] = 0
        push((h(a), Int32(a)))
        var found = false
        var iterations = 0
        while let (_, cur32) = pop() {
            let cur = Int(cur32)
            if closed[cur] { continue }
            closed[cur] = true
            if cur == b { found = true; break }
            iterations += 1
            if iterations > 4000 { break }
            for (k, e) in edges[cur].enumerated() {
                let t = Int(e.to)
                if closed[t] { continue }
                let ng = gScore[cur] + e.cost
                if ng < gScore[t] {
                    gScore[t] = ng; fromNode[t] = Int32(cur); fromEdge[t] = Int32(k)
                    push((ng + h(t), e.to))
                }
            }
        }
        guard found else { return false }
        var cur = b
        while cur != a {
            let p = Int(fromNode[cur]), k = Int(fromEdge[cur])
            out.append(edges[p][k])
            cur = p
        }
        out.reverse()
        return true
    }

    private func push(_ v: (Float, Int32)) {
        heap.append(v)
        var i = heap.count - 1
        while i > 0 { let p = (i - 1) / 2; if heap[p].0 <= heap[i].0 { break }; heap.swapAt(p, i); i = p }
    }

    private func pop() -> (Float, Int32)? {
        guard !heap.isEmpty else { return nil }
        let top = heap[0]
        let last = heap.removeLast()
        if !heap.isEmpty {
            heap[0] = last
            var i = 0
            while true {
                let l = i * 2 + 1, r = l + 1
                var m = i
                if l < heap.count && heap[l].0 < heap[m].0 { m = l }
                if r < heap.count && heap[r].0 < heap[m].0 { m = r }
                if m == i { break }
                heap.swapAt(i, m); i = m
            }
        }
        return top
    }
}
