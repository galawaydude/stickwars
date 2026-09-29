import AppKit

/// Screen-sized synthetic "screenshot" for headless tests: a browser-like window with text,
/// a photo-like gradient, buttons, icons and a dock.
enum FakePage {
    static func image(size: CGSize, scale: CGFloat = 2) -> CGImage {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        // flip so we draw top-left like a screen
        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
        let g = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        defer { NSGraphicsContext.restoreGraphicsState() }

        func fill(_ r: CGRect, _ c: NSColor, radius: CGFloat = 0) {
            c.setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        }
        func stroke(_ r: CGRect, _ c: NSColor, radius: CGFloat = 0) {
            c.setStroke()
            let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius); p.lineWidth = 1; p.stroke()
        }
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: NSColor = .black, bold: Bool = false) {
            let f = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
            (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: f, .foregroundColor: c])
        }

        // desktop wallpaper
        let wall = NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.35, blue: 0.6, alpha: 1), ending: NSColor(srgbRed: 0.6, green: 0.3, blue: 0.5, alpha: 1))!
        wall.draw(in: CGRect(origin: .zero, size: size), angle: 90)
        // menu bar
        fill(CGRect(x: 0, y: 0, width: size.width, height: 24), NSColor(white: 0.96, alpha: 1))
        text("", 14, 4, 14); text("Safari   File   Edit   View   History   Bookmarks", 40, 4, 13, bold: false)
        text("Tue 12:34", size.width - 90, 4, 13)

        // browser window
        let win = CGRect(x: 60, y: 50, width: size.width - 120, height: size.height - 170)
        fill(win, .white, radius: 10)
        fill(CGRect(x: win.minX, y: win.minY, width: win.width, height: 52), NSColor(white: 0.93, alpha: 1), radius: 10)
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: CGRect(x: win.minX + 16 + CGFloat(i) * 20, y: win.minY + 18, width: 12, height: 12)).fill()
        }
        // search box
        let search = CGRect(x: win.midX - 260, y: win.minY + 12, width: 520, height: 28)
        fill(search, .white, radius: 8); stroke(search, NSColor(white: 0.75, alpha: 1), radius: 8)
        text("destroy.spritefusion.com", search.minX + 12, search.minY + 6, 13, .darkGray)

        // content
        var y = win.minY + 80
        text("Destroy Any Desktop", win.minX + 40, y, 34, bold: true); y += 56
        let para = [
            "Every word on this page is a platform. Shoot the letters out one at a time and",
            "watch them tumble down with real rigid-body physics. Rockets blast craters that",
            "reveal the city behind the screen. Grenades bounce off buttons and icons alike.",
            "Stand on a search box, wall-jump off a photo, and drop through a line of text.",
        ]
        for line in para { text(line, win.minX + 40, y, 15, NSColor(white: 0.15, alpha: 1)); y += 24 }
        y += 16
        // buttons
        var bx = win.minX + 40
        for (label, c) in [("Sign up", NSColor.systemBlue), ("Log in", NSColor.systemGray), ("Download", NSColor.systemGreen)] {
            let r = CGRect(x: bx, y: y, width: 120, height: 36)
            fill(r, c, radius: 8)
            text(label, r.minX + 26, r.minY + 9, 15, .white, bold: true)
            bx += 140
        }
        y += 70
        // photo-like gradient with a sun and hills
        let photo = CGRect(x: win.minX + 40, y: y, width: 420, height: 240)
        NSGradient(colors: [NSColor(srgbRed: 1, green: 0.55, blue: 0.3, alpha: 1), NSColor(srgbRed: 0.35, green: 0.2, blue: 0.55, alpha: 1)])!
            .draw(in: photo, angle: -90)
        NSColor(srgbRed: 1, green: 0.9, blue: 0.5, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: photo.minX + 260, y: photo.minY + 50, width: 70, height: 70)).fill()
        NSColor(srgbRed: 0.15, green: 0.3, blue: 0.2, alpha: 1).setFill()
        let hill = NSBezierPath(); hill.move(to: CGPoint(x: photo.minX, y: photo.maxY))
        for i in 0...20 { hill.line(to: CGPoint(x: photo.minX + CGFloat(i) * 21, y: photo.maxY - 50 - 30 * sin(CGFloat(i) * 0.6))) }
        hill.line(to: CGPoint(x: photo.maxX, y: photo.maxY)); hill.close(); hill.fill()

        // side column with headings, list and icons
        var sy = photo.minY
        let sx = photo.maxX + 60
        text("Weapons", sx, sy, 22, bold: true); sy += 36
        for s in ["Pistol  ·  SMG  ·  Shotgun", "Rocket launcher and plasma rifle", "Heavy blaster, laser rifle", "Grenades on right click"] {
            text("•  " + s, sx, sy, 14, NSColor(white: 0.2, alpha: 1)); sy += 22
        }
        sy += 20
        let iconColors: [NSColor] = [.systemPink, .systemOrange, .systemTeal, .systemIndigo, .systemMint]
        for (i, c) in iconColors.enumerated() {
            let r = CGRect(x: sx + CGFloat(i) * 64, y: sy, width: 48, height: 48)
            fill(r, c, radius: 12)
            NSColor.white.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 14, dy: 14)).fill()
        }
        sy += 72
        let divider = CGRect(x: sx, y: sy, width: 360, height: 1)
        fill(divider, NSColor(white: 0.8, alpha: 1))
        text("Footer text · Privacy · Terms · Help", sx, sy + 12, 12, .gray)

        // dock
        let dock = CGRect(x: size.width / 2 - 260, y: size.height - 74, width: 520, height: 66)
        fill(dock, NSColor(white: 1, alpha: 0.35), radius: 18)
        for i in 0..<8 {
            let r = CGRect(x: dock.minX + 12 + CGFloat(i) * 63, y: dock.minY + 8, width: 50, height: 50)
            fill(r, [NSColor.systemBlue, .systemRed, .systemGreen, .systemYellow, .systemPurple, .systemOrange, .systemCyan, .systemBrown][i], radius: 12)
        }
        return ctx.makeImage()!
    }

    /// Windows matching the drawing, for title-bar ledges (global top-left points).
    static func windows(size: CGSize) -> [WindowInfo] {
        [WindowInfo(id: 1, pid: 1, owner: "Safari", bounds: CGRect(x: 60, y: 50, width: size.width - 120, height: size.height - 170), layer: 0)]
    }
}
