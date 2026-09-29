import SpriteKit

extension GameScene {
    func setKey(_ code: UInt16, _ down: Bool) { key(code, down: down) }

    func stateDump() -> String {
        var s = "scene \(Int(size.width))x\(Int(size.height)) app=\(appName) simTime=\(String(format: "%.2f", simTime))"
        if let c = canvas { s += " canvas \(c.pw)x\(c.ph) tiles \(c.tilesX * c.tilesY) lastDirty \(c.lastFlushCount)" }
        var kinds = [Int](repeating: 0, count: 5), walls = 0
        for e in level.elements where e.state == .solid { kinds[Int(e.kind.rawValue)] += 1; if e.wall { walls += 1 } }
        s += String(format: "\nelements solid=%d text=%d control=%d image=%d line=%d ledge=%d walls=%d extract=%.1fms %@",
                    level.solidCount, kinds[0], kinds[1], kinds[2], kinds[3], kinds[4], walls, extractMs, extractInfo)
        s += "\n" + extraState()
        for f in fighters {
            s += String(format: "\nfighter %@ pos=(%.1f,%.1f) vel=(%.0f,%.0f) grounded=%d wall=%d hp=%.0f alive=%d kills=%d weapon=%d",
                        f.name, f.pos.x, f.pos.y, f.vel.x, f.vel.y, f.grounded ? 1 : 0, f.wallDir, f.hp, f.alive ? 1 : 0, f.kills, f.weapons.current)
        }
        return s
    }

    /// Scene-specific harness commands; nil = unknown.
    func devCommand(_ cmd: String, _ a: [String]) -> String? {
        func n(_ i: Int) -> CGFloat { i < a.count ? CGFloat(Double(a[i]) ?? 0) : 0 }
        switch cmd {
        case "mouse": mouse = CGPoint(x: n(0), y: n(1)); return "mouse \(mouse)"
        case "click": mouseButton(a.first != "up"); return "click \(a.first ?? "down")"
        case "tp":
            player.pos = CGPoint(x: n(0), y: n(1)); player.vel = .zero; player.grounded = false
            return "tp \(player.pos)"
        case "elements":
            var s = ""
            for (i, e) in level.elements.enumerated() where e.state == .solid {
                s += String(format: "%d %@ (%.0f,%.0f %.0fx%.0f)%@\n", i, "\(e.kind)", e.rect.minX, e.rect.minY, e.rect.width, e.rect.height, e.wall ? " wall" : "")
            }
            return s
        default: return devCommandExtra(cmd, a)
        }
    }

    /// Draws ledges (green), walls (red), text (blue), images (orange), debris tops (yellow)
    /// and fighter boxes (magenta) over a snapshot image.
    func debugOverlay(on img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let s = CGFloat(w) / size.width
        ctx.scaleBy(x: s, y: s)
        ctx.setLineWidth(1)
        for e in level.elements where e.state == .solid {
            let r = e.rect
            switch e.kind {
            case .text: ctx.setStrokeColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 1, alpha: 0.8))
            case .image: ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.9))
            case .control: ctx.setStrokeColor(CGColor(srgbRed: 0.8, green: 0, blue: 0.9, alpha: 0.9))
            default: ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0.7, blue: 0.7, alpha: 0.9))
            }
            ctx.stroke(r)
            ctx.setStrokeColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
            ctx.strokeLineSegments(between: [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)])
            if e.wall {
                ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
                ctx.setLineWidth(2)
                ctx.strokeLineSegments(between: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY),
                                                 CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)])
                ctx.setLineWidth(1)
            }
        }
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
        for r in platforms { ctx.strokeLineSegments(between: [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]) }
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1))
        for f in fighters where f.alive { ctx.stroke(f.bodyRect) }
        extraOverlay(ctx)
        return ctx.makeImage()
    }
}
