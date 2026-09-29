import SpriteKit

/// 3x5 pixel font with a 1-px dark outline. Glyphs are 5 rows of bit masks (MSB = left column).
enum PixelFont {
    private static let glyphs: [Character: (w: Int, rows: [UInt8])] = {
        let g3: [Character: [UInt8]] = [
            "A": [2, 5, 7, 5, 5], "B": [6, 5, 6, 5, 6], "C": [3, 4, 4, 4, 3], "D": [6, 5, 5, 5, 6], "E": [7, 4, 6, 4, 7],
            "F": [7, 4, 6, 4, 4], "G": [3, 4, 5, 5, 3], "H": [5, 5, 7, 5, 5], "I": [7, 2, 2, 2, 7], "J": [1, 1, 1, 5, 2],
            "K": [5, 5, 6, 5, 5], "L": [4, 4, 4, 4, 7], "M": [5, 7, 7, 5, 5], "N": [6, 5, 5, 5, 5], "O": [2, 5, 5, 5, 2],
            "P": [6, 5, 6, 4, 4], "Q": [2, 5, 5, 6, 3], "R": [6, 5, 6, 5, 5], "S": [3, 4, 2, 1, 6], "T": [7, 2, 2, 2, 2],
            "U": [5, 5, 5, 5, 7], "V": [5, 5, 5, 5, 2], "W": [5, 5, 7, 7, 5], "X": [5, 5, 2, 5, 5], "Y": [5, 5, 2, 2, 2],
            "Z": [7, 1, 2, 4, 7], "0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [6, 1, 2, 4, 7], "3": [6, 1, 2, 1, 6],
            "4": [5, 5, 7, 1, 1], "5": [7, 4, 6, 1, 6], "6": [3, 4, 6, 5, 2], "7": [7, 1, 2, 2, 2], "8": [7, 5, 7, 5, 7],
            "9": [2, 5, 3, 1, 6], " ": [0, 0, 0, 0, 0], ".": [0, 0, 0, 0, 2], ",": [0, 0, 0, 2, 4], ":": [0, 2, 0, 2, 0],
            "!": [2, 2, 2, 0, 2], "?": [6, 1, 2, 0, 2], "-": [0, 0, 7, 0, 0], "+": [0, 2, 7, 2, 0], "/": [1, 1, 2, 4, 4],
            "'": [2, 2, 0, 0, 0], "(": [1, 2, 2, 2, 1], ")": [4, 2, 2, 2, 4], "<": [1, 2, 4, 2, 1], ">": [4, 2, 1, 2, 4],
            "=": [0, 7, 0, 7, 0], "_": [0, 0, 0, 0, 7], "#": [5, 7, 5, 7, 5], "*": [5, 2, 7, 2, 5], "[": [3, 2, 2, 2, 3],
            "]": [6, 2, 2, 2, 6], "|": [2, 2, 2, 2, 2],
        ]
        var out = g3.mapValues { (w: 3, rows: $0) }
        out["%"] = (5, [25, 26, 4, 11, 19]) // 5 wide, or it reads as "Z"
        return out
    }()

    private static var cache: [String: SKTexture] = [:]

    /// Width in font pixels (without outline).
    static func width(_ s: String) -> Int {
        var w = 0
        for ch in s.uppercased() { w += (glyphs[ch]?.w ?? 3) + 1 }
        return max(0, w - 1)
    }

    /// White glyphs with a dark outline; tint with sprite colour (colorBlendFactor = 1).
    static func texture(_ s: String) -> SKTexture {
        if let t = cache[s] { return t }
        if cache.count > 600 { cache.removeAll(keepingCapacity: true) }
        let text = s.uppercased()
        let w = width(text) + 2, h = 7
        var fill = [Bool](repeating: false, count: w * h)
        var x = 1
        for ch in text {
            let g = glyphs[ch] ?? glyphs["?"]!
            for r in 0..<5 {
                for c in 0..<g.w where g.rows[r] >> UInt8(g.w - 1 - c) & 1 == 1 { fill[(r + 1) * w + x + c] = true }
            }
            x += g.w + 1
        }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if fill[y * w + x] {
                    px[i] = 255; px[i + 1] = 255; px[i + 2] = 255; px[i + 3] = 255
                } else {
                    var near = false
                    for dy in -1...1 { for dx in -1...1 {
                        let xx = x + dx, yy = y + dy
                        if xx >= 0, yy >= 0, xx < w, yy < h, fill[yy * w + xx] { near = true }
                    } }
                    if near { px[i] = 16; px[i + 1] = 16; px[i + 2] = 22; px[i + 3] = 255 }
                }
            }
        }
        let t = Tex.texture(Tex.image(px, w, h))
        cache[s] = t
        return t
    }

    /// Sprite showing `s`, `scale` points per font pixel.
    static func label(_ s: String, scale: CGFloat = 2, color: SKColor = .white) -> SKSpriteNode {
        let n = SKSpriteNode(texture: nil)
        set(n, s, scale: scale, color: color)
        return n
    }

    static func set(_ n: SKSpriteNode, _ s: String, scale: CGFloat = 2, color: SKColor? = nil) {
        let t = texture(s)
        if n.texture !== t {
            n.texture = t
            n.size = CGSize(width: t.size().width * scale, height: t.size().height * scale)
        }
        if let color { n.color = color; n.colorBlendFactor = 1 }
    }
}
