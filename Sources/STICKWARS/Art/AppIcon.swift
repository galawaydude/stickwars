import AppKit

/// The app icon, drawn in code: an orange stick figure blasting a blue one off a broken screen,
/// over the game's night-city backdrop. `build.sh` renders it into AppIcon.icns.
enum AppIcon {
    static func image(_ px: Int) -> CGImage {
        let S = CGFloat(px) / 1024
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: S, y: S)
        ctx.interpolationQuality = .none

        // Squircle-ish tile with a soft shadow (macOS icon grid: 824 pt body inside 1024).
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(shape); ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.03, blue: 0.12, alpha: 1)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        let sky = CGGradient(colorsSpace: sRGB, colors: [CGColor(srgbRed: 0.42, green: 0.15, blue: 0.45, alpha: 1),
                                                         CGColor(srgbRed: 0.1, green: 0.06, blue: 0.25, alpha: 1),
                                                         CGColor(srgbRed: 0.04, green: 0.03, blue: 0.12, alpha: 1)] as CFArray,
                             locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

        // pixel stars and moon
        var r = RNG(99)
        ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.85, blue: 1, alpha: 1))
        for _ in 0..<40 { ctx.fill(CGRect(x: 100 + (r.unit() * 820).rounded(), y: 560 + (r.unit() * 360).rounded(), width: 12, height: 12)) }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.95, blue: 0.82, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 700, y: 730, width: 120, height: 120))

        // pixel skyline
        var x: CGFloat = 100
        while x < 924 {
            let w = CGFloat(48 + r.int(4) * 24), h = CGFloat(120 + r.int(9) * 24)
            ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.04, blue: 0.14, alpha: 1))
            ctx.fill(CGRect(x: x, y: 100, width: w, height: h))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.8, blue: 0.35, alpha: 1))
            var wy: CGFloat = 124
            while wy < 100 + h - 24 {
                var wx = x + 12
                while wx < x + w - 12 { if r.chance(0.3) { ctx.fill(CGRect(x: wx, y: wy, width: 12, height: 12)) }; wx += 24 }
                wy += 36
            }
            x += w + 12
        }

        // shattered "screen" slab the fighters stand on, with a crack
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.94, blue: 0.97, alpha: 1))
        let slab = CGMutablePath()
        slab.addLines(between: [CGPoint(x: 150, y: 250), CGPoint(x: 880, y: 250), CGPoint(x: 880, y: 300), CGPoint(x: 610, y: 300),
                                CGPoint(x: 585, y: 272), CGPoint(x: 560, y: 300), CGPoint(x: 150, y: 300)])
        slab.closeSubpath()
        ctx.addPath(slab); ctx.fillPath()
        ctx.setFillColor(CGColor(srgbRed: 0.7, green: 0.72, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 150, y: 250, width: 730, height: 10))

        func stick(_ color: CGColor, _ pts: [(CGPoint, CGPoint)], head: CGPoint, w: CGFloat, headR: CGFloat) {
            ctx.setStrokeColor(color); ctx.setLineWidth(w); ctx.setLineCap(.round)
            for (a, b) in pts { ctx.move(to: a); ctx.addLine(to: b) }
            ctx.strokePath()
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: head.x - headR, y: head.y - headR, width: headR * 2, height: headR * 2))
        }

        // tracer from the gun to the blue fighter
        ctx.setStrokeColor(CGColor(srgbRed: 0.55, green: 0.97, blue: 1, alpha: 0.95)); ctx.setLineWidth(14); ctx.setLineCap(.butt)
        ctx.move(to: CGPoint(x: 690, y: 603)); ctx.addLine(to: CGPoint(x: 775, y: 535)); ctx.strokePath()

        // blue fighter, knocked back
        let blue = CGColor(srgbRed: 0.23, green: 0.48, blue: 0.94, alpha: 1)
        let bp = CGPoint(x: 790, y: 470)
        stick(blue, [(bp, CGPoint(x: 830, y: 390)), (CGPoint(x: 830, y: 390), CGPoint(x: 880, y: 330)),
                     (bp, CGPoint(x: 760, y: 380)), (CGPoint(x: 760, y: 380), CGPoint(x: 790, y: 310)),
                     (bp, CGPoint(x: 820, y: 590)),
                     (CGPoint(x: 815, y: 575), CGPoint(x: 880, y: 620)), (CGPoint(x: 815, y: 575), CGPoint(x: 760, y: 640))],
              head: CGPoint(x: 850, y: 655), w: 34, headR: 42)
        // impact burst: pixel squares
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.9, blue: 0.4, alpha: 1))
        for (dx, dy) in [(0, 0), (24, 12), (-24, 24), (12, -24), (36, -12), (-12, -36), (48, 24)] {
            ctx.fill(CGRect(x: 760 + CGFloat(dx), y: 520 + CGFloat(dy), width: 20, height: 20))
        }

        // orange fighter, aiming
        let orange = CGColor(srgbRed: 0xF0 / 255, green: 0x7D / 255, blue: 0x2A / 255, alpha: 1)
        let hip = CGPoint(x: 330, y: 420), neck = CGPoint(x: 360, y: 575), sh = CGPoint(x: 356, y: 560)
        stick(orange, [(hip, CGPoint(x: 400, y: 345)), (CGPoint(x: 400, y: 345), CGPoint(x: 410, y: 300)),
                       (hip, CGPoint(x: 270, y: 350)), (CGPoint(x: 270, y: 350), CGPoint(x: 240, y: 300)),
                       (hip, neck),
                       (sh, CGPoint(x: 430, y: 560)), (CGPoint(x: 430, y: 560), CGPoint(x: 480, y: 565))],
              head: CGPoint(x: 370, y: 640), w: 42, headR: 52)

        // pixel blaster (the game's own sprite), 11 pt per art pixel
        let art = Weapons.all[5].art
        let px7: CGFloat = 11
        let gx = CGPoint(x: 480 - CGFloat(Weapons.all[5].grip.0) * px7, y: 565 + CGFloat(Weapons.all[5].grip.1) * px7)
        for (row, line) in art.enumerated() {
            for (col, ch) in line.enumerated() {
                guard let c = Tex.palette[ch] else { continue }
                ctx.setFillColor(CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1))
                ctx.fill(CGRect(x: gx.x + CGFloat(col) * px7, y: gx.y - CGFloat(row + 1) * px7, width: px7, height: px7))
            }
        }
        ctx.restoreGState()
        return ctx.makeImage()!
    }

    /// Writes a .iconset folder (for iconutil).
    static func writeIconset(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                let rep = NSBitmapImageRep(cgImage: image(base * scale))
                try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
            }
        }
    }

    static var nsImage: NSImage { NSImage(cgImage: image(512), size: NSSize(width: 512, height: 512)) }
}
