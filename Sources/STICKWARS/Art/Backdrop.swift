import SpriteKit

/// What's behind the screen: black void space, revealed wherever the snapshot gets destroyed.
/// Pixel art at 2 points per art pixel: near-black, scattered stars of varied brightness, a few
/// bright ones with a cross glint.
enum Backdrop {
    static func texture(size: CGSize, seed: UInt64 = 7) -> SKTexture {
        let w = max(8, Int(size.width / 2)), h = max(8, Int(size.height / 2))
        var r = RNG(seed)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        func put(_ x: Int, _ y: Int, _ c: RGBA) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            let i = (y * w + x) * 4
            px[i] = c.r; px[i + 1] = c.g; px[i + 2] = c.b; px[i + 3] = 255
        }
        // void
        for y in 0..<h { for x in 0..<w { put(x, y, RGBA(3, 3, 6)) } }
        // faint distant dust: very dark specks, barely there
        for _ in 0..<(w * h / 60) { put(r.int(w), r.int(h), RGBA(10, 10, 16)) }
        // stars: mostly dim, some mid, a few bright
        for _ in 0..<(w * h / 140) {
            let x = r.int(w), y = r.int(h)
            let roll = r.unit()
            if roll < 0.72 {
                let v = UInt8(55 + r.int(50)); put(x, y, RGBA(v, v, UInt8(min(255, Int(v) + 15))))
            } else if roll < 0.97 {
                let v = UInt8(140 + r.int(70)); put(x, y, RGBA(v, v, UInt8(min(255, Int(v) + 20))))
            } else {
                // bright star with a small cross glint
                let c = r.chance(0.25) ? RGBA(255, 236, 200) : RGBA(235, 240, 255)
                put(x, y, c)
                let g = RGBA(90, 95, 120)
                put(x - 1, y, g); put(x + 1, y, g); put(x, y - 1, g); put(x, y + 1, g)
            }
        }
        return Tex.texture(Tex.image(px, w, h))
    }
}
