import SpriteKit

/// The editable snapshot: a full-resolution premultiplied RGBA8 buffer (row 0 = top), shown as
/// 256x256-px tiles. Edits mark tiles dirty; `flush()` re-uploads only those, once per frame.
final class Canvas {
    let pw: Int, ph: Int
    let scale: CGFloat
    let size: CGSize
    let buf: UnsafeMutablePointer<UInt8>
    let node = SKNode()
    static let T = 256
    let tilesX: Int, tilesY: Int
    private var tiles: [SKMutableTexture] = []
    private var dirty: [Bool]
    private var dirtyList: [Int] = []
    private(set) var lastFlushCount = 0

    init(image: CGImage, pointSize: CGSize) {
        pw = image.width; ph = image.height
        size = pointSize
        scale = CGFloat(pw) / pointSize.width
        buf = .allocate(capacity: pw * ph * 4)
        let ctx = CGContext(data: buf, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        tilesX = (pw + Canvas.T - 1) / Canvas.T
        tilesY = (ph + Canvas.T - 1) / Canvas.T
        dirty = [Bool](repeating: false, count: tilesX * tilesY)
        dirtyList.reserveCapacity(tilesX * tilesY)
        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let x0 = tx * Canvas.T, y0 = ty * Canvas.T
                let w = min(Canvas.T, pw - x0), h = min(Canvas.T, ph - y0)
                let tex = SKMutableTexture(size: CGSize(width: w, height: h))
                tex.filteringMode = .nearest
                tiles.append(tex)
                let s = SKSpriteNode(texture: tex, size: CGSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale))
                s.position = CGPoint(x: (CGFloat(x0) + CGFloat(w) / 2) / scale, y: size.height - (CGFloat(y0) + CGFloat(h) / 2) / scale)
                s.blendMode = .alpha
                node.addChild(s)
                let t = ty * tilesX + tx
                dirty[t] = true; dirtyList.append(t)
            }
        }
        flush()
    }

    deinit { buf.deallocate() }

    // MARK: coordinates

    /// Pixel rect (x0, y0, x1, y1), end-exclusive, clamped, for a scene-space rect.
    @inline(__always) func pxRect(_ r: CGRect) -> (Int, Int, Int, Int) {
        let x0 = clamp(Int((r.minX * scale).rounded(.down)), 0, pw), x1 = clamp(Int((r.maxX * scale).rounded(.up)), 0, pw)
        let y0 = clamp(Int(((size.height - r.maxY) * scale).rounded(.down)), 0, ph)
        let y1 = clamp(Int(((size.height - r.minY) * scale).rounded(.up)), 0, ph)
        return (x0, y0, x1, y1)
    }

    /// The scene rect exactly covered by pxRect(r) (where a crop of r should be drawn).
    func aligned(_ r: CGRect) -> CGRect {
        let (x0, y0, x1, y1) = pxRect(r)
        return CGRect(x: CGFloat(x0) / scale, y: size.height - CGFloat(y1) / scale, width: CGFloat(x1 - x0) / scale, height: CGFloat(y1 - y0) / scale)
    }

    @inline(__always) func toPx(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale, y: (size.height - p.y) * scale) }

    func markDirty(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        guard x1 > x0, y1 > y0 else { return }
        let tx0 = max(0, x0 / Canvas.T), tx1 = min(tilesX - 1, (x1 - 1) / Canvas.T)
        let ty0 = max(0, y0 / Canvas.T), ty1 = min(tilesY - 1, (y1 - 1) / Canvas.T)
        guard tx0 <= tx1, ty0 <= ty1 else { return }
        for ty in ty0...ty1 { for tx in tx0...tx1 {
            let t = ty * tilesX + tx
            if !dirty[t] { dirty[t] = true; dirtyList.append(t) }
        } }
    }

    /// Re-uploads dirty tiles. Texture rows are bottom-up, the canvas is top-down.
    func flush() {
        lastFlushCount = dirtyList.count
        for t in dirtyList {
            dirty[t] = false
            let x0 = (t % tilesX) * Canvas.T, y0 = (t / tilesX) * Canvas.T
            let w = min(Canvas.T, pw - x0), h = min(Canvas.T, ph - y0)
            let src = buf, pw = pw
            tiles[t].modifyPixelData { ptr, len in
                guard let ptr else { return }
                let dst = ptr.assumingMemoryBound(to: UInt8.self)
                let stride = len / h
                for row in 0..<h {
                    memcpy(dst + (h - 1 - row) * stride, src + ((y0 + row) * pw + x0) * 4, w * 4)
                }
            }
        }
        dirtyList.removeAll(keepingCapacity: true)
    }

    // MARK: sampling

    func color(at p: CGPoint) -> RGBA {
        let x = clamp(Int(p.x * scale), 0, pw - 1), y = clamp(Int((size.height - p.y) * scale), 0, ph - 1)
        let i = (y * pw + x) * 4
        return RGBA(buf[i], buf[i + 1], buf[i + 2], buf[i + 3])
    }

    /// Per-channel median of the pixels on the rect's border (expanded by 1 pt), and whether
    /// the border is flat enough to count as a plain panel background.
    func borderBackground(_ r: CGRect) -> (RGBA, Bool) {
        let (x0, y0, x1, y1) = pxRect(r.insetBy(dx: -1, dy: -1))
        guard x1 - x0 > 1, y1 - y0 > 1 else { return (RGBA(255, 255, 255), false) }
        var hr = [Int](repeating: 0, count: 256), hg = hr, hb = hr, ha = hr
        var n = 0
        func add(_ x: Int, _ y: Int) {
            let i = (y * pw + x) * 4
            hr[Int(buf[i])] += 1; hg[Int(buf[i + 1])] += 1; hb[Int(buf[i + 2])] += 1; ha[Int(buf[i + 3])] += 1; n += 1
        }
        for x in x0..<x1 { add(x, y0); add(x, y1 - 1) }
        for y in (y0 + 1)..<(y1 - 1) { add(x0, y); add(x1 - 1, y) }
        func med(_ h: [Int]) -> UInt8 { var c = 0; for v in 0..<256 { c += h[v]; if c * 2 >= n { return UInt8(v) } }; return 255 }
        let m = RGBA(med(hr), med(hg), med(hb), med(ha))
        // flatness: fraction of border pixels close to the median
        var close = 0
        func near(_ x: Int, _ y: Int) {
            let i = (y * pw + x) * 4
            if abs(Int(buf[i]) - Int(m.r)) + abs(Int(buf[i + 1]) - Int(m.g)) + abs(Int(buf[i + 2]) - Int(m.b)) < 30, buf[i + 3] > 250 { close += 1 }
        }
        for x in x0..<x1 { near(x, y0); near(x, y1 - 1) }
        for y in (y0 + 1)..<(y1 - 1) { near(x0, y); near(x1 - 1, y) }
        return (m, m.a > 250 && close * 10 >= n * 8)
    }

    @inline(__always) private func ink(_ i: Int, _ bg: RGBA) -> Int {
        if buf[i + 3] < 128 { return 0 }
        return abs(Int(buf[i]) - Int(bg.r)) + abs(Int(buf[i + 1]) - Int(bg.g)) + abs(Int(buf[i + 2]) - Int(bg.b))
    }

    /// Tight bounds of "ink" (pixels differing from bg) inside r, in points.
    func inkBounds(_ r: CGRect, bg: RGBA) -> CGRect? {
        let (x0, y0, x1, y1) = pxRect(r)
        var mx0 = Int.max, my0 = Int.max, mx1 = -1, my1 = -1
        for y in y0..<max(y0, y1) { for x in x0..<max(x0, x1) where ink((y * pw + x) * 4, bg) > 40 {
            mx0 = min(mx0, x); mx1 = max(mx1, x); my0 = min(my0, y); my1 = max(my1, y)
        } }
        guard mx1 >= 0 else { return nil }
        return CGRect(x: CGFloat(mx0) / scale, y: size.height - CGFloat(my1 + 1) / scale,
                      width: CGFloat(mx1 + 1 - mx0) / scale, height: CGFloat(my1 + 1 - my0) / scale)
    }

    /// Letter spans inside a text rect: runs of pixel columns containing ink, separated by empty columns.
    func letterSpans(_ r: CGRect, bg: RGBA) -> [CGRect] {
        let (x0, y0, x1, y1) = pxRect(r)
        guard x1 > x0, y1 > y0 else { return [] }
        var out: [CGRect] = []
        var start = -1
        for x in x0...x1 {
            var has = false
            if x < x1 { for y in y0..<y1 where ink((y * pw + x) * 4, bg) > 40 { has = true; break } }
            if has, start < 0 { start = x }
            if !has, start >= 0 {
                out.append(CGRect(x: CGFloat(start) / scale, y: r.minY, width: CGFloat(x - start) / scale, height: r.height))
                start = -1
            }
        }
        // Merge slivers (under 2 pt) into their neighbour so pieces aren't specks.
        var merged: [CGRect] = []
        for s in out {
            if let last = merged.last, s.width < 2 || last.width < 2, s.minX - last.maxX < 2 {
                merged[merged.count - 1] = last.union(s)
            } else { merged.append(s) }
        }
        return merged
    }

    // MARK: editing

    func fillRect(_ r: CGRect, _ c: RGBA) {
        let (x0, y0, x1, y1) = pxRect(r)
        guard x1 > x0, y1 > y0 else { return }
        let pa = UInt32(c.a)
        let pr = UInt8(UInt32(c.r) * pa / 255), pg = UInt8(UInt32(c.g) * pa / 255), pb = UInt8(UInt32(c.b) * pa / 255)
        for y in y0..<y1 {
            var i = (y * pw + x0) * 4
            for _ in x0..<x1 { buf[i] = pr; buf[i + 1] = pg; buf[i + 2] = pb; buf[i + 3] = c.a; i += 4 }
        }
        markDirty(x0, y0, x1, y1)
    }

    /// Scanline polygon fill (even-odd) in scene points. `blend` < 1 darkens/tints existing
    /// opaque pixels instead of replacing them (used for scorch marks).
    func fillPolygon(_ poly: [CGPoint], _ c: RGBA, blend: CGFloat = 1) {
        guard poly.count >= 3 else { return }
        var pts = [CGPoint](); pts.reserveCapacity(poly.count)
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity, minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for p in poly {
            let q = toPx(p); pts.append(q)
            minX = min(minX, q.x); maxX = max(maxX, q.x); minY = min(minY, q.y); maxY = max(maxY, q.y)
        }
        let y0 = clamp(Int(minY), 0, ph), y1 = clamp(Int(maxY.rounded(.up)), 0, ph)
        let bx0 = clamp(Int(minX), 0, pw), bx1 = clamp(Int(maxX.rounded(.up)), 0, pw)
        guard y1 > y0, bx1 > bx0 else { return }
        var xs = [CGFloat](); xs.reserveCapacity(16)
        let a = UInt32(clamp(blend, 0, 1) * 255), ia = 255 - a
        for y in y0..<y1 {
            let sy = CGFloat(y) + 0.5
            xs.removeAll(keepingCapacity: true)
            var j = pts.count - 1
            for i in 0..<pts.count {
                let p = pts[i], q = pts[j]
                if (p.y > sy) != (q.y > sy) { xs.append(p.x + (sy - p.y) / (q.y - p.y) * (q.x - p.x)) }
                j = i
            }
            xs.sort()
            var k = 0
            while k + 1 < xs.count {
                let xa = clamp(Int(xs[k] + 0.5), 0, pw), xb = clamp(Int(xs[k + 1] + 0.5), 0, pw)
                var i = (y * pw + xa) * 4
                for _ in xa..<max(xa, xb) {
                    if a >= 255 {
                        let pa = UInt32(c.a)
                        buf[i] = UInt8(UInt32(c.r) * pa / 255); buf[i + 1] = UInt8(UInt32(c.g) * pa / 255)
                        buf[i + 2] = UInt8(UInt32(c.b) * pa / 255); buf[i + 3] = c.a
                    } else if buf[i + 3] > 0 {
                        let da = UInt32(buf[i + 3])
                        buf[i] = UInt8((UInt32(buf[i]) * ia + UInt32(c.r) * da / 255 * a) / 255)
                        buf[i + 1] = UInt8((UInt32(buf[i + 1]) * ia + UInt32(c.g) * da / 255 * a) / 255)
                        buf[i + 2] = UInt8((UInt32(buf[i + 2]) * ia + UInt32(c.b) * da / 255 * a) / 255)
                    }
                    i += 4
                }
                k += 2
            }
        }
        markDirty(bx0, y0, bx1, y1)
    }

    /// Blocky dithered burn mark around c (2-pt blocks, 4 shade levels) over existing pixels.
    func scorch(_ c: CGPoint, radius r: CGFloat, seed: UInt64) {
        let cp = toPx(c), rp = r * scale
        let x0 = clamp(Int(cp.x - rp), 0, pw), x1 = clamp(Int(cp.x + rp) + 1, 0, pw)
        let y0 = clamp(Int(cp.y - rp), 0, ph), y1 = clamp(Int(cp.y + rp) + 1, 0, ph)
        guard x1 > x0, y1 > y0 else { return }
        let block = max(1, Int(2 * scale))
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * pw + x) * 4
                let da = UInt32(buf[i + 3]); if da == 0 { continue }
                let bx = (x / block) * block + block / 2, by = (y / block) * block + block / 2
                let dx = CGFloat(bx) - cp.x, dy = CGFloat(by) - cp.y
                let d = (dx * dx + dy * dy).squareRoot() / rp
                if d >= 1 { continue }
                var h = UInt64(bx / block) &* 73856093 ^ UInt64(by / block) &* 19349663 ^ seed
                h = (h ^ (h >> 13)) &* 0x5bd1e995
                let noise = CGFloat(h & 1023) / 1023
                var s = (1 - d) * 1.5 + (noise - 0.5) * 0.7
                s = (clamp(s, 0, 1) * 4).rounded(.down) / 4 * 0.8
                if s <= 0 { continue }
                let a = UInt32(s * 255), ia = 255 - a
                buf[i] = UInt8((UInt32(buf[i]) * ia + 30 * da / 255 * a) / 255)
                buf[i + 1] = UInt8((UInt32(buf[i + 1]) * ia + 22 * da / 255 * a) / 255)
                buf[i + 2] = UInt8((UInt32(buf[i + 2]) * ia + 18 * da / 255 * a) / 255)
            }
        }
        markDirty(x0, y0, x1, y1)
    }

    /// Dark 1-2 px polyline (cracks), only over existing pixels.
    func drawPolyline(_ pts: [CGPoint], _ c: RGBA, alpha: CGFloat, width: Int = 2) {
        guard pts.count >= 2 else { return }
        let a = UInt32(alpha * 255), ia = 255 - a
        for s in 0..<(pts.count - 1) {
            let p = toPx(pts[s]), q = toPx(pts[s + 1])
            let steps = max(1, Int(max(abs(q.x - p.x), abs(q.y - p.y))))
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps)
                let cx = Int(p.x + (q.x - p.x) * t), cy = Int(p.y + (q.y - p.y) * t)
                for oy in 0..<width { for ox in 0..<width {
                    let x = cx + ox, y = cy + oy
                    guard x >= 0, y >= 0, x < pw, y < ph else { continue }
                    let i = (y * pw + x) * 4
                    let da = UInt32(buf[i + 3]); if da == 0 { continue }
                    buf[i] = UInt8((UInt32(buf[i]) * ia + UInt32(c.r) * da / 255 * a) / 255)
                    buf[i + 1] = UInt8((UInt32(buf[i + 1]) * ia + UInt32(c.g) * da / 255 * a) / 255)
                    buf[i + 2] = UInt8((UInt32(buf[i + 2]) * ia + UInt32(c.b) * da / 255 * a) / 255)
                } }
            }
            markDirty(Int(min(p.x, q.x)) - 1, Int(min(p.y, q.y)) - 1, Int(max(p.x, q.x)) + width + 1, Int(max(p.y, q.y)) + width + 1)
        }
    }

    /// Jagged circle polygon around c (scene points).
    static func jaggedCircle(_ c: CGPoint, _ r: CGFloat, _ g: inout RNG, n: Int = 14) -> [CGPoint] {
        var out = [CGPoint](); out.reserveCapacity(n)
        let rot = g.range(0, .pi * 2)
        for i in 0..<n {
            let a = rot + CGFloat(i) / CGFloat(n) * .pi * 2
            let rr = r * g.range(0.65, 1.15)
            out.append(CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr))
        }
        return out
    }

    // MARK: copying pixels out (one crop per element)

    func crop(_ r: CGRect) -> CGImage? {
        let (x0, y0, x1, y1) = pxRect(r)
        let w = x1 - x0, h = y1 - y0
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { d in
            for y in 0..<h { memcpy(d.baseAddress! + y * w * 4, buf + ((y0 + y) * pw + x0) * 4, w * 4) }
        }
        return Tex.image(px, w, h)
    }

    /// Copies r with alpha from the colour distance to bg, so only glyphs lift off the page.
    func cropKnockout(_ r: CGRect, bg: RGBA) -> CGImage? {
        let (x0, y0, x1, y1) = pxRect(r)
        let w = x1 - x0, h = y1 - y0
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            var s = ((y0 + y) * pw + x0) * 4, d = y * w * 4
            for _ in 0..<w {
                let sa = Int(buf[s + 3])
                if sa > 0 {
                    let dist = abs(Int(buf[s]) - Int(bg.r)) + abs(Int(buf[s + 1]) - Int(bg.g)) + abs(Int(buf[s + 2]) - Int(bg.b))
                    let a = clamp((dist - 14) * 255 / (75 - 14), 0, 255) * sa / 255
                    if a > 0 {
                        // source is premultiplied by sa; rescale to premultiplied by a
                        px[d] = UInt8(Int(buf[s]) * a / sa); px[d + 1] = UInt8(Int(buf[s + 1]) * a / sa)
                        px[d + 2] = UInt8(Int(buf[s + 2]) * a / sa); px[d + 3] = UInt8(a)
                    }
                }
                s += 4; d += 4
            }
        }
        return Tex.image(px, w, h)
    }

    /// Crop of the polygon's bounds clipped to the polygon, with a faint light edge (glass shard look).
    func cropPolygon(_ poly: [CGPoint], bounds b: CGRect) -> CGImage? {
        guard let img = crop(b) else { return nil }
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let path = CGMutablePath()
        let ab = aligned(b)
        for (i, p) in poly.enumerated() {
            let q = CGPoint(x: (p.x - ab.minX) * scale, y: (p.y - ab.minY) * scale)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        return ctx.makeImage()
    }
}
