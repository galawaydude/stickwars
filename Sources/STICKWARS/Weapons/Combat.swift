import SpriteKit

struct Projectile {
    enum Kind { case rocket, plasma, grenade, blackhole, saw }
    var kind: Kind
    var pos: CGPoint
    var vel: CGPoint
    var owner: Int
    var age: CGFloat = 0
    var bounces = 0
    var hitID = -1            // saw: last fighter cut (so one pass hits once)
    var stuck: CGFloat = 0    // saw: > 0 while embedded in something
    var cuts = 0
    var fuse: CGFloat = 0
    var power: CGFloat = 1
    var node: SKSpriteNode
}

enum ShotTarget {
    case none
    case fighter(Int)
    case element(Int)
    case debris(SKPhysicsBody)
}

struct ShotHit {
    var target: ShotTarget
    var point: CGPoint
    var normal: CGPoint
    var t: CGFloat
}

enum Art {
    static var rocket: SKTexture { Tex.pixels("rocket", ["..kkkkk..", "okrrsssk.", "ookrsssck", "okrrsssk.", "..kkkkk.."]) }
    static var plasma: SKTexture { Tex.pixels("plasma", [".cccc.", "cwwwwc", "cwwwwc", ".cccc."]) }
    static var grenade: SKTexture { Tex.pixels("grenade", ["..kk..", ".kyyk.", "kddddk", "kdgddk", "kddddk", "kdddek", ".kkkk."]) }
    /// Blocky pixel starburst for explosion flashes (never a smooth circle).
    static var blast: SKTexture {
        Tex.pixels("blast", ["....y..y.....", "..y.yyyy..y..", "...yywwyyy...", ".yywwwwwwyy..", "..ywwwwwwwyy.",
                             "yywwwwwwwwwy.", ".ywwwwwwwwwyy", "..yywwwwwwy..", ".yyywwwwwyyy.", "...yyywwyy...",
                             "..y..yyyy.y..", ".....y..y....", "............."])
    }
    static var flash: SKTexture { Tex.pixels("flash", ["..y....", ".yyw.y.", "yywwwyy", ".yyw.y.", "..y...."]) }
    static var crosshair: SKTexture {
        Tex.pixels("crosshair", ["....kkk....", "....kwk....", "....kwk....", "....kkk....", "kkkk...kkkk", "kwwk.w.kwwk",
                                 "kkkk...kkkk", "....kkk....", "....kwk....", "....kwk....", "....kkk...."])
    }
}

extension GameScene {
    // MARK: weapons

    func updateWeapons(_ f: Fighter, _ dt: Double) {
        var belt = f.weapons
        belt.cooldown -= dt
        if belt.grenades < Weapons.grenadeMax {
            belt.grenadeTimer += dt
            if belt.grenadeTimer >= Weapons.grenadeRecharge { belt.grenades += 1; belt.grenadeTimer = 0 }
        }
        let inp = f.input
        if inp.switchTo >= 0, inp.switchTo < Weapons.all.count, inp.switchTo != belt.current {
            belt.slots[belt.current].charging = false
            belt.slots[belt.current].charge = 0
            belt.current = inp.switchTo
            belt.cooldown = max(belt.cooldown, 0.12)
            f.rig.setWeapon(belt.current)
            f.switchT = 0
            if f.isPlayer { Audio.shared.play(.blip, volume: 0.4) }
        }
        let def = belt.def
        var s = belt.slots[belt.current]
        // reload & heat
        for k in 0..<belt.slots.count {
            if belt.slots[k].reloadLeft > 0 {
                belt.slots[k].reloadLeft -= dt
                if belt.slots[k].reloadLeft <= 0 { belt.slots[k].ammo = Weapons.all[k].mag; if f.isPlayer && k == belt.current { Audio.shared.play(.reload, volume: 0.5) } }
            }
            if Weapons.all[k].heat > 0 {
                belt.slots[k].heat = max(0, belt.slots[k].heat - CGFloat(dt) * 0.45)
                if belt.slots[k].overheated && belt.slots[k].heat < 0.3 { belt.slots[k].overheated = false }
            }
        }
        s = belt.slots[belt.current]
        if inp.reload, def.mag > 0, s.ammo < def.mag, s.reloadLeft <= 0 { s.reloadLeft = def.reload }
        if s.reloadLeft > 0 && f.weapons.slots[belt.current].reloadLeft <= 0 { magDrop(f) }

        let ready = belt.cooldown <= 0 && s.reloadLeft <= 0 && !s.overheated
        if def.kind == .charge {
            if inp.fire && ready && s.ammo > 0 {
                if !s.charging { s.charging = true; s.charge = 0; Audio.shared.play(.charge, volume: 0.3, pan: pan(f.pos)) }
                s.charge = min(1, s.charge + CGFloat(dt))
            }
            if s.charging && (!inp.fire || inp.fireReleased) {
                s.charging = false
                belt.slots[belt.current] = s
                f.weapons = belt
                fire(f, charge: s.charge)
                return
            }
        } else {
            // hold to keep firing, every weapon (semi-autos repeat at their fire rate)
            let want = inp.fire || inp.firePressed
            if want && ready {
                if def.mag > 0 && s.ammo <= 0 {
                    s.reloadLeft = def.reload
                    if f.isPlayer { Audio.shared.play(.empty, volume: 0.5) }
                } else {
                    belt.slots[belt.current] = s
                    f.weapons = belt
                    fire(f, charge: 0)
                    return
                }
            }
        }
        belt.slots[belt.current] = s
        f.weapons = belt

        if inp.melee { slash(f) }

        if inp.grenade && f.weapons.grenades > 0 {
            f.weapons.grenades -= 1
            throwGrenade(f)
        }
    }

    private func aimDir(_ f: Fighter) -> CGPoint { (f.input.aim - f.shoulder).normalized }

    /// Light bullet magnetism for the player: bends the shot up to ~4° toward an enemy near the crosshair.
    private func aimAssist(_ f: Fighter, _ dir: CGPoint) -> CGPoint {
        var best = dir, bestA: CGFloat = 0.07
        for o in fighters where o.alive && o.id != f.id {
            let to = o.center - f.muzzle
            let l = to.length
            guard l < 1000, l > 1 else { continue }
            let n = to * (1 / l)
            let a = acos(clamp(n.x * dir.x + n.y * dir.y, -1, 1))
            if a < bestA { bestA = a; best = n }
        }
        return (dir * 0.35 + best * 0.65).normalized
    }

    /// Empty magazine drops out of the gun.
    func magDrop(_ f: Fighter) {
        particles.emit(f.shoulder.x + f.facing * 8, f.shoulder.y - 6, vx: rng.range(-40, 40), vy: rng.range(20, 80), life: 1.0,
                       color: SKColor(white: 0.3, alpha: 1), size: 4, gravity: 1400, drag: 0.5)
        if f.isPlayer { Audio.shared.play(.empty, volume: 0.35) }
    }

    func fire(_ f: Fighter, charge: CGFloat) {
        var belt = f.weapons
        let def = belt.def
        var s = belt.slots[belt.current]
        if def.mag > 0 { s.ammo -= 1; if s.ammo <= 0 { s.reloadLeft = def.reload; magDrop(f) } }
        if def.heat > 0 { s.heat += def.heat; if s.heat >= 1 { s.overheated = true } }
        s.charge = 0
        belt.slots[belt.current] = s
        belt.cooldown = def.interval
        f.weapons = belt

        var dir = aimDir(f)
        let m = f.muzzle
        if f.isPlayer && def.kind != .rocket { dir = aimAssist(f, dir) }
        let recoil = def.recoil * (def.kind == .charge ? (0.5 + charge * 2.5) : 1)
        f.vel.x -= dir.x * recoil
        if !f.grounded || dir.y < -0.5 { f.vel.y -= dir.y * recoil * 0.6 }
        f.recoilKick = def.kind == .rocket || def.pellets > 1 || charge > 0.5 ? 0.45 : 0.18
        Audio.shared.play(def.sound, volume: f.isPlayer ? 0.8 : 0.45, pan: pan(m))
        // muzzle flash sized to the weapon, a puff of smoke, and a spent casing
        let big: CGFloat = def.pellets > 1 || def.kind == .rocket || charge > 0.5 ? 1.8 : def.kind == .laser ? 1.4 : 1.1
        fx.spawn(Art.flash, at: m, size: CGSize(width: 16 * big, height: 12 * big), rotation: atan2(dir.y, dir.x), life: 0.05,
                 anchor: CGPoint(x: 0.05, y: 0.5), z: 4, add: true)
        for _ in 0..<(def.pellets > 1 || def.kind == .rocket ? 5 : 2) {
            particles.emit(m.x, m.y, vx: dir.x * rng.range(20, 90) + rng.range(-20, 20), vy: dir.y * rng.range(20, 90) + rng.range(10, 50),
                           life: rng.range(0.35, 0.7), color: SKColor(white: rng.range(0.7, 0.9), alpha: 1), size: rng.chance(0.5) ? 3 : 4, gravity: -60, drag: 3)
        }
        if def.kind == .hitscan || def.kind == .charge {
            let back = -f.facing
            particles.emit(f.shoulder.x, f.shoulder.y + 2, vx: back * rng.range(60, 140), vy: rng.range(140, 260), life: 0.9,
                           color: SKColor(srgbRed: 1, green: 0.8, blue: 0.3, alpha: 1), size: 2, gravity: 1400, drag: 0.5)
        }
        if f.isPlayer { shake(def.shake) }

        switch def.kind {
        case .hitscan:
            for _ in 0..<def.pellets {
                let a = atan2(dir.y, dir.x) + rng.range(-def.spread, def.spread)
                shoot(from: m, dir: CGPoint(x: cos(a), y: sin(a)), def: def, owner: f.id, damage: def.damage, power: def.power,
                      carve: def.carve, width: def.tracerWidth)
            }
        case .charge:
            let dmg = lerp(def.damage, 85, charge)
            let hit = shoot(from: m, dir: dir, def: def, owner: f.id, damage: dmg, power: charge > 0.45 ? .word : .letter,
                            carve: lerp(def.carve, 16, charge), width: lerp(2, 7, charge))
            if charge >= 0.95, let hit { explode(at: hit.point - hit.normal * -2, radius: 40, damage: 30, owner: f.id) }
            shake(f.isPlayer ? 2 + charge * 4 : 0)
        case .laser:
            laser(from: m, dir: dir, def: def, owner: f.id)
        case .rocket:
            spawnProjectile(.rocket, at: m, vel: dir * def.speed, owner: f.id)
        case .blackhole:
            spawnProjectile(.blackhole, at: m, vel: dir * def.speed, owner: f.id)
            fx.spawn(Art.swirl, at: m, size: CGSize(width: 34, height: 34), color: SKColor(srgbRed: 0.8, green: 0.4, blue: 1, alpha: 1), life: 0.2, grow: 1, z: 5, add: true)
        case .saw:
            spawnProjectile(.saw, at: m, vel: dir * def.speed, owner: f.id, bounces: 5)
        case .lightning:
            lightning(from: m, dir: dir, def: def, owner: f.id)
            particles.burst(m, n: 3, speed: 160, life: 0.15, color: def.tracer, size: 2)
        case .plasma:
            let a = atan2(dir.y, dir.x) + rng.range(-def.spread, def.spread)
            spawnProjectile(.plasma, at: m, vel: CGPoint(x: cos(a), y: sin(a)) * def.speed, owner: f.id, bounces: 3)
        }
    }

    func throwGrenade(_ f: Fighter) {
        let d = aimDir(f)
        let v = d * 760 + CGPoint(x: f.vel.x * 0.4, y: 160)
        spawnProjectile(.grenade, at: f.shoulder + d * 10, vel: v, owner: f.id, fuse: CGFloat(Weapons.grenadeFuse))
        Audio.shared.play(.grenade, volume: 0.5, pan: pan(f.pos))
    }

    // MARK: hitscan

    /// Nearest thing along a->b: fighters (not `owner`), solid pixels of elements, debris.
    func trace(_ a: CGPoint, _ b: CGPoint, owner: Int, skip: Int = -1) -> ShotHit {
        let dx = b.x - a.x, dy = b.y - a.y
        var best = ShotHit(target: .none, point: b, normal: .zero, t: 1)
        for f in fighters where f.alive && f.id != owner {
            if let (t, n) = Level.segmentRect(a, dx, dy, f.bodyRect), t < best.t {
                best = ShotHit(target: .fighter(f.id), point: CGPoint(x: a.x + dx * t, y: a.y + dy * t), normal: n, t: t)
            }
        }
        // Elements: big ones are hit at their first opaque pixel so bullets fly through holes.
        let from = a
        var ignored = 0
        var ign = (-1, -1, -1, -1)
        while ignored < 4 {
            let seg = b - from
            guard let h = level.raycast(from, b, accept: { i in
                let e = level.elements[i]
                return e.kind != .ledge && i != skip && i != ign.0 && i != ign.1 && i != ign.2 && i != ign.3
            }) else { break }
            let tAbs = ((h.point - a).length) / max(1e-6, CGPoint(x: dx, y: dy).length)
            if tAbs >= best.t { break }
            let e = level.elements[h.index]
            if e.isBig, let c = canvas {
                // march inside the rect until an opaque pixel
                let dirn = seg.normalized
                var p = h.point, found = false
                var steps = 0
                while e.rect.insetBy(dx: -0.5, dy: -0.5).contains(p) && steps < 2000 {
                    if c.color(at: p).a > 40 { found = true; break }
                    p = p + dirn; steps += 1
                }
                let tp = ((p - a).length) / max(1e-6, CGPoint(x: dx, y: dy).length)
                if found {
                    if tp < best.t { best = ShotHit(target: .element(h.index), point: p, normal: h.normal, t: tp) }
                    break
                }
                switch ignored { case 0: ign.0 = h.index; case 1: ign.1 = h.index; case 2: ign.2 = h.index; default: ign.3 = h.index }
                ignored += 1
                continue
            }
            best = ShotHit(target: .element(h.index), point: h.point, normal: h.normal, t: tAbs)
            break
        }
        // Debris bodies.
        var bestD: SKPhysicsBody?
        var bestDT = best.t
        physicsWorld.enumerateBodies(alongRayStart: a, end: b) { body, p, n, _ in
            guard body.categoryBitMask == PhysCat.debris else { return }
            let t = (p - a).length / max(1e-6, CGPoint(x: dx, y: dy).length)
            if t < bestDT { bestDT = t; bestD = body; best.point = p; best.normal = CGPoint(x: n.dx, y: n.dy) }
        }
        if let bestD { best.target = .debris(bestD); best.t = bestDT }
        return best
    }

    @discardableResult
    func shoot(from a: CGPoint, dir: CGPoint, def: WeaponDef, owner: Int, damage: CGFloat, power: Power, carve: CGFloat, width: CGFloat) -> ShotHit? {
        let b = a + dir * def.range
        let h = trace(a, b, owner: owner)
        fx.line(a, h.point, width: width, color: def.tracer, life: 0.06)
        applyHit(h, dir: dir, def: def, owner: owner, damage: damage, power: power, carve: carve)
        if case .none = h.target { return nil }
        return h
    }

    func applyHit(_ h: ShotHit, dir: CGPoint, def: WeaponDef, owner: Int, damage: CGFloat, power: Power, carve: CGFloat) {
        switch h.target {
        case .none: break
        case .fighter(let id):
            let f = fighters[id]
            hurt(f, amount: damage, by: owner, dir: dir, knock: def.knock)
            particles.burst(h.point, n: 6, speed: 220, life: 0.35, color: f.color, size: 3, dir: dir, cone: 0.7)
        case .element(let i):
            hitElement(i, at: h.point, dir: dir, power: power, damage: damage, carve: carve)
            particles.burst(h.point, n: 3, speed: 260, life: 0.2, color: SKColor(srgbRed: 1, green: 0.9, blue: 0.5, alpha: 1), size: 2,
                            dir: h.normal, cone: 1.2)
        case .debris(let body):
            debris.wake(body: body)
            let m = body.mass
            body.applyImpulse(CGVector(dx: dir.x * m * 260, dy: dir.y * m * 260 + m * 80), at: h.point)
            body.angularVelocity += rng.range(-6, 6)
            particles.burst(h.point, n: 2, speed: 160, life: 0.2, color: .white, dir: h.normal, cone: 1)
        }
    }

    /// Piercing beam: slices through letters and fighters, stops at a big element.
    func laser(from a: CGPoint, dir: CGPoint, def: WeaponDef, owner: Int) {
        var p = a
        let end = a + dir * def.range
        var sliced = 0
        var stop = end
        var hitFighters: [Int] = []
        var lastElement = -1
        for _ in 0..<40 {
            let h = trace(p, end, owner: owner, skip: lastElement)
            switch h.target {
            case .none: stop = end
            case .fighter(let id):
                if !hitFighters.contains(id) {
                    hitFighters.append(id)
                    hurt(fighters[id], amount: def.damage, by: owner, dir: dir, knock: def.knock)
                    particles.burst(h.point, n: 8, speed: 260, life: 0.4, color: fighters[id].color, size: 3)
                }
                p = h.point + dir * (Move.halfW * 2 + 2)
                continue
            case .element(let i):
                let e = level.elements[i]
                if e.isBig || sliced >= 16 {
                    hitElement(i, at: h.point, dir: dir, power: .letter, damage: def.damage, carve: 6)
                    stop = h.point
                } else {
                    sliced += 1
                    hitElement(i, at: h.point, dir: dir, power: .letter, damage: def.damage, carve: def.carve)
                    p = h.point + dir * 0.5
                    lastElement = -1
                    continue
                }
            case .debris(let body):
                debris.wake(body: body)
                body.applyImpulse(CGVector(dx: dir.x * body.mass * 300, dy: dir.y * body.mass * 300 + body.mass * 100), at: h.point)
                p = h.point + dir * 2
                continue
            }
            break
        }
        fx.line(a, stop, width: 6, color: def.tracer.withAlphaComponent(0.35), life: 0.18)
        fx.line(a, stop, width: 2.5, color: SKColor(srgbRed: 1, green: 0.85, blue: 0.85, alpha: 1), life: 0.14)
        particles.burst(stop, n: 8, speed: 240, life: 0.3, color: def.tracer, size: 2, dir: dir * -1, cone: 1.2)
    }

    // MARK: projectiles

    func spawnProjectile(_ kind: Projectile.Kind, at p: CGPoint, vel: CGPoint, owner: Int, bounces: Int = 0, fuse: CGFloat = 0) {
        let node: SKSpriteNode
        if let n = projectilePool.popLast() { node = n } else { node = SKSpriteNode(); projectileRoot.addChild(node) }
        let tex: SKTexture
        var sz: CGSize
        switch kind {
        case .rocket: tex = Art.rocket; sz = CGSize(width: 18, height: 10)
        case .plasma: tex = Art.plasma; sz = CGSize(width: 12, height: 8)
        case .grenade: tex = Art.grenade; sz = CGSize(width: 12, height: 14)
        case .blackhole: tex = Art.holeCore; sz = CGSize(width: 30, height: 30)
        case .saw: tex = GunArts.sawBlade.texture("sawblade"); sz = CGSize(width: 22, height: 22)
        }
        node.texture = tex
        node.size = sz
        node.alpha = 1
        node.isHidden = false
        node.blendMode = kind == .plasma ? .add : .alpha
        node.position = p
        node.zRotation = atan2(vel.y, vel.x)
        projectiles.append(Projectile(kind: kind, pos: p, vel: vel, owner: owner, bounces: bounces, fuse: fuse, node: node))
    }

    func updateProjectiles(_ dt: CGFloat) {
        var i = 0
        while i < projectiles.count {
            var pr = projectiles[i]
            pr.age += dt
            var dead = false
            let a = pr.pos
            switch pr.kind {
            case .rocket:
                pr.vel = pr.vel * (1 + dt * 0.6)
                let b = a + pr.vel * dt
                let h = trace(a, b, owner: pr.age < 0.15 ? pr.owner : -1)
                if case .none = h.target {
                    pr.pos = b
                    if rng.chance(0.8) {
                        particles.emit(a.x, a.y, vx: rng.range(-30, 30), vy: rng.range(-30, 30), life: rng.range(0.3, 0.6),
                                       color: SKColor(white: rng.range(0.55, 0.8), alpha: 1), size: 4, gravity: -40, drag: 2)
                    }
                } else {
                    explode(at: h.point + h.normal * 2, radius: Weapons.rocketRadius, damage: Weapons.all[3].damage, owner: pr.owner)
                    dead = true
                }
            case .plasma:
                let b = a + pr.vel * dt
                let h = trace(a, b, owner: pr.age < 0.1 ? pr.owner : -1)
                switch h.target {
                case .none:
                    pr.pos = b
                case .fighter(let id):
                    hurt(fighters[id], amount: Weapons.all[4].damage, by: pr.owner, dir: pr.vel.normalized, knock: Weapons.all[4].knock)
                    particles.burst(h.point, n: 6, speed: 200, life: 0.3, color: Weapons.all[4].tracer, size: 2)
                    dead = true
                default:
                    applyHit(h, dir: pr.vel.normalized, def: Weapons.all[4], owner: pr.owner, damage: Weapons.all[4].damage, power: .letter, carve: 4)
                    particles.burst(h.point, n: 5, speed: 180, life: 0.25, color: Weapons.all[4].tracer, size: 2, dir: h.normal, cone: 1)
                    if pr.bounces > 0, h.normal != .zero {
                        pr.bounces -= 1
                        let n = h.normal
                        let d = pr.vel.x * n.x + pr.vel.y * n.y
                        pr.vel = CGPoint(x: pr.vel.x - 2 * d * n.x, y: pr.vel.y - 2 * d * n.y)
                        pr.pos = h.point + n * 2
                        Audio.shared.play(.bounce, volume: 0.25, pan: pan(h.point))
                    } else { dead = true }
                }
                if pr.age > 1.6 { dead = true }
            case .blackhole:
                let b = a + pr.vel * dt
                let h = trace(a, b, owner: pr.owner)
                if case .none = h.target, pr.age < 0.85 {
                    pr.pos = b
                    if rng.chance(0.9) {
                        particles.emit(a.x, a.y, vx: rng.range(-40, 40), vy: rng.range(-40, 40), life: 0.35,
                                       color: rng.chance(0.5) ? SKColor(srgbRed: 0.75, green: 0.35, blue: 1, alpha: 1) : .black, size: 3, gravity: 0, drag: 2)
                    }
                } else {
                    openSingularity(at: h.target.isNone ? b : h.point + h.normal * 6, owner: pr.owner)
                    dead = true
                }
            case .saw:
                if pr.stuck > 0 {
                    // embedded: keep grinding sparks, then fade out
                    pr.stuck -= dt
                    pr.node.alpha = min(1, pr.stuck)
                    if rng.chance(0.3) { particles.burst(pr.pos, n: 1, speed: 160, life: 0.25, color: .orange, size: 2) }
                    if pr.stuck <= 0 { dead = true }
                    break
                }
                pr.vel.y -= 260 * dt
                let b = a + pr.vel * dt
                let h = trace(a, b, owner: pr.age < 0.12 ? pr.owner : -1, skip: -1)
                let def = Weapons.all[8]
                switch h.target {
                case .none:
                    pr.pos = b
                case .fighter(let id):
                    // slices through fighters (once per pass)
                    if pr.hitID != id {
                        pr.hitID = id
                        hurt(fighters[id], amount: def.damage, by: pr.owner, dir: pr.vel.normalized, knock: def.knock)
                        particles.burst(h.point, n: 12, speed: 260, life: 0.4, color: fighters[id].color, size: 3, dir: pr.vel.normalized, cone: 0.9)
                        Audio.shared.play(.saw, volume: 0.5, pan: pan(h.point))
                    }
                    pr.pos = b
                case .element(let e) where level.elements[e].kind == .text && pr.cuts < 14:
                    // cuts through text without slowing
                    pr.cuts += 1
                    knockLetter(e, at: h.point, dir: pr.vel.normalized)
                    pr.pos = b
                default:
                    applyHit(h, dir: pr.vel.normalized, def: def, owner: pr.owner, damage: 12, power: .letter, carve: 4)
                    particles.burst(h.point, n: 8, speed: 260, life: 0.3, color: SKColor(srgbRed: 1, green: 0.75, blue: 0.3, alpha: 1), size: 2, dir: h.normal, cone: 1.2)
                    Audio.shared.play(.grind, volume: 0.45, pan: pan(h.point))
                    if pr.bounces > 0, h.normal != .zero {
                        pr.bounces -= 1
                        pr.hitID = -1
                        let n = h.normal
                        let d = pr.vel.x * n.x + pr.vel.y * n.y
                        pr.vel = CGPoint(x: (pr.vel.x - 2 * d * n.x) * 0.92, y: (pr.vel.y - 2 * d * n.y) * 0.92)
                        pr.pos = h.point + n * 3
                    } else {
                        pr.pos = h.point; pr.stuck = 2.5
                    }
                }
                if pr.pos.y < 8 && pr.stuck <= 0 { pr.pos.y = 8; pr.vel.y = abs(pr.vel.y) * 0.8; pr.bounces -= 1 }
                if pr.pos.x < 8 || pr.pos.x > size.width - 8 { pr.vel.x = -pr.vel.x; pr.pos.x = clamp(pr.pos.x, 8, size.width - 8); pr.bounces -= 1 }
                if pr.bounces < -1 && pr.stuck <= 0 { pr.stuck = 1 }
                if pr.age > 5 { dead = true }
            case .grenade:
                pr.vel.y -= 1500 * dt
                pr.fuse -= dt
                let b = a + pr.vel * dt
                let h = trace(a, b, owner: pr.owner)
                switch h.target {
                case .element, .debris:
                    let n = h.normal == .zero ? CGPoint(x: 0, y: 1) : h.normal
                    let d = pr.vel.x * n.x + pr.vel.y * n.y
                    pr.vel = CGPoint(x: (pr.vel.x - 2 * d * n.x) * 0.55, y: (pr.vel.y - 2 * d * n.y) * 0.45)
                    pr.pos = h.point + n * 3
                    if abs(d) > 120 { Audio.shared.play(.bounce, volume: 0.35, pan: pan(h.point)) }
                default:
                    pr.pos = b
                }
                if pr.pos.y < 3 { pr.pos.y = 3; pr.vel.y = abs(pr.vel.y) * 0.45; pr.vel.x *= 0.7 }
                if pr.pos.x < 3 || pr.pos.x > size.width - 3 { pr.vel.x = -pr.vel.x * 0.6; pr.pos.x = clamp(pr.pos.x, 3, size.width - 3) }
                if pr.fuse <= 0 {
                    explode(at: pr.pos, radius: Weapons.grenadeRadius, damage: Weapons.grenadeDamage, owner: pr.owner)
                    dead = true
                }
            }
            if pr.pos.x < -300 || pr.pos.x > size.width + 300 || pr.pos.y < -300 || pr.pos.y > size.height + 600 { dead = true }
            if dead {
                pr.node.isHidden = true
                projectilePool.append(pr.node)
                projectiles.swapAt(i, projectiles.count - 1)
                projectiles.removeLast()
                continue
            }
            pr.node.position = pr.pos
            switch pr.kind {
            case .grenade: pr.node.zRotation -= pr.vel.x * dt * 0.05
            case .saw: if pr.stuck <= 0 { pr.node.zRotation -= dt * 38 * (pr.vel.x >= 0 ? 1 : -1) }
            case .blackhole: pr.node.zRotation -= dt * 10
            default: pr.node.zRotation = atan2(pr.vel.y, pr.vel.x)
            }
            projectiles[i] = pr
            i += 1
        }
    }

    func clearProjectiles() {
        for p in projectiles { p.node.isHidden = true; projectilePool.append(p.node) }
        projectiles.removeAll()
    }

    // MARK: damage

    func hurt(_ f: Fighter, amount: CGFloat, by: Int, dir: CGPoint, knock: CGFloat) {
        guard f.alive, simTime >= f.invulnUntil else { return }
        var amount = amount
        // bots hit the player softer, by difficulty (the player has one life bar vs. several bots)
        if f.isPlayer && by >= 0 && by != f.id { amount *= [0.5, 0.7, 1.0][difficulty.rawValue] }
        amount = absorbArmor(f, amount)
        f.hp -= amount
        f.hitFlash = 0.08
        f.hitKick = 1
        f.hitDirX = dir.x >= 0 ? 1 : -1
        if f.isPlayer { hud.hurt() }
        if by == player.id && !f.isPlayer { hud.markHit() }
        f.vel.x += dir.x * knock
        f.vel.y += max(0, dir.y) * knock + knock * 0.4
        if knock > 0 { f.grounded = false }
        if by >= 0 && by != f.id { f.lastHitBy = by; f.lastHitTime = simTime }
        if amount >= 1 { damageNumber(Int(amount.rounded()), at: f.center + CGPoint(x: 0, y: 30)) }
        if by == player.id || f.isPlayer { hitStop(0.03) }
        Audio.shared.play(.hit, volume: 0.5, pan: pan(f.pos))
        if f.hp <= 0 { kill(f, by: f.lastHitBy >= 0 && simTime - f.lastHitTime < 4 ? f.lastHitBy : by) }
    }

    // MARK: juice

    func shake(_ amount: CGFloat) { shakeAmp = max(shakeAmp, amount) }
    func hitStop(_ s: Double) { hitStopLeft = max(hitStopLeft, s) }
}

extension ShotTarget {
    var isNone: Bool { if case .none = self { return true }; return false }
}
