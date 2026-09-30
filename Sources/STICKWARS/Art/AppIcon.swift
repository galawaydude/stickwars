import AppKit

/// The app icon, drawn in code: an orange stickman bursting out through a shattered app window,
/// black space and stars behind the crack, glass shards flying. `build.sh` renders it into AppIcon.icns.
enum AppIcon {
    static func image(_ px: Int) -> CGImage {
        let S = CGFloat(px) / 1024
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: S, y: S)
        func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
        }
        func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
            let p = CGMutablePath()
            p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) }); p.closeSubpath(); return p
        }

        // macOS icon body (824 pt inside 1024) with a soft drop shadow
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(shape); ctx.setFillColor(col(0x15131F)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        let bg = CGGradient(colorsSpace: sRGB, colors: [col(0x2A2440), col(0x121019), col(0x07070B)] as CFArray, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

        // the app window, slightly tilted
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 500)
        ctx.rotate(by: -0.08)
        let win = CGRect(x: -300, y: -230, width: 600, height: 440)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(gray: 0, alpha: 0.6))
        ctx.addPath(CGPath(roundedRect: win, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.setFillColor(col(0xEEF0F6)); ctx.fillPath()
        ctx.restoreGState()
        // title bar + traffic lights + a few "content" lines
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: win, cornerWidth: 34, cornerHeight: 34, transform: nil)); ctx.clip()
        ctx.setFillColor(col(0xD9DCE6)); ctx.fill(CGRect(x: win.minX, y: win.maxY - 62, width: win.width, height: 62))
        ctx.restoreGState()
        for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            ctx.setFillColor(col(UInt32(c)))
            ctx.fillEllipse(in: CGRect(x: win.minX + 30 + CGFloat(i) * 40, y: win.maxY - 44, width: 26, height: 26))
        }
        ctx.setFillColor(col(0xB9BDCB))
        for (y, w) in [(118.0, 300.0), (82.0, 420.0), (46.0, 360.0)] { ctx.fill(CGRect(x: win.minX + 40, y: CGFloat(y), width: CGFloat(w), height: 18)) }
        ctx.setFillColor(col(0x3B82F6)); ctx.fill(CGRect(x: win.minX + 40, y: -186, width: 150, height: 46))

        // the crack: a jagged hole into black space with stars
        let hole = poly([(-150, -120), (-60, -175), (40, -140), (120, -190), (170, -90), (150, 10), (200, 90), (80, 70),
                         (20, 150), (-60, 70), (-160, 90), (-120, -10), (-200, -40)])
        ctx.saveGState()
        ctx.addPath(hole); ctx.clip()
        ctx.setFillColor(col(0x040407)); ctx.fill(CGRect(x: -300, y: -300, width: 600, height: 600))
        var r = RNG(11)
        for _ in 0..<60 {
            let s: CGFloat = r.chance(0.15) ? 7 : 4
            ctx.setFillColor(col(r.chance(0.2) ? 0xFFF1D0 : 0xDDE6FF, r.range(0.5, 1)))
            ctx.fill(CGRect(x: r.range(-210, 210), y: r.range(-200, 160), width: s, height: s))
        }
        ctx.restoreGState()
        // crack lines radiating from the hole
        ctx.setStrokeColor(col(0x2A2D3A, 0.85)); ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for line in [[(170.0, -90.0), (240.0, -120.0), (285.0, -95.0)], [(-200, -40), (-260, -70), (-290, -40)],
                     [(20, 150), (40, 195), (10, 208)], [(-150, -120), (-190, -190), (-240, -205)], [(200, 90), (255, 130)]] {
            ctx.move(to: CGPoint(x: line[0].0, y: line[0].1))
            for p in line.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
            ctx.strokePath()
        }
        ctx.restoreGState()

        // glass shards flying out toward the top right
        for (pts, a) in [([(640.0, 700.0), (700, 740), (668, 672)], 0.95), ([(724, 640), (790, 668), (746, 606)], 0.9),
                         ([(600, 780), (636, 830), (650, 772)], 0.85), ([(790, 760), (842, 790), (818, 736)], 0.8),
                         ([(360, 690), (318, 720), (340, 668)], 0.8), ([(700, 820), (730, 866), (748, 812)], 0.75)] as [([(CGFloat, CGFloat)], CGFloat)] {
            ctx.addPath(poly(pts)); ctx.setFillColor(col(0xEEF0F6, a)); ctx.fillPath()
            ctx.addPath(poly(pts)); ctx.setStrokeColor(col(0x9AA3B8, a)); ctx.setLineWidth(3); ctx.strokePath()
        }

        // the stickman leaping out of the crack, blaster first
        let orange = col(0xF07D2A)
        ctx.setStrokeColor(orange); ctx.setLineWidth(44); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let hip = CGPoint(x: 455, y: 450), neck = CGPoint(x: 555, y: 575), sh = CGPoint(x: 545, y: 562)
        let segs: [(CGPoint, CGPoint)] = [
            (hip, neck),
            (hip, CGPoint(x: 385, y: 432)), (CGPoint(x: 385, y: 432), CGPoint(x: 318, y: 468)),   // back leg kicking out
            (hip, CGPoint(x: 468, y: 362)), (CGPoint(x: 468, y: 362), CGPoint(x: 405, y: 322)),   // front leg tucked
            (sh, CGPoint(x: 630, y: 585)), (CGPoint(x: 630, y: 585), CGPoint(x: 708, y: 618)),    // gun arm
            (sh, CGPoint(x: 615, y: 540)), (CGPoint(x: 615, y: 540), CGPoint(x: 690, y: 596)),    // support arm
        ]
        for (a, b) in segs { ctx.move(to: a); ctx.addLine(to: b) }
        ctx.strokePath()
        ctx.setFillColor(orange)
        ctx.fillEllipse(in: CGRect(x: 548, y: 590, width: 104, height: 104))

        // the game's blaster (vector art) in his hands
        let art = GunArts.blaster, gs: CGFloat = 3.4
        ctx.saveGState()
        ctx.translateBy(x: 708, y: 618)
        ctx.rotate(by: 0.35)
        let hgt = art.svg.size.height * gs
        art.svg.draw(in: ctx, scale: gs, height: hgt,
                     origin: CGPoint(x: -(art.grip.x + art.svg.pad) * gs, y: -hgt + (art.grip.y + art.svg.pad) * gs))
        ctx.restoreGState()
        // muzzle flash and a cyan bolt heading out of frame
        ctx.setStrokeColor(col(0x8CF4FF)); ctx.setLineWidth(12); ctx.setLineCap(.butt)
        ctx.move(to: CGPoint(x: 850, y: 716)); ctx.addLine(to: CGPoint(x: 940, y: 752)); ctx.strokePath()
        ctx.setFillColor(col(0xFFD640))
        for (dx, dy, s) in [(0.0, 0.0, 26.0), (22, 16, 16), (-8, 26, 14), (24, -14, 12)] {
            ctx.fill(CGRect(x: 824 + CGFloat(dx), y: 700 + CGFloat(dy), width: CGFloat(s), height: CGFloat(s)))
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
