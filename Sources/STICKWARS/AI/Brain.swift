import CoreGraphics

struct BotSkill {
    var aimErr: CGFloat      // max aim wobble, radians
    var reaction: Double     // delay before shooting after gaining sight
    var burst: Double, pause: Double
    var grenadeChance: CGFloat
}

extension Difficulty {
    var skill: BotSkill {
        switch self {
        case .easy: return BotSkill(aimErr: 0.16, reaction: 0.6, burst: 0.35, pause: 0.9, grenadeChance: 0.002)
        case .normal: return BotSkill(aimErr: 0.08, reaction: 0.35, burst: 0.55, pause: 0.5, grenadeChance: 0.004)
        case .hard: return BotSkill(aimErr: 0.035, reaction: 0.18, burst: 0.8, pause: 0.3, grenadeChance: 0.007)
        }
    }
}

/// One bot: sticky target, A* over the ledge graph, bursts of fire with human-ish aim error.
final class Brain {
    unowned let f: Fighter
    var target = -1
    private var targetUntil = 0.0
    private var path: [NavEdge] = []
    private var pathIdx = 0
    private var replanAt = 0.0
    private var edgeActive = false, doubleDone = false, jumpedAt = 0.0
    private var losAt = 0.0, hasLOS = false, seenSince = -1.0
    private var burstUntil = 0.0, pauseUntil = 0.0
    private var aimOff: CGFloat = 0
    private let aimPhase = rng.range(0, 100)
    private var weaponAt = 0.0, grenadeAt = 0.0
    private var stuckT = 0.0, lastX: CGFloat = 0
    private var strafeDir: CGFloat = 1, strafeUntil = 0.0
    private var chargeGoal: CGFloat = 0.6
    private var coverNode = -1
    /// Demo reels: keep this weapon instead of choosing by range.
    var lockedWeapon: Int?
    /// Demo reels: stand still (looking around) until this time; flashier movement; better aim.
    var holdUntil = 0.0
    var stylish = false
    var skillOverride: BotSkill?
    var scripted = false

    init(_ f: Fighter) { self.f = f }

    func forceReplan() { replanAt = 0 }

    func debug(_ s: GameScene) -> String {
        let e = pathIdx < path.count ? "\(path[pathIdx].kind) to \(path[pathIdx].to) takeoff \(Int(path[pathIdx].takeoff)) land \(Int(path[pathIdx].land))" : "-"
        return "\(f.name) node=\(s.nav.node(at: f.pos)) target=\(target) los=\(hasLOS) path=\(pathIdx)/\(path.count) edge=\(e) active=\(edgeActive) input=(\(f.input.moveX),j\(f.input.jumpHeld),jet\(f.input.jet),fire\(f.input.fire)) fuel=\(String(format: "%.2f", f.jetFuel))"
    }

    func think(_ s: GameScene, _ dt: Double) {
        var inp = FighterInput()
        inp.aim = f.input.aim
        let now = s.simTime
        guard f.alive, !s.matchOver else { f.input = inp; return }
        let skill = skillOverride ?? s.difficulty.skill
        if scripted { return }   // the director is driving this fighter
        if now < holdUntil {
            // opening beat: catch breath, glance left and right, then weapon up
            let look: CGFloat = sin(CGFloat(now) * 2.2) > 0 ? 1 : -1
            inp.aim = f.shoulder + CGPoint(x: look * 200, y: -40)
            f.facing = look
            f.input = inp
            return
        }

        // 1. Target: sticky for 3-6 s, spread so bots don't all gang up on the player.
        if target < 0 || target >= s.fighters.count || !s.fighters[target].alive || now > targetUntil { pickTarget(s) }
        let T: Fighter? = target >= 0 && target < s.fighters.count && s.fighters[target].alive ? s.fighters[target] : nil

        // 2. Goal: health when hurt, cover when low, otherwise the target.
        var goal = f.pos
        let dist = T.map { $0.pos.dist(f.pos) } ?? 0
        let pref = preferredRange()
        if f.hp < 55, let pk = s.nearestPickup(to: f.pos), pk.dist(f.pos) < 800 {
            goal = pk
        } else if f.armor < 25, let pk = s.nearestPickup(to: f.pos, .armor), pk.dist(f.pos) < 500 {
            goal = pk
        } else if f.hp < 35, let T, dist < 400 {
            if coverNode < 0 || coverNode >= s.nav.nodes.count || now >= replanAt { coverNode = s.coverNode(for: f, from: T) }
            if coverNode >= 0 { let n = s.nav.nodes[coverNode]; goal = CGPoint(x: (n.x0 + n.x1) / 2, y: n.y) }
        } else if let T {
            goal = T.pos
            if hasLOS && abs(dist - pref) < 140 { goal = f.pos } // good spot: hold and strafe
        }
        // demo hero holds the featured window; the fight comes to it
        if stylish, let st = s.stage?.insetBy(dx: 20, dy: 10), !st.contains(goal) {
            goal = CGPoint(x: clamp(goal.x, st.minX, st.maxX), y: clamp(goal.y, st.minY, st.maxY))
        }

        // 3. Navigate along the path.
        var wantMove = false
        if now >= replanAt && f.grounded && !s.nav.nodes.isEmpty {
            replanAt = now + 0.5 + Double(rng.range(0, 0.2))
            let from = s.nav.node(at: f.pos)
            let to = s.nav.node(below: goal + CGPoint(x: 0, y: 4))
            if from >= 0, from != to, s.nav.path(from: from, to: to, into: &path) { pathIdx = 0; edgeActive = false } else { path.removeAll(keepingCapacity: true) }
        }
        if pathIdx < path.count {
            wantMove = true
            let e = path[pathIdx]
            if f.grounded {
                let cur = s.nav.node(at: f.pos)
                if cur == Int(e.to) {
                    pathIdx += 1; edgeActive = false
                } else if edgeActive && now - jumpedAt > 0.2 {
                    replanAt = now // landed somewhere unexpected
                    edgeActive = false
                } else if !edgeActive {
                    let dx = e.takeoff - f.pos.x
                    if abs(dx) > 7 && e.kind != .walk && e.kind != .fall {
                        inp.moveX = dx > 0 ? 1 : -1
                    } else {
                        switch e.kind {
                        case .walk, .fall:
                            inp.moveX = e.land > f.pos.x ? 1 : -1
                            if e.kind == .fall && abs(dx) < 10 { edgeActive = true; jumpedAt = now }
                        case .jet where f.jetFuel < 0.7:
                            inp.moveX = 0 // wait for fuel
                        case .jump, .doubleJump, .jet:
                            inp.jumpPressed = true; inp.jumpHeld = true
                            edgeActive = true; doubleDone = false; jumpedAt = now
                            inp.moveX = abs(e.land - f.pos.x) > 6 ? (e.land > f.pos.x ? 1 : -1) : 0
                        case .drop:
                            inp.down = true; inp.downPressed = true
                            edgeActive = true; jumpedAt = now
                        }
                    }
                }
            } else {
                let dx = e.land - f.pos.x
                inp.moveX = abs(dx) > 5 ? (dx > 0 ? 1 : -1) : 0
                inp.jumpHeld = f.vel.y > 0
                if e.kind == .doubleJump && !doubleDone && f.vel.y < 80 && f.airJumps > 0 {
                    inp.jumpPressed = true; inp.jumpHeld = true; doubleDone = true
                }
                // jet links fly up to the ledge; other jumps get jet help if they fall short
                if s.nav.nodes.indices.contains(Int(e.to)) {
                    let ty = s.nav.nodes[Int(e.to)].y
                    if e.kind == .jet { inp.jet = f.pos.y < ty + 30; inp.jumpHeld = true }
                    else if ty > f.pos.y + 30, f.vel.y < -100 { inp.jet = f.jetFuel > 0.3 }
                }
            }
        } else if let T {
            // Same ledge (or no path): keep preferred range, strafe a little.
            let dx = T.pos.x - f.pos.x
            if abs(dx) > pref + 60 { inp.moveX = dx > 0 ? 1 : -1; wantMove = true }
            else if abs(dx) < pref - 100 { inp.moveX = dx > 0 ? -1 : 1; wantMove = true }
            else {
                if now > strafeUntil { strafeDir = rng.chance(0.5) ? 1 : -1; strafeUntil = now + Double(rng.range(0.5, 1.2)) }
                inp.moveX = rng.chance(0.85) ? strafeDir : 0
            }
            // jump at targets above when no path found
            if T.pos.y > f.pos.y + 60 && f.grounded && rng.chance(0.02) { inp.jumpPressed = true; inp.jumpHeld = true }
        }
        // Demo hero: flips and hops while fighting (double jump = front flip), wall-jumps off walls.
        if stylish {
            if f.grounded && rng.chance(0.012) { inp.jumpPressed = true; inp.jumpHeld = true }
            if !f.grounded && f.vel.y < 120 && f.vel.y > -40 && f.airJumps > 0 && rng.chance(0.08) { inp.jumpPressed = true; inp.jumpHeld = true }
            if !f.grounded && f.wallDir != 0 && rng.chance(0.1) { inp.jumpPressed = true; inp.jumpHeld = true }
        }
        // Stuck against something: hop or wall-jump.
        if wantMove && abs(f.pos.x - lastX) < 0.3 && inp.moveX != 0 { stuckT += dt } else { stuckT = 0 }
        if stuckT > 0.35 { inp.jumpPressed = true; inp.jumpHeld = true; stuckT = 0; replanAt = now + 0.25 }
        if !f.grounded && f.wallDir != 0 && goal.y > f.pos.y + 40 && f.vel.y < 0 && rng.chance(0.08) { inp.jumpPressed = true; inp.jumpHeld = true }
        lastX = f.pos.x

        // 4. Aim and fire.
        if let T {
            let def = f.weapons.def
            var aimAt = T.center
            if def.kind == .rocket || def.kind == .plasma {
                let lead = dist / max(1, def.speed)
                aimAt = aimAt + CGPoint(x: T.vel.x * lead * 0.7, y: 0)
            }
            // smooth wobble, mostly near the target, sometimes off by up to aimErr
            let t = CGFloat(now) + aimPhase
            aimOff = skill.aimErr * (0.6 * sin(t * 1.7) + 0.4 * sin(t * 3.3 + 1.3))
            let v = aimAt - f.shoulder
            let a = atan2(v.y, v.x) + aimOff
            let l = max(60, v.length)
            inp.aim = f.shoulder + CGPoint(x: cos(a) * l, y: sin(a) * l)

            if now >= losAt {
                losAt = now + 0.12
                let h = s.trace(f.muzzle, T.center, owner: f.id)
                switch h.target {
                case .fighter(let id): hasLOS = id == T.id
                case .element(let i): hasLOS = !s.level.elements[i].isBig // shoot through text and small stuff
                case .debris: hasLOS = true
                case .none: hasLOS = true
                }
                if hasLOS { if seenSince < 0 { seenSince = now } } else { seenSince = -1 }
            }
            if now >= weaponAt {
                weaponAt = now + Double(rng.range(1.0, 2.0))
                let w = lockedWeapon ?? chooseWeapon(dist: dist, below: T.pos.y < f.pos.y - 40)
                if w != f.weapons.current { inp.switchTo = w }
            }
            let canFire = hasLOS && seenSince >= 0 && now - seenSince > skill.reaction && dist < def.range * 0.85
            if canFire {
                if now >= burstUntil && now >= pauseUntil {
                    burstUntil = now + skill.burst * Double(rng.range(0.6, 1.4))
                    pauseUntil = burstUntil + skill.pause * Double(rng.range(0.6, 1.4))
                }
                if now < burstUntil {
                    switch def.kind {
                    case .charge:
                        let st = f.weapons.slots[f.weapons.current]
                        if st.charging && st.charge >= chargeGoal { inp.fire = false; chargeGoal = rng.range(0.3, 1.0) } else { inp.fire = true }
                    default:
                        if def.auto { inp.fire = true } else if f.weapons.cooldown <= 0 { inp.firePressed = true; inp.fire = true }
                    }
                }
            } else if def.kind == .charge && f.weapons.slots[f.weapons.current].charging {
                inp.fire = true // keep charging until sight returns
            }
            if dist < 58 && hasLOS && rng.chance(0.25) { inp.melee = true }
            if dist > 110 && dist < 420 && f.weapons.grenades > 0 && now > grenadeAt && rng.chance(skill.grenadeChance) && hasLOS {
                grenadeAt = now + 4
                inp.grenade = true
                inp.aim = T.pos + CGPoint(x: 0, y: dist * 0.45)
            }
            if !canFire, def.mag > 0, f.weapons.slots[f.weapons.current].ammo < def.mag / 2, rng.chance(0.01) { inp.reload = true }
        } else {
            inp.aim = f.pos + CGPoint(x: f.facing * 200, y: 30)
        }
        f.facing = inp.aim.x >= f.pos.x ? 1 : -1
        f.input = inp
    }

    private func pickTarget(_ s: GameScene) {
        var best = -1, bestScore = CGFloat.infinity
        var onPlayer = 0
        for b in s.brains where b !== self && b.target == s.player.id { onPlayer += 1 }
        for o in s.fighters where o.alive && o.id != f.id {
            var score = o.pos.dist(f.pos) + rng.range(0, 140)
            if o.isPlayer && !s.demo { score += CGFloat(onPlayer) * 260 }
            if o.id == f.lastHitBy && s.simTime - f.lastHitTime < 2.5 { score -= 250 }
            if s.simTime < o.invulnUntil { score += 300 }
            if score < bestScore { bestScore = score; best = o.id }
        }
        target = best
        targetUntil = s.simTime + Double(rng.range(3, 6))
        seenSince = -1
    }

    private func preferredRange() -> CGFloat {
        let k: CGFloat = stylish ? 0.65 : 1
        return k * baseRange()
    }

    private func baseRange() -> CGFloat {
        switch f.weapons.current {
        case 2, 9: return 130
        case 1, 4, 8: return 280
        case 3: return 380
        default: return 360
        }
    }

    private func chooseWeapon(dist: CGFloat, below: Bool) -> Int {
        let r = rng.unit()
        if dist < 170 { return r < 0.45 ? 2 : r < 0.75 ? 9 : 1 }
        if dist < 420 {
            if below && r < 0.2 { return 3 }
            return r < 0.3 ? 1 : r < 0.5 ? 4 : r < 0.68 ? 8 : r < 0.84 ? 9 : r < 0.92 ? 7 : 0
        }
        return r < 0.3 ? 6 : r < 0.5 ? 5 : r < 0.65 ? 7 : r < 0.8 ? 8 : r < 0.9 ? 0 : 3
    }
}
