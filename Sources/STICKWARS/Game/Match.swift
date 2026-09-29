import SpriteKit

enum PickupKind { case health, armor }

struct Pickup {
    var kind: PickupKind
    var pos: CGPoint
    var node: SKSpriteNode
    var born: Double
}

extension Art {
    static var medkit: SKTexture {
        Tex.pixels("medkit", [".kkkkkkkk.", "kwwwwwwwwk", "kwwwrrwwwk", "kwwwrrwwwk", "kwrrrrrrwk",
                              "kwrrrrrrwk", "kwwwrrwwwk", "kwwwrrwwwk", "kwwwwwwwwk", ".kkkkkkkk."])
    }

    static let portalFrames = (0..<3).map { portal($0) }

    /// Dark purple portal with scrolling scanlines and a grey dithered rim; 3 animation frames.
    static func portal(_ frame: Int) -> SKTexture {
        let w = 16, h = 28
        var rows: [String] = []
        for y in 0..<h {
            var row = ""
            for x in 0..<w {
                let nx = (CGFloat(x) + 0.5 - CGFloat(w) / 2) / (CGFloat(w) / 2)
                let ny = (CGFloat(y) + 0.5 - CGFloat(h) / 2) / (CGFloat(h) / 2)
                let d = nx * nx + ny * ny
                if d > 1 { row += "."; continue }
                if d > 0.72 { row += (x + y) % 2 == 0 ? "l" : "g"; continue }
                if d > 0.6 { row += "k"; continue }
                if (y + frame) % 3 == 0 { row += "m"; continue }
                row += abs(nx) < 0.18 && (y + frame * 2) % 5 == 0 ? "c" : (d < 0.2 ? "p" : "v")
            }
            rows.append(row)
        }
        return Tex.pixels("portal\(frame)", rows)
    }
}

extension GameScene {
    static let scoreLimit = 10
    static let botNames = ["BLU", "GRN", "YLW", "PRP", "RED"]
    static let botColors: [UInt32] = [0x3A7BF0, 0x3CC05A, 0xF0C83A, 0xA05AE6, 0xE6463C]

    var difficulty: Difficulty { app?.settings.difficulty ?? .normal }

    /// Makes the fighter list match the menu's bot count (player is always id 0).
    func configureFighters() {
        let want = (botOverride ?? app?.settings.bots ?? 3) + 1
        while fighters.count > want {
            let f = fighters.removeLast()
            f.node.removeFromParent(); portals.removeLast().removeFromParent()
            brains.removeAll { $0.f === f }
        }
        while fighters.count < want {
            let i = fighters.count
            let c = RGBA(hex: GameScene.botColors[(i - 1) % 5]).sk
            let f = Fighter(id: i, name: GameScene.botNames[(i - 1) % 5], color: c, isPlayer: false)
            f.rig.setWeapon(0)
            f.node.isHidden = true
            world.addChild(f.node)
            fighters.append(f)
            brains.append(Brain(f))
        }
        while portals.count < fighters.count {
            let p = SKSpriteNode(texture: Art.portal(0), size: CGSize(width: 32, height: 56))
            p.anchorPoint = CGPoint(x: 0.5, y: 0.08)
            p.zPosition = 18; p.isHidden = true
            world.addChild(p); portals.append(p)
        }
    }

    func newMatch() {
        configureFighters()
        matchOver = false
        hud.showBanner(nil)
        hud.clearFeed()
        for p in pickups { p.node.removeFromParent() }
        pickups.removeAll()
        pickupAt = simTime + 8
        for f in fighters {
            f.kills = 0; f.deaths = 0
            f.alive = false
            f.node.isHidden = true
            f.respawnAt = simTime + (f.isPlayer ? 0.3 : 0.5 + Double(f.id) * 0.25)
            f.spawnPoint = nil
        }
    }

    func kill(_ f: Fighter, by killer: Int) {
        guard f.alive else { return }
        f.alive = false
        f.deaths += 1
        f.respawnAt = simTime + 2.2
        f.spawnPoint = nil
        f.grounded = false
        // the body goes limp and flies with the hit
        let v = CGVector(dx: f.vel.x * 0.7 + f.hitDirX * 260, dy: max(f.vel.y * 0.6, 0) + 260)
        ragdolls.spawn(f.rig.bones(in: physicsRoot), front: f.rig.colors.0, back: f.rig.colors.1, vel: v,
                       spin: -f.hitDirX * rng.range(4, 9), world: physicsWorld, time: simTime)
        f.node.isHidden = true
        let k: Fighter? = killer >= 0 && killer < fighters.count ? fighters[killer] : nil
        if let k, k !== f { k.kills += 1 } else { f.kills = max(0, f.kills - 1) }
        hud.addKill(killer: k, victim: f, weapon: k?.weapons.current ?? 0, time: simTime)
        particles.burst(f.center, n: 22, speed: 320, life: 0.7, color: f.color, size: 3)
        Audio.shared.play(k?.isPlayer == true ? .kill : .death, volume: 0.7, pan: pan(f.pos))
        let playerInvolved = f.isPlayer || k?.isPlayer == true
        shake(playerInvolved ? 7 : 3)
        hitStop(playerInvolved ? 0.06 : 0.02)
        let final = k.map { $0 !== f && $0.kills >= GameScene.scoreLimit } ?? false
        // demo reels: the follow-cam star scores or dies
        if demo && finaleAt == nil {
            if f.id == director.star { starKilled(f, by: k) }
            else if let k, k.id == director.star, k !== f { starScored(f) }
            return
        }
        // slow-motion shots on the moments that matter
        if final {
            cinema.slowMo(2.2, scale: 0.18, at: f.center, zoom: 1.45, force: true)
            cinema.impactFlash(0.5)
        } else if k?.isPlayer == true && k !== f {
            cinema.slowMo(0.8, scale: 0.3, at: f.center, zoom: 1.28)
            cinema.impactFlash(0.3)
            hud.markKill()
            if simTime - streakAt < 3.5 { streak += 1 } else { streak = 1 }
            streakAt = simTime
            hud.callout(["KILL", "DOUBLE KILL", "TRIPLE KILL", "QUAD KILL", "RAMPAGE"][min(streak - 1, 4)], color: player.color)
        } else if f.isPlayer {
            cinema.slowMo(1.0, scale: 0.3, at: f.center, zoom: 1.25)
            streak = 0
        }
        if final, !matchOver {
            matchOver = true
            matchOverAt = simTime
            bannerLeft = 4
            showWinner(4)
            Audio.shared.play(.win, volume: 0.8)
        }
    }

    func updateMatch(_ dt: Double) {
        let fdt = CGFloat(dt)
        for (i, f) in fighters.enumerated() {
            let portal = portals[i]
            if f.alive {
                // invulnerability blink, falling far off-screen kills
                f.node.alpha = simTime < f.invulnUntil ? (Int(simTime * 16) % 2 == 0 ? 0.35 : 1) : 1
                if f.pos.y < -150 || f.pos.y > size.height * 3 { kill(f, by: f.lastHitBy) }
                if !portal.isHidden {
                    portal.setScale(max(0.01, portal.xScale - fdt * 2.5))
                    if portal.xScale <= 0.05 { portal.isHidden = true }
                }
                continue
            }
            // portal opens 0.6 s before the respawn
            if demo && finaleAt != nil { continue }   // nobody comes back during the finale
            if simTime >= f.respawnAt - 0.6, !extracting {
                if f.spawnPoint == nil {
                    f.spawnPoint = spawnPoint(inStage: demo && stage != nil && (f.isPlayer || rng.chance(0.6)))
                    portal.position = f.spawnPoint!
                    portal.isHidden = false
                    portal.setScale(0.1)
                    Audio.shared.play(.portal, volume: 0.35, pan: pan(f.spawnPoint!))
                }
                portal.setScale(min(1, portal.xScale + fdt * 3))
                portal.texture = Art.portalFrames[Int(simTime * 12) % 3]
            }
            if simTime >= f.respawnAt, !extracting, !matchOver || f.spawnPoint != nil {
                spawn(f, at: f.spawnPoint ?? spawnPoint())
                f.invulnUntil = simTime + 2
            }
        }
        if !portals.isEmpty { for (i, p) in portals.enumerated() where fighters[i].alive && !p.isHidden { p.texture = Art.portalFrames[Int(simTime * 12) % 3] } }

        // health and armour pickups
        if simTime >= pickupAt && pickups.count < 3 && !extracting && level.solidCount > 0 {
            pickupAt = simTime + 10
            let armors = pickups.filter { $0.kind == .armor }.count
            let kind: PickupKind = armors == 0 && rng.chance(0.5) ? .armor : .health
            let p = spawnPoint() + CGPoint(x: 0, y: 14)
            let svg = kind == .armor ? GunArts.armorPickup : GunArts.medkit
            let n = SKSpriteNode(texture: svg.texture(kind == .armor ? "pk-armor" : "pk-med"), size: svg.size)
            n.position = p; n.zPosition = 15
            world.addChild(n)
            pickups.append(Pickup(kind: kind, pos: p, node: n, born: simTime))
        }
        var k = 0
        while k < pickups.count {
            let pk = pickups[k]
            pk.node.position = CGPoint(x: pk.pos.x, y: (pk.pos.y + 3 * sin(CGFloat(simTime - pk.born) * 3)).rounded())
            var taken = false
            for f in fighters where f.alive && f.bodyRect.insetBy(dx: -8, dy: -4).contains(pk.pos) {
                switch pk.kind {
                case .health:
                    guard f.hp < 100 else { continue }
                    f.hp = min(100, f.hp + 40)
                    particles.burst(pk.pos, n: 12, speed: 160, life: 0.5, color: SKColor(srgbRed: 0.4, green: 1, blue: 0.5, alpha: 1), size: 2, gravity: -100)
                case .armor:
                    guard f.armor < 100 else { continue }
                    f.armor = min(100, f.armor + 75)
                    particles.burst(pk.pos, n: 14, speed: 180, life: 0.5, color: SKColor(srgbRed: 0.4, green: 0.8, blue: 1, alpha: 1), size: 2, gravity: -100)
                    Audio.shared.play(.clank, volume: 0.45, pan: pan(pk.pos))
                }
                if f.isPlayer { hud.callout(pk.kind == .armor ? "ARMOR" : "+40 HP", color: pk.kind == .armor ? .cyan : .green) }
                taken = true
                Audio.shared.play(.pickup, volume: 0.6, pan: pan(pk.pos))
                break
            }
            if taken { pk.node.removeFromParent(); pickups.remove(at: k) } else { k += 1 }
        }

        if matchOver {
            let left = max(0, Int((4 - (simTime - matchOverAt)).rounded(.up)))
            if simTime - matchOverAt > 4 { if !(demo && finaleAt != nil) { newMatch() } } else if left != bannerLeft { bannerLeft = left; showWinner(left) }
        }
        updateNav()
    }

    private func showWinner(_ left: Int) {
        guard let w = fighters.max(by: { $0.kills < $1.kills }) else { return }
        hud.showBanner(w.isPlayer ? "YOU WIN" : "\(w.name) WINS", color: w.color.blended(withFraction: 0.2, of: .white) ?? w.color,
                       sub: "NEW MATCH IN \(left)")
    }

    func nearestPickup(to p: CGPoint, _ kind: PickupKind = .health) -> CGPoint? {
        var best: CGPoint?, bd = CGFloat.infinity
        for pk in pickups where pk.kind == kind { let d = pk.pos.dist(p); if d < bd { bd = d; best = pk.pos } }
        return best
    }

    /// A ledge far from `enemy`, preferably behind a big element, and not too far from `f`.
    func coverNode(for f: Fighter, from enemy: Fighter) -> Int {
        var best = -1, bestScore = CGFloat.infinity
        for _ in 0..<24 {
            guard !nav.nodes.isEmpty else { break }
            let i = rng.int(nav.nodes.count)
            let n = nav.nodes[i]
            let c = CGPoint(x: (n.x0 + n.x1) / 2, y: n.y + 30)
            let de = c.dist(enemy.center)
            guard de > 300 else { continue }
            var score = c.dist(f.pos) - de * 0.5
            if let h = level.raycast(enemy.center, c, accept: { level.elements[$0].isBig }), h.t < 0.95 { score -= 300 }
            if score < bestScore { bestScore = score; best = i }
        }
        return best
    }

    /// Rebuilds the nav graph off the main thread when the level changed, at most every 0.5 s.
    func updateNav() {
        guard !navBuilding, level.version != navVersion, simTime >= navAt, !extracting else { return }
        navBuilding = true
        let v = level.version, tops = NavGraph.tops(level), sz = size
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let g = NavGraph.build(tops: tops, size: sz)
            DispatchQueue.main.async {
                guard let self else { return }
                self.nav = g
                self.navVersion = v
                self.navBuilding = false
                self.navAt = self.simTime + 0.5
                for b in self.brains { b.forceReplan() }
            }
        }
    }
}

extension GameScene {
    func damageNumber(_ n: Int, at p: CGPoint) {
        let t = PixelFont.texture("\(n)")
        guard let s = fx.spawn(t, at: p + CGPoint(x: rng.range(-8, 8), y: 0), size: CGSize(width: t.size().width * 2, height: t.size().height * 2),
                               color: SKColor(srgbRed: 1, green: 0.9, blue: 0.3, alpha: 1), life: 0.7, z: 50) else { return }
        s.colorBlendFactor = 1
        fx.setVelocity(s, CGPoint(x: rng.range(-20, 20), y: 70))
    }

}
