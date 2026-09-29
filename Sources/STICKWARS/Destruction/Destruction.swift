import SpriteKit

/// Breaking the snapshot: letter knock-outs, carved holes, crumbling, and explosions with
/// fractured shards. Text lifts off the page (its spot is refilled with the panel colour);
/// images and anything off a flat panel break the screen itself, revealing the backdrop.
extension GameScene {
    private var clearColor: RGBA { RGBA(0, 0, 0, 0) }

    /// Colour for pixel particles near p.
    func inkColor(_ p: CGPoint) -> SKColor {
        guard let c = canvas else { return .white }
        let v = c.color(at: p)
        return v.a < 10 ? SKColor(white: 0.2, alpha: 1) : v.sk
    }

    // MARK: bullet hits

    /// A projectile / hitscan hit on element i.
    func hitElement(_ i: Int, at p: CGPoint, dir: CGPoint, power: Power, damage: CGFloat, carve: CGFloat) {
        let e = level.elements[i]
        guard e.state == .solid else { return }
        switch e.kind {
        case .ledge: return
        case .text:
            if power == .letter { knockLetter(i, at: p, dir: dir) } else { breakLoose(i, from: p, dir: dir, speed: 380) }
        case .line:
            breakLoose(i, from: p, dir: dir, speed: 250)
        case .control where !e.isBig:
            level.damage(i, hp: damage)
            particles.burst(p, n: 5, speed: 200, life: 0.35, color: inkColor(p), dir: dir * -1, cone: 1.2)
            if level.elements[i].hp <= 0 || power == .heavy { breakLoose(i, from: p, dir: dir, speed: 320) }
            else { Audio.shared.play(.hit, volume: 0.25, pan: pan(p)) }
        default:
            carveHole(i, at: p, radius: carve, dir: dir, damage: damage)
        }
    }

    /// Knocks the letter under p out of word i; the rest of the word stays as up to two new elements.
    func knockLetter(_ i: Int, at p: CGPoint, dir: CGPoint) {
        guard let c = canvas else { return }
        let e = level.elements[i]
        let (bg, flat) = c.borderBackground(e.rect)
        let letters = e.letters ?? c.letterSpans(e.rect, bg: bg)
        guard letters.count > 1 else { breakLoose(i, from: p, dir: dir, speed: 380); return }
        var k = 0, best = CGFloat.greatestFiniteMagnitude
        for (j, l) in letters.enumerated() {
            let d = p.x < l.minX ? l.minX - p.x : p.x > l.maxX ? p.x - l.maxX : 0
            if d < best { best = d; k = j }
        }
        let L = c.inkBounds(letters[k], bg: bg)?.insetBy(dx: -0.5, dy: -0.5) ?? letters[k]
        if let img = flat ? c.cropKnockout(L, bg: bg) : c.crop(L) {
            let v = CGVector(dx: dir.x * rng.range(220, 420) + rng.range(-40, 40), dy: dir.y * 200 + rng.range(150, 320))
            debris.spawn(img, rect: c.aligned(L), vel: v, spin: rng.range(-14, 14), time: simTime)
        }
        c.fillRect(letters[k].insetBy(dx: -0.5, dy: 0), flat ? bg : clearColor)
        level.remove(i, state: .loose)
        let left = Array(letters[..<k]), right = Array(letters[(k + 1)...])
        for part in [left, right] where !part.isEmpty {
            var r = part[0]
            for l in part { r = r.union(l) }
            r = CGRect(x: r.minX, y: e.rect.minY, width: r.width, height: e.rect.height)
            var ne = Element(rect: r, kind: .text, fromAX: e.fromAX)
            ne.letters = part
            level.add(ne)
        }
        particles.burst(p, n: 4, speed: 160, life: 0.3, color: inkColor(L.center), dir: dir * -1, cone: 1)
        Audio.shared.play(.pop, volume: 0.5, pan: pan(p))
    }

    /// Removes element i from the static world and throws its exact pixels as rigid bodies.
    func breakLoose(_ i: Int, from p: CGPoint, dir: CGPoint, speed: CGFloat) {
        guard let c = canvas, level.elements[i].state == .solid else { return }
        let e = level.elements[i]
        // Elements drawn inside this one (a button's label) go with it.
        level.collect(e.rect.insetBy(dx: -1, dy: -1), into: &scratch)
        for j in scratch where j != i && e.rect.insetBy(dx: -1, dy: -1).contains(level.elements[j].rect) && level.elements[j].kind != .ledge {
            level.remove(j, state: .loose)
        }
        if e.kind == .image && e.rect.width * e.rect.height > 90 * 90 {
            crumble(i, from: p); return
        }
        let (bg, flat) = e.kind == .image ? (RGBA(0, 0, 0, 0), false) : c.borderBackground(e.rect)
        let r = e.rect.insetBy(dx: -0.5, dy: -0.5)
        if let img = flat ? c.cropKnockout(r, bg: bg) : c.crop(r) {
            let out = (e.rect.center - p).normalized
            let d = (dir + out * 0.5).normalized
            let v = CGVector(dx: d.x * speed * rng.range(0.7, 1.1), dy: d.y * speed * 0.6 + rng.range(120, 280))
            let spin = rng.range(-6, 6) * (e.rect.width > 60 ? 0.4 : 1)
            debris.spawn(img, rect: c.aligned(r), vel: v, spin: spin, time: simTime)
        }
        c.fillRect(r, flat ? bg : clearColor)
        level.remove(i, state: .loose)
        Audio.shared.play(e.kind == .text ? .pop : .shatter, volume: 0.5, pan: pan(p))
    }

    /// Carves a jagged hole into a big element; it crumbles at 0 HP or 40% carved.
    func carveHole(_ i: Int, at p: CGPoint, radius: CGFloat, dir: CGPoint, damage: CGFloat) {
        guard let c = canvas else { return }
        let e = level.elements[i]
        for _ in 0..<6 {
            let q = p + CGPoint(x: rng.range(-radius, radius), y: rng.range(-radius, radius))
            let col = inkColor(q)
            let a = atan2(-dir.y, -dir.x) + rng.range(-1.1, 1.1)
            let s = rng.range(120, 380)
            particles.emit(q.x, q.y, vx: cos(a) * s, vy: sin(a) * s + 80, life: rng.range(0.3, 0.7), color: col, size: rng.chance(0.3) ? 3 : 2)
        }
        c.fillPolygon(Canvas.jaggedCircle(p, radius, &rng, n: 10), clearColor)
        level.damage(i, hp: damage, carved: .pi * radius * radius * 0.7)
        let ne = level.elements[i]
        if ne.hp <= 0 || ne.carved > 0.4 * e.rect.width * e.rect.height {
            breakLoose(i, from: p, dir: dir, speed: 300)
        } else {
            Audio.shared.play(.hit, volume: 0.3, pan: pan(p))
        }
    }

    /// Breaks a big element into jittered grid chunks cut from its real pixels.
    func crumble(_ i: Int, from p: CGPoint) {
        guard let c = canvas else { return }
        let e = level.elements[i]
        let r = e.rect
        var cols = max(1, Int(r.width / 44)), rows = max(1, Int(r.height / 44))
        while cols * rows > 20 { if cols > rows { cols -= 1 } else { rows -= 1 } }
        let cw = r.width / CGFloat(cols), ch = r.height / CGFloat(rows)
        for y in 0..<rows { for x in 0..<cols {
            let cr = CGRect(x: r.minX + CGFloat(x) * cw, y: r.minY + CGFloat(y) * ch, width: cw, height: ch).integral
            guard let img = c.crop(cr) else { continue }
            let d = (cr.center - p).normalized
            let v = CGVector(dx: d.x * rng.range(80, 260), dy: d.y * rng.range(60, 200) + rng.range(40, 200))
            debris.spawn(img, rect: c.aligned(cr), vel: v, spin: rng.range(-3, 3), time: simTime)
        } }
        c.fillRect(r.insetBy(dx: -0.5, dy: -0.5), clearColor)
        level.remove(i, state: .loose)
        particles.burst(r.center, n: 24, speed: 260, life: 0.6, color: inkColor(r.center), size: 3)
        Audio.shared.play(.shatter, volume: 0.8, pan: pan(p))
        shake(4)
    }

    // MARK: explosions

    func explode(at p: CGPoint, radius R: CGFloat, damage: CGFloat, owner: Int) {
        guard let c = canvas else { return }
        Audio.shared.play(.explosion, volume: 1, pan: pan(p))
        shake(R > 60 ? 9 : 5)
        hitStop(0.06)

        // 1. Small elements in range fly outward; big ones take damage. (Copy pixels before the crater.)
        level.collect(CGRect(x: p.x - R, y: p.y - R, width: R * 2, height: R * 2), into: &scratch)
        let hits = scratch
        var knocked = 0
        var crumbleList: [Int] = []
        for i in hits where level.elements[i].state == .solid {
            let e = level.elements[i]
            let q = CGPoint(x: clamp(p.x, e.rect.minX, e.rect.maxX), y: clamp(p.y, e.rect.minY, e.rect.maxY))
            let dist = q.dist(p)
            guard dist < R else { continue }
            let fall = 1 - dist / R
            switch e.kind {
            case .ledge:
                // cut the ledge where the blast is
                let cut = R * 0.6
                level.remove(i)
                if p.x - cut > e.rect.minX + 20 { level.add(Element(rect: CGRect(x: e.rect.minX, y: e.rect.minY, width: p.x - cut - e.rect.minX, height: e.rect.height), kind: .ledge)) }
                if e.rect.maxX > p.x + cut + 20 { level.add(Element(rect: CGRect(x: p.x + cut, y: e.rect.minY, width: e.rect.maxX - p.x - cut, height: e.rect.height), kind: .ledge)) }
            case _ where e.isBig:
                let overlap = e.rect.intersection(CGRect(x: p.x - R * 0.55, y: p.y - R * 0.55, width: R * 1.1, height: R * 1.1))
                level.damage(i, hp: damage * 2 * fall, carved: overlap.isNull ? 0 : overlap.width * overlap.height * 0.8)
                let ne = level.elements[i]
                if ne.hp <= 0 || ne.carved > 0.4 * e.rect.width * e.rect.height { crumbleList.append(i) }
            default:
                if knocked < 70 {
                    knocked += 1
                    let d = (e.rect.center - p).normalized
                    breakLoose(i, from: p, dir: d, speed: 500 + 500 * fall)
                } else {
                    c.fillRect(e.rect, clearColor); level.remove(i)
                }
            }
        }

        // 2. Crater: shatter the parts that show real content into shards cut from the pixels (taken
        // before any scorching, so they keep their true colours). Flat areas (plain backgrounds)
        // turn into pixel dust instead of featureless grey triangles.
        let fr = Fracture.make(center: p, radius: R * 0.55, rng: &rng)
        var shards = 0
        for cell in fr.cells where shards < 12 && (cell.ring == fr.rings || rng.chance(0.4)) {
            let b = Fracture.bounds(cell.poly)
            let centroid = b.center
            let d = (centroid - p).normalized
            guard c.color(at: centroid).a > 20 else { continue }
            if isFlat(c, b) {
                let col = c.color(at: centroid).sk
                for _ in 0..<4 {
                    let q = CGPoint(x: rng.range(b.minX, b.maxX), y: rng.range(b.minY, b.maxY))
                    let sp = rng.range(200, 520)
                    particles.emit(q.x, q.y, vx: d.x * sp + rng.range(-60, 60), vy: d.y * sp + rng.range(80, 220), life: rng.range(0.5, 0.9),
                                   color: col, size: rng.chance(0.5) ? 3 : 4, gravity: 1100, drag: 1)
                }
                continue
            }
            guard let img = c.cropPolygon(cell.poly, bounds: b) else { continue }
            let s = rng.range(350, 750)
            // the crop is pixel-aligned; place the sprite on the same pixel rect
            debris.spawn(img, rect: c.aligned(b), poly: cell.core, vel: CGVector(dx: d.x * s, dy: d.y * s + 250), spin: rng.range(-12, 12), time: simTime)
            shards += 1
        }
        c.scorch(p, radius: R * 0.95, seed: rng.next())
        c.fillPolygon(fr.outline, clearColor)
        for crack in fr.cracks { c.drawPolyline(crack, RGBA(12, 10, 14), alpha: 0.85, width: 2) }
        for i in crumbleList where level.elements[i].state == .solid { crumble(i, from: p) }

        // 3. Pixel fireball, sparks and smoke.
        let fire: [SKColor] = [SKColor(srgbRed: 1, green: 0.95, blue: 0.6, alpha: 1), SKColor(srgbRed: 1, green: 0.7, blue: 0.2, alpha: 1),
                               SKColor(srgbRed: 1, green: 0.4, blue: 0.1, alpha: 1), SKColor(srgbRed: 0.8, green: 0.15, blue: 0.1, alpha: 1)]
        for k in 0..<60 {
            let a = rng.range(0, .pi * 2), s = rng.range(60, 520) * (R / 70)
            particles.emit(p.x, p.y, vx: cos(a) * s, vy: sin(a) * s, life: rng.range(0.25, 0.6), color: fire[k % 4],
                           size: rng.chance(0.5) ? 4 : 6, gravity: -120, drag: 4)
        }
        for _ in 0..<18 {
            let a = rng.range(0, .pi * 2), s = rng.range(20, 120)
            particles.emit(p.x + cos(a) * R * 0.3, p.y + sin(a) * R * 0.3, vx: cos(a) * s, vy: sin(a) * s + 60, life: rng.range(0.8, 1.6),
                           color: SKColor(white: rng.range(0.25, 0.45), alpha: 1), size: rng.chance(0.5) ? 6 : 8, gravity: -60, drag: 2)
        }
        particles.burst(p, n: 30, speed: 700, life: 0.5, color: SKColor(srgbRed: 1, green: 0.9, blue: 0.5, alpha: 1), size: 2, gravity: 600)
        fx.spawn(Art.blast, at: p, size: CGSize(width: R * 1.1, height: R * 1.1), rotation: CGFloat(rng.int(4)) * .pi / 2,
                 life: 0.14, grow: 0.6, z: 3, add: true)

        // 4. Fighters and debris.
        for f in fighters where f.alive {
            let d = f.center - p
            let l = d.length
            guard l < R + 20 else { continue }
            let fall = clamp(1 - l / (R + 20), 0, 1)
            let n = d.normalized
            let self_ = f.id == owner
            // rocket jumps: self damage is reduced, knockback is full
            hurt(f, amount: damage * fall * (self_ ? 0.35 : 1), by: owner, dir: n, knock: 0)
            f.vel.x += n.x * 900 * fall
            f.vel.y = max(f.vel.y, 0) + (n.y * 0.5 + 0.7) * 900 * fall
            f.grounded = false
        }
        debris.blast(p, radius: R, speed: 900)
    }

    /// True when a region is one plain colour (sampled on a small grid).
    func isFlat(_ c: Canvas, _ r: CGRect) -> Bool {
        var lo = (255, 255, 255), hi = (0, 0, 0)
        for gy in 0..<4 { for gx in 0..<4 {
            let q = CGPoint(x: r.minX + r.width * (CGFloat(gx) + 0.5) / 4, y: r.minY + r.height * (CGFloat(gy) + 0.5) / 4)
            let v = c.color(at: q)
            lo = (min(lo.0, Int(v.r)), min(lo.1, Int(v.g)), min(lo.2, Int(v.b)))
            hi = (max(hi.0, Int(v.r)), max(hi.1, Int(v.g)), max(hi.2, Int(v.b)))
        } }
        return (hi.0 - lo.0) + (hi.1 - lo.1) + (hi.2 - lo.2) < 36
    }

    @inline(__always) func pan(_ p: CGPoint) -> Float { Float((p.x / size.width) * 2 - 1) * 0.7 }
}
