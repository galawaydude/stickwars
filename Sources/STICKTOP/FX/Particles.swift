import SpriteKit

/// Pooled square pixel particles, updated in place with swap-remove. No per-particle actions.
final class Particles {
    private struct P {
        var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
        var life: CGFloat, maxLife: CGFloat, gravity: CGFloat, drag: CGFloat
    }
    let node = SKNode()
    private var sprites: [SKSpriteNode] = []
    private var ps: [P] = []
    private(set) var count = 0
    let cap: Int

    init(cap: Int = 1600) {
        self.cap = cap
        ps = [P](repeating: P(x: 0, y: 0, vx: 0, vy: 0, life: 0, maxLife: 1, gravity: 0, drag: 0), count: cap)
        let t = Tex.white
        for _ in 0..<cap {
            let s = SKSpriteNode(texture: t, size: CGSize(width: 2, height: 2))
            s.colorBlendFactor = 1
            s.isHidden = true
            sprites.append(s)
            node.addChild(s)
        }
    }

    func emit(_ x: CGFloat, _ y: CGFloat, vx: CGFloat, vy: CGFloat, life: CGFloat, color: SKColor, size: CGFloat = 2,
              gravity: CGFloat = 900, drag: CGFloat = 1.5) {
        guard count < cap else { return }
        ps[count] = P(x: x, y: y, vx: vx, vy: vy, life: life, maxLife: life, gravity: gravity, drag: drag)
        let s = sprites[count]
        s.color = color
        s.size = CGSize(width: size, height: size)
        s.alpha = 1
        s.position = CGPoint(x: x, y: y)
        s.isHidden = false
        count += 1
    }

    /// Burst of n particles with random directions.
    func burst(_ p: CGPoint, n: Int, speed: CGFloat, life: CGFloat, color: SKColor, size: CGFloat = 2, gravity: CGFloat = 900,
               dir: CGPoint? = nil, cone: CGFloat = .pi) {
        let base = dir.map { atan2($0.y, $0.x) } ?? 0
        for _ in 0..<n {
            let a = dir == nil ? rng.range(0, .pi * 2) : base + rng.range(-cone, cone)
            let s = speed * rng.range(0.3, 1)
            emit(p.x, p.y, vx: cos(a) * s, vy: sin(a) * s, life: life * rng.range(0.6, 1.2), color: color, size: size, gravity: gravity)
        }
    }

    func update(_ dt: CGFloat) {
        var i = 0
        while i < count {
            ps[i].life -= dt
            if ps[i].life <= 0 {
                count -= 1
                ps.swapAt(i, count)
                sprites.swapAt(i, count)
                sprites[count].isHidden = true
                continue
            }
            let d = max(0, 1 - ps[i].drag * dt)
            ps[i].vx *= d
            ps[i].vy = ps[i].vy * d - ps[i].gravity * dt
            ps[i].x += ps[i].vx * dt
            ps[i].y += ps[i].vy * dt
            let s = sprites[i]
            s.position = CGPoint(x: ps[i].x.rounded(), y: ps[i].y.rounded())
            let f = ps[i].life / ps[i].maxLife
            if f < 0.35 { s.alpha = f / 0.35 }
            i += 1
        }
    }

    func clear() {
        for i in 0..<count { sprites[i].isHidden = true }
        count = 0
    }
}

/// Pooled short-lived sprites: tracers, beams, muzzle flashes, rings.
final class FXPool {
    private struct F { var life: CGFloat, maxLife: CGFloat, grow: CGFloat, baseScale: CGFloat }
    let node = SKNode()
    private var sprites: [SKSpriteNode] = []
    private var fs: [F] = []
    private(set) var count = 0

    init(cap: Int = 160) {
        for _ in 0..<cap {
            let s = SKSpriteNode(texture: Tex.white)
            s.colorBlendFactor = 1
            s.isHidden = true
            sprites.append(s); node.addChild(s)
        }
        fs = [F](repeating: F(life: 0, maxLife: 1, grow: 0, baseScale: 1), count: cap)
    }

    @discardableResult
    func spawn(_ tex: SKTexture, at p: CGPoint, size: CGSize, rotation: CGFloat = 0, color: SKColor = .white, blend: CGFloat = 1,
               life: CGFloat, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5), grow: CGFloat = 0, z: CGFloat = 0, add: Bool = false) -> SKSpriteNode? {
        guard count < sprites.count else { return nil }
        let s = sprites[count]
        s.texture = tex; s.size = size; s.anchorPoint = anchor
        s.position = p; s.zRotation = rotation; s.color = color; s.colorBlendFactor = blend
        s.alpha = 1; s.setScale(1); s.zPosition = z
        s.blendMode = add ? .add : .alpha
        s.isHidden = false
        fs[count] = F(life: life, maxLife: life, grow: grow, baseScale: 1)
        count += 1
        return s
    }

    /// A line from a to b (tracer / beam).
    func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat, color: SKColor, life: CGFloat, add: Bool = true) {
        let d = b - a
        spawn(Tex.white, at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), size: CGSize(width: max(1, d.length), height: width),
              rotation: atan2(d.y, d.x), color: color, life: life, z: 1, add: add)
    }

    func update(_ dt: CGFloat) {
        var i = 0
        while i < count {
            fs[i].life -= dt
            if fs[i].life <= 0 {
                count -= 1
                fs.swapAt(i, count); sprites.swapAt(i, count)
                sprites[count].isHidden = true
                continue
            }
            let f = fs[i].life / fs[i].maxLife
            let s = sprites[i]
            s.alpha = f
            if fs[i].grow != 0 { s.setScale(1 + fs[i].grow * (1 - f)) }
            i += 1
        }
    }

    func clear() {
        for i in 0..<count { sprites[i].isHidden = true }
        count = 0
    }
}
