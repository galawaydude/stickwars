import SpriteKit

/// A singularity left by the black-hole gun: pulls in fighters, debris and loose letters, rips
/// small elements off the screen, then collapses in a blast.
struct Singularity {
    var pos: CGPoint
    var age: CGFloat = 0
    var owner: Int
    let core: SKSpriteNode, ring: SKSpriteNode, swirl: SKSpriteNode
    static let life: CGFloat = 2.4, reach: CGFloat = 250
}

extension Art {
    static var swirl: SKTexture {
        Tex.drawn("swirl", 64, 64) { c in
            c.translateBy(x: 32, y: 32)
            for arm in 0..<3 {
                let path = CGMutablePath()
                for k in 0...40 {
                    let t = CGFloat(k) / 40
                    let a = CGFloat(arm) * 2.094 + t * 4.2
                    let r = 4 + t * 26
                    let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
                    if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                c.addPath(path)
                c.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.35, blue: 1, alpha: 0.9))
                c.setLineWidth(4); c.setLineCap(.round)
                c.strokePath()
            }
        }
    }

    static var holeCore: SKTexture {
        Tex.drawn("holecore", 128, 128) { c in
            let g = CGGradient(colorsSpace: sRGB, colors: [CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                                                           CGColor(srgbRed: 0.55, green: 0.2, blue: 0.95, alpha: 0.9), CGColor(srgbRed: 0.4, green: 0.1, blue: 0.8, alpha: 0)] as CFArray,
                               locations: [0, 0.42, 0.52, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
    }

    static var holeRing: SKTexture {
        Tex.drawn("holering", 160, 160) { c in
            c.setStrokeColor(CGColor(srgbRed: 1, green: 0.7, blue: 1, alpha: 0.8)); c.setLineWidth(3)
            c.strokeEllipse(in: CGRect(x: 8, y: 50, width: 144, height: 60))
            c.setStrokeColor(CGColor(srgbRed: 0.6, green: 0.3, blue: 1, alpha: 0.6)); c.setLineWidth(6)
            c.strokeEllipse(in: CGRect(x: 18, y: 56, width: 124, height: 48))
        }
    }

    /// White crescent for knife slashes.
    static var slash: SKTexture {
        Tex.drawn("slash", 96, 96) { c in
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: 48, y: 48), radius: 44, startAngle: -1.3, endAngle: 1.3, clockwise: false)
            p.addArc(center: CGPoint(x: 38, y: 48), radius: 36, startAngle: 1.2, endAngle: -1.2, clockwise: true)
            p.closeSubpath()
            c.addPath(p); c.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95)); c.fillPath()
        }
    }
}

extension GameScene {
    // MARK: knife

    func slash(_ f: Fighter) {
        guard simTime >= f.knifeCD else { return }
        f.knifeCD = simTime + Weapons.knifeCooldown
        f.slashT = 0
        let dir = (f.input.aim - f.shoulder).normalized
        let c = f.shoulder + dir * 22
        Audio.shared.play(.slash, volume: f.isPlayer ? 0.7 : 0.4, pan: pan(c))
        fx.spawn(Art.slash, at: c, size: CGSize(width: 58, height: 58), rotation: atan2(dir.y, dir.x), color: .white, life: 0.16, grow: 0.25, z: 6, add: true)
        // fighters in a short cone
        for o in fighters where o.alive && o.id != f.id {
            let v = o.center - f.shoulder
            let l = v.length
            guard l < Weapons.knifeRange + 12 else { continue }
            if l < 16 || (v.x * dir.x + v.y * dir.y) / l > 0.35 {
                hurt(o, amount: Weapons.knifeDamage, by: f.id, dir: dir, knock: 420)
                particles.burst(o.center, n: 10, speed: 260, life: 0.45, color: o.color, size: 3, dir: dir, cone: 0.8)
                if f.isPlayer { shake(4); hitStop(0.05) }
            }
        }
        // slice up to three letters in reach
        var sliced = 0
        level.collect(CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52), into: &scratch)
        for i in scratch where sliced < 3 && level.elements[i].state == .solid && level.elements[i].kind == .text {
            knockLetter(i, at: level.elements[i].rect.center, dir: dir)
            sliced += 1
        }
    }

    // MARK: black hole

    func openSingularity(at p: CGPoint, owner: Int) {
        let core = SKSpriteNode(texture: Art.holeCore, size: CGSize(width: 10, height: 10))
        let ring = SKSpriteNode(texture: Art.holeRing, size: CGSize(width: 10, height: 10))
        let swirl = SKSpriteNode(texture: Art.swirl, size: CGSize(width: 10, height: 10))
        ring.blendMode = .add; swirl.blendMode = .add
        for (n, z) in [(swirl, CGFloat(33)), (core, 34), (ring, 35)] { n.position = p; n.zPosition = z; world.addChild(n) }
        holes.append(Singularity(pos: p, owner: owner, core: core, ring: ring, swirl: swirl))
        Audio.shared.play(.blackhole, volume: 0.8, pan: pan(p))
        shake(4)
    }

    func updateSingularities(_ dt: CGFloat) {
        var i = 0
        while i < holes.count {
            var h = holes[i]
            h.age += dt
            let grow = min(1, h.age / 0.35)
            let dying = h.age > Singularity.life - 0.25
            let s = (dying ? max(0.05, (Singularity.life - h.age) / 0.25) : grow)
            h.core.size = CGSize(width: 70 * s, height: 70 * s)
            h.swirl.size = CGSize(width: 120 * s, height: 120 * s)
            h.ring.size = CGSize(width: 150 * s, height: 150 * s)
            h.swirl.zRotation -= dt * 7
            h.ring.zRotation = sin(h.age * 3) * 0.25
            let R = Singularity.reach
            // fighters get dragged in and hurt near the centre
            for f in fighters where f.alive {
                let v = h.pos - f.center
                let l = v.length
                guard l < R, l > 1 else { continue }
                let pull = (1 - l / R) * 2600 * dt
                f.vel = f.vel + v * (pull / l)
                if !f.grounded || l < 120 { f.grounded = false }
                if l < 42 { hurt(f, amount: 80 * dt, by: h.owner, dir: v * (1 / l), knock: 0) }
            }
            // debris swirls in; pieces reaching the centre are swallowed
            for p in debris.pieces where p.fade == 0 {
                let v = h.pos - p.node.position
                let l = v.length
                guard l < R * 1.2, let b = p.node.physicsBody else { continue }
                debris.wake(body: b)
                if l < 18 { p.fade = 12; continue }
                let k = (1 - l / (R * 1.2)) * 1400 * dt
                let tang = CGPoint(x: -v.y, y: v.x) * (0.5 / max(l, 1))
                b.velocity = CGVector(dx: b.velocity.dx * 0.985 + (v.x / l) * k + tang.x * k, dy: b.velocity.dy * 0.985 + (v.y / l) * k + tang.y * k)
            }
            // rip nearby small elements off the screen toward the hole (a few per step)
            if Int(h.age * 60) % 3 == 0 {
                level.collect(CGRect(x: h.pos.x - 150, y: h.pos.y - 150, width: 300, height: 300), into: &scratch)
                var ripped = 0
                for e in scratch where ripped < 2 && level.elements[e].state == .solid && !level.elements[e].isBig && level.elements[e].kind != .ledge {
                    let c = level.elements[e].rect.center
                    guard c.dist(h.pos) < 150 else { continue }
                    breakLoose(e, from: c * 2 - h.pos, dir: (h.pos - c).normalized, speed: 300)
                    ripped += 1
                }
            }
            // purple dust spiralling in
            if rng.chance(0.8) {
                let a = rng.range(0, .pi * 2), r = rng.range(60, 160) * s
                let q = h.pos + CGPoint(x: cos(a) * r, y: sin(a) * r)
                let v = (h.pos - q) * 2.2 + CGPoint(x: -sin(a), y: cos(a)) * 120
                particles.emit(q.x, q.y, vx: v.x, vy: v.y, life: 0.45, color: rng.chance(0.5) ? SKColor(srgbRed: 0.8, green: 0.4, blue: 1, alpha: 1) : .white,
                               size: 2, gravity: 0, drag: 0)
            }
            if h.age >= Singularity.life {
                // collapse: implosion flash, then a blast outward
                for n in [h.core, h.ring, h.swirl] { n.removeFromParent() }
                holes.remove(at: i)
                Audio.shared.play(.collapse, volume: 0.9, pan: pan(h.pos))
                cinema.impactFlash(0.25)
                explode(at: h.pos, radius: 78, damage: 55, owner: h.owner)
                continue
            }
            holes[i] = h
            i += 1
        }
    }

    func clearSingularities() {
        for h in holes { for n in [h.core, h.ring, h.swirl] { n.removeFromParent() } }
        holes.removeAll()
    }

    // MARK: lightning

    /// Chain lightning: hits the first thing along the aim, then arcs to up to three more targets.
    func lightning(from a: CGPoint, dir: CGPoint, def: WeaponDef, owner: Int) {
        let h = trace(a, a + dir * def.range, owner: owner)
        var pts = [a]
        var at = h.point
        var hitIDs: [Int] = []
        switch h.target {
        case .fighter(let id):
            hurt(fighters[id], amount: def.damage, by: owner, dir: dir, knock: def.knock); hitIDs.append(id)
        case .element(let i):
            hitElement(i, at: h.point, dir: dir, power: .letter, damage: def.damage, carve: def.carve)
        case .debris(let b):
            debris.wake(body: b); b.applyImpulse(CGVector(dx: dir.x * b.mass * 120, dy: b.mass * 150), at: h.point)
        case .none:
            // fizzle: short random arc in the air
            at = a + dir * rng.range(90, 160)
        }
        pts.append(at)
        // chain to nearby fighters first, otherwise to nearby letters
        for _ in 0..<3 {
            var best: Fighter?, bd: CGFloat = 170
            for o in fighters where o.alive && o.id != owner && !hitIDs.contains(o.id) {
                let d = o.center.dist(at); if d < bd { bd = d; best = o }
            }
            if let o = best {
                hurt(o, amount: def.damage * 0.8, by: owner, dir: (o.center - at).normalized, knock: def.knock)
                hitIDs.append(o.id); at = o.center; pts.append(at)
                continue
            }
            level.collect(CGRect(x: at.x - 90, y: at.y - 90, width: 180, height: 180), into: &scratch)
            guard let e = scratch.first(where: { level.elements[$0].state == .solid && level.elements[$0].kind == .text }) else { break }
            let c = level.elements[e].rect.center
            knockLetter(e, at: c, dir: (c - at).normalized)
            at = c; pts.append(at)
        }
        // jagged double bolt that flickers
        for layer in 0..<2 {
            var prev = pts[0]
            for k in 1..<pts.count {
                let target = pts[k]
                let segs = max(2, Int(prev.dist(target) / 22))
                for sgi in 1...segs {
                    let t = CGFloat(sgi) / CGFloat(segs)
                    var q = prev + (target - prev) * t
                    if sgi < segs { q = q + CGPoint(x: rng.range(-9, 9), y: rng.range(-9, 9)) }
                    let from = sgi == 1 ? prev : (prev + (target - prev) * (CGFloat(sgi - 1) / CGFloat(segs)))
                    fx.line(from, q, width: layer == 0 ? 4 : 1.5, color: layer == 0 ? def.tracer.withAlphaComponent(0.45) : .white, life: 0.07)
                    _ = from
                }
                prev = target
            }
        }
        particles.burst(at, n: 6, speed: 240, life: 0.25, color: def.tracer, size: 2)
    }

    // MARK: armour

    /// Armour soaks 60% of incoming damage until it breaks; returns the damage that gets through.
    func absorbArmor(_ f: Fighter, _ amount: CGFloat) -> CGFloat {
        guard f.armor > 0 else { return amount }
        let soak = min(f.armor, amount * 0.6)
        f.armor -= soak
        if f.armor <= 0.5 {
            f.armor = 0
            Audio.shared.play(.clank, volume: 0.7, pan: pan(f.pos))
            particles.burst(f.center, n: 14, speed: 280, life: 0.7, color: SKColor(srgbRed: 0.16, green: 0.4, blue: 0.9, alpha: 1), size: 4)
        } else if soak > 3 {
            particles.burst(f.center, n: 3, speed: 200, life: 0.3, color: SKColor(srgbRed: 0.5, green: 0.9, blue: 1, alpha: 1), size: 2)
        }
        return amount - soak
    }
}
