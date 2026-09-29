import CoreGraphics

/// Integer box in top-left point coordinates.
struct IBox {
    var x0: Int32, y0: Int32, x1: Int32, y1: Int32 // inclusive
    var text = false // came from splitting a text line into words
    var w: Int { Int(x1 - x0 + 1) }
    var h: Int { Int(y1 - y0 + 1) }
    var rect: CGRect { CGRect(x: CGFloat(x0), y: CGFloat(y0), width: CGFloat(w), height: CGFloat(h)) }
}

/// Universal element detection from pixels: 1 px per point grayscale, edge map, dilation
/// (2 pt horizontally, 1 vertically) to merge letters into words, then connected components.
enum PixelDetector {
    static func detect(_ image: CGImage, width w: Int, height h: Int) -> [IBox] {
        let n = w * h
        guard n > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let gp = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let g = UnsafeMutablePointer<UInt8>(gp) // row 0 = top

        let edge = UnsafeMutablePointer<UInt8>.allocate(capacity: n)
        let dil = UnsafeMutablePointer<UInt8>.allocate(capacity: n)
        let tmp = UnsafeMutablePointer<UInt8>.allocate(capacity: n)
        let label = UnsafeMutablePointer<UInt8>.allocate(capacity: n) // visited flag
        let stack = UnsafeMutablePointer<Int32>.allocate(capacity: n)
        defer { edge.deallocate(); dil.deallocate(); tmp.deallocate(); label.deallocate(); stack.deallocate() }
        edge.initialize(repeating: 0, count: n)
        label.initialize(repeating: 0, count: n)

        // Edge map: neighbour luminance difference above 16.
        for y in 0..<(h - 1) {
            let row = y * w
            for x in 0..<(w - 1) {
                let i = row + x
                let v = Int(g[i])
                if abs(v - Int(g[i + 1])) > 16 || abs(v - Int(g[i + w])) > 16 { edge[i] = 1 }
            }
        }
        // Horizontal dilation by 2 (running window count).
        for y in 0..<h {
            let row = y * w
            var c = 0
            for x in 0..<min(2, w) { c += Int(edge[row + x]) }
            for x in 0..<w {
                if x + 2 < w { c += Int(edge[row + x + 2]) }
                if x - 3 >= 0 { c -= Int(edge[row + x - 3]) }
                tmp[row + x] = c > 0 ? 1 : 0
            }
        }
        // Vertical dilation by 1.
        for y in 0..<h {
            let row = y * w
            for x in 0..<w {
                var v = tmp[row + x]
                if y > 0 { v |= tmp[row + x - w] }
                if y + 1 < h { v |= tmp[row + x + w] }
                dil[row + x] = v
            }
        }
        // Connected components (4-connected) with an explicit Int32 stack; bounds from undilated edges.
        var boxes: [IBox] = []
        boxes.reserveCapacity(4096)
        let maxW = Int(Double(w) * 0.6), maxH = Int(Double(h) * 0.4)
        for start in 0..<n where dil[start] == 1 && label[start] == 0 {
            var sp = 0
            stack[sp] = Int32(start); sp += 1
            label[start] = 1
            var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
            while sp > 0 {
                sp -= 1
                let i = Int(stack[sp])
                let x = i % w, y = i / w
                if edge[i] == 1 {
                    if x < x0 { x0 = x }; if x > x1 { x1 = x }
                    if y < y0 { y0 = y }; if y > y1 { y1 = y }
                }
                if x > 0, dil[i - 1] == 1, label[i - 1] == 0 { label[i - 1] = 1; stack[sp] = Int32(i - 1); sp += 1 }
                if x + 1 < w, dil[i + 1] == 1, label[i + 1] == 0 { label[i + 1] = 1; stack[sp] = Int32(i + 1); sp += 1 }
                if y > 0, dil[i - w] == 1, label[i - w] == 0 { label[i - w] = 1; stack[sp] = Int32(i - w); sp += 1 }
                if y + 1 < h, dil[i + w] == 1, label[i + w] == 0 { label[i + w] = 1; stack[sp] = Int32(i + w); sp += 1 }
            }
            guard x1 >= 0 else { continue }
            // edge pixel x marks the boundary between x and x+1: widen by one to cover both sides
            x1 = min(w - 1, x1 + 1); y1 = min(h - 1, y1 + 1)
            let bw = x1 - x0 + 1, bh = y1 - y0 + 1
            if bw < 6 && bh < 6 { continue }        // specks
            if bw < 3 || bh < 2 { continue }
            if bw > maxW && bh > maxH { continue }  // frame-sized
            // Text lines: split into words at column gaps wider than a letter gap.
            if bh < 40 && bw > bh * 2 {
                let gapMin = max(3, bh / 5)
                var runStart = x0, empty = 0
                for x in x0...(x1 + 1) {
                    var has = false
                    if x <= x1 { for y in y0...y1 where edge[y * w + x] == 1 { has = true; break } }
                    if has {
                        if empty >= gapMin && x - empty > runStart {
                            boxes.append(IBox(x0: Int32(runStart), y0: Int32(y0), x1: Int32(x - empty), y1: Int32(y1), text: true))
                            runStart = x
                        }
                        empty = 0
                    } else { empty += 1 }
                }
                if x1 >= runStart { boxes.append(IBox(x0: Int32(runStart), y0: Int32(y0), x1: Int32(x1), y1: Int32(y1), text: true)) }
                continue
            }
            boxes.append(IBox(x0: Int32(x0), y0: Int32(y0), x1: Int32(x1), y1: Int32(y1)))
        }
        return boxes
    }
}
