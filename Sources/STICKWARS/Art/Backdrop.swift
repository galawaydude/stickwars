import SpriteKit

/// Procedural pixel-art night city revealed behind destroyed parts of the "screen".
enum Backdrop {
    /// `size` in points; 1 art pixel = 2 points.
    static func texture(size: CGSize, seed: UInt64 = 7) -> SKTexture {
        let w = max(8, Int(size.width / 2)), h = max(8, Int(size.height / 2))
        var r = RNG(seed)
        var px = [UInt8](repeating: 255, count: w * h * 4)
        func put(_ x: Int, _ y: Int, _ c: RGBA) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            let i = (y * w + x) * 4
            px[i] = c.r; px[i + 1] = c.g; px[i + 2] = c.b; px[i + 3] = 255
        }
        // Sky: banded gradient with ordered dithering between bands.
        let bands: [RGBA] = [RGBA(10, 8, 28), RGBA(18, 12, 44), RGBA(30, 16, 62), RGBA(48, 20, 80), RGBA(74, 26, 92), RGBA(104, 36, 96)]
        let bayer = [0, 2, 3, 1]
        for y in 0..<h {
            let f = CGFloat(y) / CGFloat(h) * CGFloat(bands.count - 1)
            let b = Int(f), t = f - CGFloat(b)
            for x in 0..<w {
                let d = CGFloat(bayer[(y & 1) * 2 + (x & 1)]) / 4
                put(x, y, bands[min(bands.count - 1, t > d ? b + 1 : b)])
            }
        }
        // Stars and a moon.
        for _ in 0..<(w * h / 180) {
            let x = r.int(w), y = r.int(h * 2 / 3)
            put(x, y, r.chance(0.2) ? RGBA(255, 240, 200) : RGBA(180, 190, 255))
        }
        let mx = w * 3 / 4, my = h / 6, mr = max(6, h / 16)
        for y in -mr...mr { for x in -mr...mr where x * x + y * y <= mr * mr {
            let crater = ((x + 3) * (x + 3) + (y - 2) * (y - 2) < mr * mr / 9) || ((x - 4) * (x - 4) + (y + 3) * (y + 3) < mr * mr / 16)
            put(mx + x, my + y, crater ? RGBA(210, 205, 190) : RGBA(245, 240, 220))
        } }
        // Three skyline layers, back to front.
        let layers: [(RGBA, RGBA, CGFloat, CGFloat)] = [
            (RGBA(36, 20, 66), RGBA(90, 60, 130), 0.45, 0.02),
            (RGBA(24, 14, 46), RGBA(255, 190, 90), 0.62, 0.08),
            (RGBA(12, 8, 26), RGBA(255, 220, 120), 0.8, 0.14),
        ]
        for (li, (body, lit, topFrac, litChance)) in layers.enumerated() {
            var x = -r.int(10)
            while x < w {
                let bw = 8 + r.int(18 + li * 6)
                let bh = Int(CGFloat(h) * (1 - topFrac) * r.range(0.4, 1.0)) + 6
                let top = h - bh
                for yy in top..<h { for xx in x..<(x + bw) { put(xx, yy, body) } }
                // antenna
                if r.chance(0.3) { for yy in (top - 5)..<top { put(x + bw / 2, yy, body) }; put(x + bw / 2, top - 6, RGBA(255, 60, 60)) }
                // windows
                var wy = top + 3
                while wy < h - 2 {
                    var wx = x + 2
                    while wx < x + bw - 2 {
                        if r.chance(litChance) { put(wx, wy, r.chance(0.15) ? RGBA(120, 230, 255) : lit) }
                        wx += 2
                    }
                    wy += 3
                }
                // neon sign on front buildings
                if li == 2, r.chance(0.18), bw > 12 {
                    let c = [RGBA(255, 60, 200), RGBA(60, 240, 255), RGBA(120, 255, 120)][r.int(3)]
                    let sy = top + 4 + r.int(max(1, bh / 3))
                    for xx in (x + 3)..<(x + bw - 3) { put(xx, sy, c); put(xx, sy + 3, c) }
                    put(x + 3, sy + 1, c); put(x + 3, sy + 2, c); put(x + bw - 4, sy + 1, c); put(x + bw - 4, sy + 2, c)
                }
                x += bw + r.int(3)
            }
        }
        return Tex.texture(Tex.image(px, w, h))
    }
}
