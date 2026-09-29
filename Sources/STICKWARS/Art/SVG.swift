import CoreGraphics
import SpriteKit

/// Minimal SVG: path data (M L H V C S Q T Z, absolute and relative), rects and circles with
/// fill / stroke, rendered in code with a bold dark "sticker" outline behind every shape.
/// Art stays in source as SVG markup-equivalent data; nothing is loaded from files.
struct SVG {
    enum Shape {
        case path(String)
        case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)   // x y w h rx
        case circle(CGFloat, CGFloat, CGFloat)                    // cx cy r
    }
    struct El {
        var shape: Shape
        var fill: UInt32?
        var stroke: UInt32?
        var width: CGFloat = 1
        var alpha: CGFloat = 1
        var outline = true
    }
    let w: CGFloat, h: CGFloat
    var outline: CGFloat = 1.6
    let els: [El]

    /// Padding added around the view box so the outline isn't clipped.
    var pad: CGFloat { outline + 0.5 }
    var size: CGSize { CGSize(width: w + pad * 2, height: h + pad * 2) }

    /// Anchor for a point given in view-box coordinates (y down).
    func anchor(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x + pad) / size.width, y: 1 - (p.y + pad) / size.height) }

    // MARK: element helpers (read like SVG attributes)

    static func P(_ d: String, _ fill: UInt32? = nil, stroke: UInt32? = nil, width: CGFloat = 1, alpha: CGFloat = 1, outline: Bool = true) -> El {
        El(shape: .path(d), fill: fill, stroke: stroke, width: width, alpha: alpha, outline: outline)
    }
    static func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: UInt32, rx: CGFloat = 0, alpha: CGFloat = 1, outline: Bool = true) -> El {
        El(shape: .rect(x, y, w, h, rx), fill: fill, alpha: alpha, outline: outline)
    }
    static func C(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ fill: UInt32?, stroke: UInt32? = nil, width: CGFloat = 1, alpha: CGFloat = 1, outline: Bool = true) -> El {
        El(shape: .circle(cx, cy, r), fill: fill, stroke: stroke, width: width, alpha: alpha, outline: outline)
    }

    // MARK: rendering

    private static var cache: [String: SKTexture] = [:]

    func texture(_ name: String, scale: CGFloat = 4) -> SKTexture {
        if let t = SVG.cache[name] { return t }
        let t = SKTexture(cgImage: image(scale: scale))
        t.filteringMode = .linear
        SVG.cache[name] = t
        return t
    }

    func image(scale s: CGFloat) -> CGImage {
        let W = Int((size.width * s).rounded(.up)), H = Int((size.height * s).rounded(.up))
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(in: ctx, scale: s, height: CGFloat(H))
        return ctx.makeImage()!
    }

    /// Draws into ctx (y-up) with the view box's top-left at the top-left of a `height`-tall area.
    func draw(in ctx: CGContext, scale s: CGFloat, height: CGFloat, origin: CGPoint = .zero) {
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y + height)
        ctx.scaleBy(x: s, y: -s)
        ctx.translateBy(x: pad, y: pad)
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        let paths = els.map { SVG.cgPath($0.shape) }
        // outline pass: every shape stroked wide in near-black, behind everything
        ctx.setStrokeColor(SVG.color(0x121219, 1))
        for (e, p) in zip(els, paths) where e.outline {
            ctx.addPath(p)
            ctx.setLineWidth((e.fill == nil ? e.width : 0) + outline * 2)
            ctx.strokePath()
        }
        for (e, p) in zip(els, paths) {
            if let f = e.fill { ctx.addPath(p); ctx.setFillColor(SVG.color(f, e.alpha)); ctx.fillPath() }
            if let st = e.stroke { ctx.addPath(p); ctx.setStrokeColor(SVG.color(st, e.alpha)); ctx.setLineWidth(e.width); ctx.strokePath() }
        }
        ctx.restoreGState()
    }

    static func color(_ hex: UInt32, _ a: CGFloat) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
    }

    static func cgPath(_ s: Shape) -> CGPath {
        switch s {
        case let .rect(x, y, w, h, r):
            return r > 0 ? CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
                         : CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: nil)
        case let .circle(cx, cy, r):
            return CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), transform: nil)
        case let .path(d):
            return parse(d)
        }
    }

    /// SVG path data parser (no arcs).
    static func parse(_ d: String) -> CGPath {
        let p = CGMutablePath()
        var tokens: [String] = []
        var cur = ""
        func flush() { if !cur.isEmpty { tokens.append(cur); cur = "" } }
        for ch in d {
            if ch.isLetter && ch != "e" { flush(); tokens.append(String(ch)) }
            else if ch == "," || ch == " " || ch == "\n" { flush() }
            else if ch == "-" && !cur.isEmpty && cur.last != "e" { flush(); cur = "-" }
            else if ch == "." && cur.contains(".") { flush(); cur = "." }
            else { cur.append(ch) }
        }
        flush()
        var i = 0, cmd = "M"
        var pt = CGPoint.zero, start = CGPoint.zero, lastCtrl = CGPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0 }
        func hasNum() -> Bool { i < tokens.count && Double(tokens[i]) != nil }
        while i < tokens.count {
            if !hasNum() { cmd = tokens[i]; i += 1 }
            let rel = cmd == cmd.lowercased() && cmd.lowercased() != "z"
            let o = rel ? pt : .zero
            switch cmd.uppercased() {
            case "M":
                pt = CGPoint(x: o.x + num(), y: o.y + num()); p.move(to: pt); start = pt; lastCtrl = pt
                cmd = rel ? "l" : "L"
            case "L": pt = CGPoint(x: o.x + num(), y: o.y + num()); p.addLine(to: pt); lastCtrl = pt
            case "H": pt = CGPoint(x: (rel ? pt.x : 0) + num(), y: pt.y); p.addLine(to: pt); lastCtrl = pt
            case "V": pt = CGPoint(x: pt.x, y: (rel ? pt.y : 0) + num()); p.addLine(to: pt); lastCtrl = pt
            case "C":
                let c1 = CGPoint(x: o.x + num(), y: o.y + num()), c2 = CGPoint(x: o.x + num(), y: o.y + num())
                pt = CGPoint(x: o.x + num(), y: o.y + num()); p.addCurve(to: pt, control1: c1, control2: c2); lastCtrl = c2
            case "S":
                let c1 = CGPoint(x: 2 * pt.x - lastCtrl.x, y: 2 * pt.y - lastCtrl.y)
                let c2 = CGPoint(x: o.x + num(), y: o.y + num())
                pt = CGPoint(x: o.x + num(), y: o.y + num()); p.addCurve(to: pt, control1: c1, control2: c2); lastCtrl = c2
            case "Q":
                let c = CGPoint(x: o.x + num(), y: o.y + num())
                pt = CGPoint(x: o.x + num(), y: o.y + num()); p.addQuadCurve(to: pt, control: c); lastCtrl = c
            case "T":
                let c = CGPoint(x: 2 * pt.x - lastCtrl.x, y: 2 * pt.y - lastCtrl.y)
                pt = CGPoint(x: o.x + num(), y: o.y + num()); p.addQuadCurve(to: pt, control: c); lastCtrl = c
            case "Z":
                p.closeSubpath(); pt = start; lastCtrl = pt
                if hasNum() { cmd = "L" }
            default: i += 1
            }
        }
        return p
    }
}
