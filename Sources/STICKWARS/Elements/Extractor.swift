import CoreGraphics
import Foundation

struct Extraction {
    var elements: [Element]
    var axCount = 0
    var pixelCount = 0
    var ms = 0.0
}

/// Runs AX and pixel detection in parallel and merges them: AX rects win where present,
/// pixel boxes split AX text into words and cover everything AX can't see.
enum Extractor {
    static func run(image: CGImage, windows: [WindowInfo], screen: CGSize, useAX: Bool = true) -> Extraction {
        let t0 = now()
        let W = Int(screen.width), H = Int(screen.height)
        final class Box { var boxes: [IBox] = [] }
        let pix = Box()
        let g = DispatchGroup()
        DispatchQueue.global(qos: .userInteractive).async(group: g) { pix.boxes = PixelDetector.detect(image, width: W, height: H) }
        let ax = useAX ? AXScanner.scan(windows: windows, screen: screen) : []
        g.wait()
        var ex = merge(boxes: pix.boxes, ax: ax, windows: windows, screen: screen)
        ex.ms = (now() - t0) * 1000
        return ex
    }

    static func merge(boxes: [IBox], ax: [AXItem], windows: [WindowInfo], screen: CGSize) -> Extraction {
        let H = screen.height
        func scene(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }
        var out: [Element] = []
        out.reserveCapacity(boxes.count + ax.count + 16)

        // Grid of pixel-box centres for fast "boxes inside rect" lookups.
        let cell: CGFloat = 48
        let gc = Int(screen.width / cell) + 1, gr = Int(screen.height / cell) + 1
        var grid = [[Int32]](repeating: [], count: gc * gr)
        for (i, b) in boxes.enumerated() {
            let c = b.rect.center
            grid[clamp(Int(c.y / cell), 0, gr - 1) * gc + clamp(Int(c.x / cell), 0, gc - 1)].append(Int32(i))
        }
        var consumed = [Bool](repeating: false, count: boxes.count)
        func inside(_ r: CGRect, _ body: (Int) -> Void) {
            let x0 = clamp(Int(r.minX / cell), 0, gc - 1), x1 = clamp(Int(r.maxX / cell), 0, gc - 1)
            let y0 = clamp(Int(r.minY / cell), 0, gr - 1), y1 = clamp(Int(r.maxY / cell), 0, gr - 1)
            for y in y0...y1 { for x in x0...x1 { for k in grid[y * gc + x] where r.contains(boxes[Int(k)].rect.center) { body(Int(k)) } } }
        }

        // A. accessibility elements
        for item in ax {
            let r = item.rect
            switch item.kind {
            case .text, .textArea:
                var n = 0
                inside(r.insetBy(dx: -2, dy: -2)) { k in
                    guard !consumed[k] else { return }
                    consumed[k] = true; n += 1
                    let br = boxes[k].rect
                    let clipped = item.kind == .text ? br.intersection(r.insetBy(dx: -1, dy: -1)) : br
                    if !clipped.isNull, clipped.width >= 3, clipped.height >= 3 {
                        out.append(Element(rect: scene(clipped), kind: classify(boxes[k], children: 0), fromAX: true))
                    }
                }
                if n == 0, item.kind == .text, r.height <= 40, r.width >= 6 { out.append(Element(rect: scene(r), kind: .text, fromAX: true)) }
            case .control, .image:
                inside(r.insetBy(dx: -1, dy: -1)) { consumed[$0] = true }
                let big = r.width >= 24 && r.height >= 24
                out.append(Element(rect: scene(r), kind: item.kind == .image && big ? .image : .control, fromAX: true))
            }
        }

        // B. leftover pixel boxes
        for (i, b) in boxes.enumerated() where !consumed[i] {
            var children = 0
            if b.h >= 34 && b.w >= 24 {
                inside(b.rect.insetBy(dx: 1, dy: 1)) { k in if k != i && boxes[k].w * boxes[k].h < b.w * b.h / 2 { children += 1 } }
            }
            if children >= 2 && b.h >= 60 {
                // Container (card, panel): only its top border is a ledge; children stand on their own.
                out.append(Element(rect: scene(CGRect(x: b.rect.minX, y: b.rect.minY, width: b.rect.width, height: 2)), kind: .line))
            } else {
                out.append(Element(rect: scene(b.rect), kind: classify(b, children: children)))
            }
        }

        // C. window title-bar tops as ledges (only the parts not covered by windows in front)
        for (i, w) in windows.enumerated() where w.layer == 0 && w.bounds.minY > 2 {
            let y = w.bounds.minY
            var segs: [(CGFloat, CGFloat)] = [(max(0, w.bounds.minX), min(screen.width, w.bounds.maxX))]
            for f in windows[..<i] where f.bounds.minY <= y + 1 && f.bounds.maxY >= y - 1 {
                var next: [(CGFloat, CGFloat)] = []
                for (a, b) in segs {
                    if f.bounds.maxX <= a || f.bounds.minX >= b { next.append((a, b)); continue }
                    if f.bounds.minX > a { next.append((a, f.bounds.minX)) }
                    if f.bounds.maxX < b { next.append((f.bounds.maxX, b)) }
                }
                segs = next
            }
            for (a, b) in segs where b - a >= 30 {
                out.append(Element(rect: CGRect(x: a, y: H - y - 2, width: b - a, height: 2), kind: .ledge, fromAX: true))
            }
        }
        return Extraction(elements: out, axCount: ax.count, pixelCount: boxes.count)
    }

    static func classify(_ b: IBox, children: Int) -> ElementKind {
        let w = b.w, h = b.h
        if b.text { return .text }
        if h <= 3 && w >= 12 { return .line }
        if h >= 34 && w >= 24 { return .image }
        if h >= 12, Double(w) / Double(h) < 1.5 { return .control } // icon-ish
        return .text
    }
}
