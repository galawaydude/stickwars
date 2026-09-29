import AppKit

/// A synthetic desktop with three overlapping app windows (code editor, browser article, chat) plus
/// menu bar and Dock, used for headless demo recordings. Nothing personal is ever captured.
enum FakeDesktop {
    // window frames, global top-left points, front to back
    static func windows(size: CGSize) -> [WindowInfo] {
        let (a, b, c) = frames(size)
        return [WindowInfo(id: 1, pid: 1, owner: "Safari", bounds: b, layer: 0),
                WindowInfo(id: 2, pid: 2, owner: "Chat", bounds: c, layer: 0),
                WindowInfo(id: 3, pid: 3, owner: "Code", bounds: a, layer: 0)]
    }

    private static func frames(_ s: CGSize) -> (CGRect, CGRect, CGRect) {
        (CGRect(x: 36, y: 64, width: s.width * 0.47, height: s.height * 0.6),
         CGRect(x: s.width * 0.33, y: s.height * 0.2, width: s.width * 0.42, height: s.height * 0.62),
         CGRect(x: s.width * 0.71, y: 90, width: s.width * 0.27, height: s.height * 0.66))
    }

    static func image(size: CGSize, scale: CGFloat = 2) -> CGImage {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
        }
        func fill(_ r: CGRect, _ c: NSColor, _ radius: CGFloat = 0) { c.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: NSColor, bold: Bool = false, mono: Bool = false) {
            let f = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular) : (bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size))
            (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: f, .foregroundColor: c])
        }
        func window(_ r: CGRect, title: String, dark: Bool) {
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow(); sh.shadowBlurRadius = 24; sh.shadowOffset = NSSize(width: 0, height: -8); sh.shadowColor = NSColor(white: 0, alpha: 0.45); sh.set()
            fill(r, dark ? rgb(0x1E1F24) : .white, 11)
            NSGraphicsContext.restoreGraphicsState()
            fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 34), dark ? rgb(0x2A2C33) : rgb(0xEDEDF0), 11)
            fill(CGRect(x: r.minX, y: r.minY + 22, width: r.width, height: 12), dark ? rgb(0x2A2C33) : rgb(0xEDEDF0))
            for (i, c) in [rgb(0xFF5F57), rgb(0xFEBC2E), rgb(0x28C840)].enumerated() {
                c.setFill(); NSBezierPath(ovalIn: CGRect(x: r.minX + 13 + CGFloat(i) * 20, y: r.minY + 11, width: 12, height: 12)).fill()
            }
            text(title, r.midX - CGFloat(title.count) * 3.3, r.minY + 9, 13, dark ? rgb(0xB9BCC6) : rgb(0x55575F), bold: true)
        }

        // wallpaper
        NSGradient(colors: [rgb(0x1B2A6B), rgb(0x5B2A86), rgb(0xC0487A)])!.draw(in: CGRect(origin: .zero, size: size), angle: -60)
        for i in 0..<5 {
            let p = NSBezierPath()
            p.move(to: CGPoint(x: 0, y: size.height * (0.35 + CGFloat(i) * 0.12)))
            p.curve(to: CGPoint(x: size.width, y: size.height * (0.25 + CGFloat(i) * 0.13)),
                    controlPoint1: CGPoint(x: size.width * 0.3, y: size.height * (0.1 + CGFloat(i) * 0.1)),
                    controlPoint2: CGPoint(x: size.width * 0.6, y: size.height * (0.6 + CGFloat(i) * 0.05)))
            p.lineWidth = 60; rgb(0xFFFFFF, 0.05).setStroke(); p.stroke()
        }
        // menu bar
        fill(CGRect(x: 0, y: 0, width: size.width, height: 26), rgb(0x0E0E14, 0.55))
        text("  Safari    File    Edit    View    History    Bookmarks    Window    Help", 10, 5, 13, .white, bold: false)
        text("100%   Tue 9:41 AM", size.width - 150, 5, 13, .white)

        let (a, b, c) = frames(size)

        // A: code editor (back)
        window(a, title: "game.swift — stickwars", dark: true)
        fill(CGRect(x: a.minX, y: a.minY + 34, width: 150, height: a.height - 34), rgb(0x18191D))
        for (i, f) in ["▾ Sources", "   App", "   Game", "   Weapons", "   Fighter", "   HUD", "  README.md", "  build.sh"].enumerated() {
            text(f, a.minX + 12, a.minY + 48 + CGFloat(i) * 22, 12, rgb(0xA8ABB6))
        }
        let code: [[(String, UInt32)]] = [
            [("func ", 0xC678DD), ("openSingularity", 0x61AFEF), ("(at p: CGPoint) {", 0xE6E6E6)],
            [("    let ", 0xC678DD), ("reach", 0xE5C07B), (": CGFloat = ", 0xE6E6E6), ("250", 0xD19A66)],
            [("    for ", 0xC678DD), ("f ", 0xE6E6E6), ("in ", 0xC678DD), ("fighters ", 0xE6E6E6), ("where ", 0xC678DD), ("f.alive {", 0xE6E6E6)],
            [("        f.vel += pull(f, toward: p)", 0xE6E6E6)],
            [("    }", 0xE6E6E6)],
            [("    // rip letters off the screen", 0x7F848E)],
            [("    level.", 0xE6E6E6), ("collect", 0x61AFEF), ("(near: p) { ", 0xE6E6E6), ("breakLoose", 0x61AFEF), ("($0) }", 0xE6E6E6)],
            [("    shake(", 0xE6E6E6), ("4", 0xD19A66), (")", 0xE6E6E6)],
            [("}", 0xE6E6E6)],
            [("", 0)],
            [("struct ", 0xC678DD), ("Fighter", 0xE5C07B), (" {", 0xE6E6E6)],
            [("    var ", 0xC678DD), ("hp", 0xE6E6E6), (": CGFloat = ", 0xE6E6E6), ("100", 0xD19A66)],
            [("    var ", 0xC678DD), ("armor", 0xE6E6E6), (": CGFloat = ", 0xE6E6E6), ("0", 0xD19A66)],
            [("    var ", 0xC678DD), ("weapon", 0xE6E6E6), (" = ", 0xE6E6E6), (".blackHole", 0x98C379)],
            [("}", 0xE6E6E6)],
        ]
        for (i, line) in code.enumerated() {
            let y = a.minY + 48 + CGFloat(i) * 22
            guard y < a.maxY - 20 else { break }
            text("\(i + 1)", a.minX + 162, y, 12, rgb(0x5C6370), mono: true)
            var x = a.minX + 192
            for (s, col) in line where !s.isEmpty {
                text(s, x, y, 13, rgb(col), mono: true)
                x += CGFloat(s.count) * 7.8
            }
        }

        // C: chat app (middle)
        window(c, title: "#stick-fights", dark: false)
        fill(CGRect(x: c.minX, y: c.minY + 34, width: 64, height: c.height - 34), rgb(0x3F0E40))
        for i in 0..<4 { fill(CGRect(x: c.minX + 14, y: c.minY + 50 + CGFloat(i) * 50, width: 36, height: 36), rgb([0xE8912D, 0x2EB67D, 0x36C5F0, 0xECB22E][i]), 9) }
        let msgs = [("Ava", "did you see the letters fly??", 0xE8912D), ("Ben", "black hole gun is insane", 0x2EB67D),
                    ("Cleo", "my whole inbox is on the floor", 0x36C5F0), ("Dev", "who blew up the dock", 0xECB22E),
                    ("Ava", "rematch. first to 10.", 0xE8912D)]
        for (i, m) in msgs.enumerated() {
            let y = c.minY + 56 + CGFloat(i) * 70
            guard y < c.maxY - 90 else { break }
            fill(CGRect(x: c.minX + 80, y: y, width: 34, height: 34), rgb(UInt32(m.2)), 8)
            text(m.0, c.minX + 124, y, 14, rgb(0x1D1C1D), bold: true)
            text(m.1, c.minX + 124, y + 20, 13, rgb(0x1D1C1D))
        }
        fill(CGRect(x: c.minX + 78, y: c.maxY - 58, width: c.width - 94, height: 40), .white, 8)
        rgb(0xBBBBBB).setStroke(); NSBezierPath(roundedRect: CGRect(x: c.minX + 78, y: c.maxY - 58, width: c.width - 94, height: 40), xRadius: 8, yRadius: 8).stroke()
        text("Message #stick-fights", c.minX + 92, c.maxY - 46, 13, rgb(0x9A9A9A))

        // B: browser article (front)
        window(b, title: "The Desktop Is a Battlefield", dark: false)
        let url = CGRect(x: b.midX - 170, y: b.minY + 5, width: 340, height: 24)
        fill(url, .white, 7); text("stickwars.dev/blog/destroy-your-desktop", url.minX + 12, url.minY + 4, 12, rgb(0x666666))
        var y = b.minY + 60
        text("Destroy Your Desktop", b.minX + 32, y, 30, rgb(0x111111), bold: true); y += 48
        for line in ["Every word on this page is a platform. Shoot the", "letters out one at a time and watch them pile up.",
                     "Rockets blast craters that reveal the city behind", "the screen. Black holes eat whole paragraphs."] {
            text(line, b.minX + 32, y, 15, rgb(0x333333)); y += 23
        }
        y += 12
        var bx = b.minX + 32
        for (label, col) in [("Play now", 0x0A84FF), ("Download", 0x30D158), ("Share", 0x8E8E93)] {
            fill(CGRect(x: bx, y: y, width: 118, height: 36), rgb(UInt32(col)), 9)
            text(label, bx + 24, y + 9, 15, .white, bold: true); bx += 134
        }
        y += 58
        let photo = CGRect(x: b.minX + 32, y: y, width: b.width - 64, height: min(170, b.maxY - y - 20))
        NSGradient(colors: [rgb(0xFF9A5A), rgb(0x6A3A9A)])!.draw(in: photo, angle: -90)
        rgb(0xFFE08A).setFill(); NSBezierPath(ovalIn: CGRect(x: photo.maxX - 120, y: photo.minY + 30, width: 64, height: 64)).fill()
        rgb(0x22382A).setFill()
        let hill = NSBezierPath(); hill.move(to: CGPoint(x: photo.minX, y: photo.maxY))
        for i in 0...24 { hill.line(to: CGPoint(x: photo.minX + CGFloat(i) * photo.width / 24, y: photo.maxY - 40 - 26 * sin(CGFloat(i) * 0.7))) }
        hill.line(to: CGPoint(x: photo.maxX, y: photo.maxY)); hill.close(); hill.fill()

        // Dock
        let dock = CGRect(x: size.width / 2 - 250, y: size.height - 72, width: 500, height: 64)
        fill(dock, rgb(0xFFFFFF, 0.28), 18)
        for i in 0..<8 {
            fill(CGRect(x: dock.minX + 14 + CGFloat(i) * 60, y: dock.minY + 8, width: 48, height: 48),
                 rgb([0x0A84FF, 0xFF453A, 0x30D158, 0xFFD60A, 0xBF5AF2, 0xFF9F0A, 0x64D2FF, 0xAC8E68][i]), 12)
        }
        return ctx.makeImage()!
    }
}
