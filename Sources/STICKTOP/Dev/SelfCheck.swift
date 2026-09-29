import AppKit

/// Tiny runnable self-check for pure logic: `STICKTOP --selfcheck`.
enum SelfCheck {
    static func run() -> Bool {
        var ok = true
        func check(_ c: Bool, _ msg: String) { print((c ? "ok   " : "FAIL ") + msg); if !c { ok = false } }

        // Element extraction on the fake page.
        let size = CGSize(width: 1512, height: 982)
        let img = FakePage.image(size: size)
        let ex = Extractor.run(image: img, windows: FakePage.windows(size: size), screen: size, useAX: false)
        let texts = ex.elements.filter { $0.kind == .text }.count
        check(texts >= 60, "fake page yields words (\(texts) text elements, \(String(format: "%.0f", ex.ms)) ms)")
        check(ex.elements.contains { $0.kind == .ledge && abs($0.rect.maxY - (982 - 50)) < 1 }, "title bar ledge at the window top")
        check(ex.elements.contains { $0.kind == .image && $0.wall && $0.rect.width > 380 }, "photo is a walled image")
        check(!ex.elements.contains { $0.rect.width > 900 && $0.rect.height > 400 }, "no frame-sized elements")

        // One-way platform collision.
        let level = Level(size: size)
        level.reset([Element(rect: CGRect(x: 100, y: 300, width: 200, height: 14), kind: .text),
                     Element(rect: CGRect(x: 500, y: 0, width: 100, height: 200), kind: .image)])
        let f = Fighter(id: 9, name: "T", color: .red, isPlayer: false)
        func sim(_ n: Int) { for _ in 0..<n { [CGRect]().withUnsafeBufferPointer { f.step(1 / 120, level: level, extra: $0, bounds: size) }; f.input.clearEdges() } }
        f.pos = CGPoint(x: 200, y: 500); sim(120)
        check(f.grounded && abs(f.pos.y - 314) < 0.01, "falls onto a text ledge (y=\(f.pos.y))")
        f.pos = CGPoint(x: 200, y: 250); f.vel = CGPoint(x: 0, y: 800); f.grounded = false
        f.input.jumpHeld = true; sim(30)
        check(f.pos.y > 314, "jumps up through the ledge from below")
        sim(120)
        check(f.grounded && abs(f.pos.y - 314) < 0.01, "lands on it from above")
        f.input.down = true; f.input.downPressed = true; sim(60); f.input.down = false
        check(f.pos.y < 300, "S drops through the ledge")
        f.pos = CGPoint(x: 400, y: 0); f.vel = .zero; f.input.moveX = 1; sim(120)
        check(f.pos.x <= 500 - Move.halfW + 0.01 && f.wallDir == 1, "tall image blocks from the side")
        f.input.moveX = 0

        // Fracture generator.
        var g = RNG(42)
        for _ in 0..<50 {
            let fr = Fracture.make(center: CGPoint(x: 400, y: 400), radius: 60, rng: &g)
            let cellArea = fr.cells.reduce(0) { $0 + abs(Fracture.area($1.poly)) }
            let rimArea = abs(Fracture.area(fr.outline))
            if fr.cells.count < 5 || fr.cells.contains(where: { $0.poly.count < 3 }) || abs(cellArea - rimArea) > rimArea * 0.02 {
                check(false, "fracture cells tile the crater (cells \(fr.cells.count), \(cellArea) vs \(rimArea))"); break
            }
        }
        check(true, "fracture cells tile the crater outline")

        print(ok ? "selfcheck passed" : "selfcheck FAILED")
        return ok
    }
}
