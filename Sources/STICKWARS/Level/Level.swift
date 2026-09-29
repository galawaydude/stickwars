import CoreGraphics

struct RayHit {
    var index: Int
    var t: CGFloat          // 0...1 along the segment
    var point: CGPoint
    var normal: CGPoint
}

/// Static geometry: the solid elements plus a uniform spatial hash (48-pt cells).
/// Queries don't allocate; mutation happens only when elements break.
final class Level {
    let size: CGSize
    private(set) var elements: [Element] = []
    let cell: CGFloat = 48
    let cols: Int, rows: Int
    private var buckets: [[Int32]]
    private var stamp: [UInt32] = []
    private var curStamp: UInt32 = 0
    /// Bumped on every change; nav graph and physics bodies watch it.
    private(set) var version = 0
    private(set) var solidCount = 0
    /// Indices added / removed since the consumer last drained them (static physics bodies).
    var added: [Int] = []
    var removed: [Int] = []

    init(size: CGSize) {
        self.size = size
        cols = Int((size.width / cell).rounded(.up)) + 1
        rows = Int((size.height / cell).rounded(.up)) + 1
        buckets = [[Int32]](repeating: [], count: cols * rows)
    }

    func reset(_ els: [Element]) {
        for i in 0..<buckets.count { buckets[i].removeAll(keepingCapacity: true) }
        elements.removeAll(keepingCapacity: true)
        stamp.removeAll(keepingCapacity: true)
        added.removeAll(); removed.removeAll()
        solidCount = 0
        for e in els { add(e) }
        version += 1
    }

    @inline(__always) private func cellRange(_ r: CGRect) -> (Int, Int, Int, Int) {
        (clamp(Int(r.minX / cell), 0, cols - 1), clamp(Int(r.minY / cell), 0, rows - 1),
         clamp(Int(r.maxX / cell), 0, cols - 1), clamp(Int(r.maxY / cell), 0, rows - 1))
    }

    @discardableResult
    func add(_ e: Element) -> Int {
        let i = elements.count
        elements.append(e)
        stamp.append(0)
        let (x0, y0, x1, y1) = cellRange(e.rect)
        for y in y0...y1 { for x in x0...x1 { buckets[y * cols + x].append(Int32(i)) } }
        solidCount += 1
        added.append(i)
        version += 1
        return i
    }

    func remove(_ i: Int, state: ElementState = .destroyed) {
        guard elements[i].state == .solid else { return }
        elements[i].state = state
        let (x0, y0, x1, y1) = cellRange(elements[i].rect)
        let key = Int32(i)
        for y in y0...y1 { for x in x0...x1 {
            let b = y * cols + x
            if let k = buckets[b].firstIndex(of: key) { buckets[b].swapAt(k, buckets[b].count - 1); buckets[b].removeLast() }
        } }
        solidCount -= 1
        removed.append(i)
        version += 1
    }

    func damage(_ i: Int, hp: CGFloat, carved: CGFloat = 0) {
        elements[i].hp -= hp
        elements[i].carved += carved
    }

    func setLetters(_ i: Int, _ l: [CGRect]) { elements[i].letters = l }

    @inline(__always) private func nextStamp() -> UInt32 {
        curStamp &+= 1
        if curStamp == 0 { for k in 0..<stamp.count { stamp[k] = 0 }; curStamp = 1 }
        return curStamp
    }

    /// Calls body for every solid element whose rect intersects r. Don't mutate the level inside.
    @inline(__always)
    func query(_ r: CGRect, _ body: (Int) -> Void) {
        let s = nextStamp()
        let (x0, y0, x1, y1) = cellRange(r)
        for y in y0...y1 { for x in x0...x1 {
            for k in buckets[y * cols + x] {
                let i = Int(k)
                if stamp[i] != s {
                    stamp[i] = s
                    if elements[i].rect.intersects(r) { body(i) }
                }
            }
        } }
    }

    /// Same as query but into a reusable buffer, so callers can mutate the level afterwards.
    func collect(_ r: CGRect, into out: inout [Int]) {
        out.removeAll(keepingCapacity: true)
        query(r) { out.append($0) }
    }

    /// Nearest element hit by segment a->b (grid DDA), for which `accept` is true.
    func raycast(_ a: CGPoint, _ b: CGPoint, accept: (Int) -> Bool) -> RayHit? {
        let dx = b.x - a.x, dy = b.y - a.y
        let s = nextStamp()
        var best: RayHit?
        var bestT: CGFloat = 1
        var cx = Int((a.x / cell).rounded(.down)), cy = Int((a.y / cell).rounded(.down))
        let stepX = dx > 0 ? 1 : -1, stepY = dy > 0 ? 1 : -1
        let inf = CGFloat.greatestFiniteMagnitude
        var tMaxX = dx != 0 ? ((CGFloat(cx + (dx > 0 ? 1 : 0)) * cell) - a.x) / dx : inf
        var tMaxY = dy != 0 ? ((CGFloat(cy + (dy > 0 ? 1 : 0)) * cell) - a.y) / dy : inf
        let tDX = dx != 0 ? cell / abs(dx) : inf, tDY = dy != 0 ? cell / abs(dy) : inf
        var guardN = cols + rows + 4
        while guardN > 0 {
            guardN -= 1
            if cx >= 0, cy >= 0, cx < cols, cy < rows {
                for k in buckets[cy * cols + cx] {
                    let i = Int(k)
                    if stamp[i] == s { continue }
                    stamp[i] = s
                    if let (t, n) = Level.segmentRect(a, dx, dy, elements[i].rect), t < bestT, accept(i) {
                        bestT = t
                        best = RayHit(index: i, t: t, point: CGPoint(x: a.x + dx * t, y: a.y + dy * t), normal: n)
                    }
                }
            }
            let tExit = min(tMaxX, tMaxY)
            if tExit >= bestT || tExit > 1 { break }
            if tMaxX < tMaxY { cx += stepX; tMaxX += tDX } else { cy += stepY; tMaxY += tDY }
        }
        return best
    }

    /// Slab test. Returns entry t in [0,1] and the entry normal; t = 0 if a starts inside.
    @inline(__always)
    static func segmentRect(_ a: CGPoint, _ dx: CGFloat, _ dy: CGFloat, _ r: CGRect) -> (CGFloat, CGPoint)? {
        var t0: CGFloat = 0, t1: CGFloat = 1
        var n = CGPoint(x: -dx, y: -dy).normalized
        if dx == 0 {
            if a.x < r.minX || a.x > r.maxX { return nil }
        } else {
            var ta = (r.minX - a.x) / dx, tb = (r.maxX - a.x) / dx
            var nx: CGFloat = -1
            if ta > tb { swap(&ta, &tb); nx = 1 }
            if ta > t0 { t0 = ta; n = CGPoint(x: nx, y: 0) }
            t1 = min(t1, tb)
            if t0 > t1 { return nil }
        }
        if dy == 0 {
            if a.y < r.minY || a.y > r.maxY { return nil }
        } else {
            var ta = (r.minY - a.y) / dy, tb = (r.maxY - a.y) / dy
            var ny: CGFloat = -1
            if ta > tb { swap(&ta, &tb); ny = 1 }
            if ta > t0 { t0 = ta; n = CGPoint(x: 0, y: ny) }
            t1 = min(t1, tb)
            if t0 > t1 { return nil }
        }
        return (t0, n)
    }
}
