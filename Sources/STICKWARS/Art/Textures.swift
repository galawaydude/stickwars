import CoreGraphics
import SpriteKit

/// Procedural textures, generated once and cached by name. Main thread only.
enum Tex {
    private static var cache: [String: SKTexture] = [:]
    private static var pixelImages: [String: CGImage] = [:]
    private static var atlas: SKTextureAtlas?

    static let palette: [Character: RGBA] = [
        "k": RGBA(18, 18, 26), "d": RGBA(52, 56, 70), "g": RGBA(92, 98, 116), "l": RGBA(150, 158, 176),
        "s": RGBA(206, 212, 224), "w": RGBA(255, 255, 255), "c": RGBA(90, 235, 255), "b": RGBA(40, 120, 255),
        "n": RGBA(20, 60, 170), "y": RGBA(255, 214, 64), "o": RGBA(255, 140, 40), "r": RGBA(232, 58, 58),
        "p": RGBA(70, 30, 110), "m": RGBA(150, 70, 220), "v": RGBA(38, 14, 64), "e": RGBA(60, 200, 90),
        "h": RGBA(120, 255, 190), "a": RGBA(150, 250, 255),
    ]

    /// Makes an sRGB CGImage from a premultiplied RGBA8 buffer (row 0 = top).
    static func image(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage {
        let data = Data(px) as CFData
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func texture(_ img: CGImage, nearest: Bool = true) -> SKTexture {
        let t = SKTexture(cgImage: img)
        t.filteringMode = nearest ? .nearest : .linear
        return t
    }

    /// Pixel-art sprite from rows of palette characters ('.' or ' ' = transparent).
    static func pixels(_ name: String, _ rows: [String]) -> SKTexture {
        if let t = cache[name] { return t }
        let h = rows.count, w = rows.map(\.count).max() ?? 1
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = palette[ch] else { continue }
                let i = (y * w + x) * 4
                px[i] = c.r; px[i + 1] = c.g; px[i + 2] = c.b; px[i + 3] = 255
            }
        }
        let img = image(px, w, h)
        let t = texture(img)
        cache[name] = t
        if atlas == nil { pixelImages[name] = img }
        return t
    }

    /// Packs every pixel sprite generated so far into one atlas so they batch into fewer draw calls.
    static func packAtlas() {
        guard atlas == nil, !pixelImages.isEmpty else { return }
        var dict: [String: Any] = [:]
        for (k, img) in pixelImages { dict[k] = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)) }
        let a = SKTextureAtlas(dictionary: dict)
        for k in pixelImages.keys {
            let t = a.textureNamed(k)
            t.filteringMode = .nearest
            cache[k] = t
        }
        atlas = a
        pixelImages.removeAll()
    }

    /// Generic cached texture drawn with a CGContext (y up).
    static func drawn(_ name: String, _ w: Int, _ h: Int, nearest: Bool = false, _ draw: (CGContext) -> Void) -> SKTexture {
        if let t = cache[name] { return t }
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        let t = texture(ctx.makeImage()!, nearest: nearest)
        cache[name] = t
        return t
    }

    static var white: SKTexture {
        drawn("white", 2, 2, nearest: true) { $0.setFillColor(.white); $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
    }

    /// Horizontal white capsule; use with centerRect so the round caps don't stretch.
    static var capsule: SKTexture {
        drawn("capsule", 48, 16) { c in
            c.setFillColor(.white)
            c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 48, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil))
            c.fillPath()
        }
    }

    static var circle: SKTexture {
        drawn("circle", 32, 32) { c in c.setFillColor(.white); c.fillEllipse(in: CGRect(x: 0, y: 0, width: 32, height: 32)) }
    }

    /// Anchor for a pixel sprite so that pixel (x, y) (top-left origin) sits on the node position.
    static func anchor(_ tex: SKTexture, px x: Int, _ y: Int) -> CGPoint {
        let s = tex.size()
        return CGPoint(x: (CGFloat(x) + 0.5) / s.width, y: 1 - (CGFloat(y) + 0.5) / s.height)
    }
}
