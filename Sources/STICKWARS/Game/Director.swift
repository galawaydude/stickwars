import SpriteKit

/// Demo-reel director: picks camera shots around the hero (wide, tracking, close-up when enemies
/// are near), with an opening close-up on the hero's portal. Only runs when `demo` is on.
struct DirectorState {
    var start = 0.0
    var shotUntil = 0.0
    var shot = 0            // 0 wide, 1 tracking, 2 close
    var lastHeroKills = 0
}

extension GameScene {
    func startDirector() {
        director = DirectorState(start: simTime)
        finaleAt = nil; finaleCollapsedAt = nil
        cinema.blackout.alpha = 0
        for b in brains { b.scripted = false }
        cinema.filmBars = 38
        hud.cinematic = true
        // the hero drops in first; the bots portal in one by one a moment later
        for f in fighters {
            f.alive = false; f.node.isHidden = true; f.spawnPoint = nil
            f.respawnAt = simTime + (f.isPlayer ? 0.35 : 2.6 + Double(f.id) * 0.35)
        }
        if let b = brains.first(where: { $0.f === player }) {
            b.holdUntil = simTime + 2.3
            b.stylish = true
            b.skillOverride = BotSkill(aimErr: 0.02, reaction: 0.08, burst: 1.1, pause: 0.18, grenadeChance: 0.012)
        }
    }

    /// Finale: respawns stop, the hero flips up and fires one last giant black hole into the bots;
    /// it drags them all in and its collapse kills everyone left.
    func startFinale() {
        finaleAt = simTime
        finaleCollapsedAt = nil
        if let b = brains.first(where: { $0.f === player }) { b.scripted = true }
        player.input = FighterInput()
        player.input.switchTo = 7
        player.invulnUntil = 0
    }

    func finaleCollapse(at p: CGPoint, owner: Int) {
        finaleCollapsedAt = simTime
        cinema.slowMo(2.8, scale: 0.2, at: p, zoom: 1.15, force: true)
        for f in fighters where f.alive && f.id != owner {
            let out = (f.center - p).normalized
            f.vel = CGPoint(x: out.x * 1100, y: max(out.y, 0.3) * 900 + 300)
            f.hitDirX = out.x >= 0 ? 1 : -1
            kill(f, by: owner)
        }
    }

    private var finaleTarget: CGPoint {
        let bots = fighters.filter { $0.alive && !$0.isPlayer }
        guard !bots.isEmpty else { return player.center + CGPoint(x: player.facing * 250, y: 0) }
        return bots.reduce(CGPoint.zero) { $0 + $1.center } * (1 / CGFloat(bots.count))
    }

    private func directFinale(_ fa: Double) {
        let t = simTime - fa
        let hero = player!
        let target = finaleTarget
        var inp = FighterInput()
        inp.aim = target
        hero.facing = target.x >= hero.pos.x ? 1 : -1
        if t > 0.2 && t < 0.25 { inp.jumpPressed = true }
        inp.jumpHeld = t < 0.6
        if t > 0.42 && t < 0.47 && hero.airJumps > 0 { inp.jumpPressed = true } // front flip at the top
        hero.input = inp
        if director.lastHeroKills >= 0 && t > 0.7 && director.shot != 99 {
            // fire the finale orb once, from the top of the flip
            director.shot = 99
            let dir = (target - hero.muzzle).normalized
            spawnProjectile(.blackhole, at: hero.muzzle, vel: dir * 650, owner: hero.id)
            projectiles[projectiles.count - 1].power = 2.3
            Audio.shared.play(.blackhole, volume: 1, pan: pan(hero.muzzle))
            shake(6)
        }
        // camera: wide on the fight, then settle on the lone hero
        if let c = finaleCollapsedAt, simTime - c > 0.12 {
            cinema.baseZoom = 1.55; cinema.baseFocus = hero.center + CGPoint(x: 0, y: 10)
        } else {
            cinema.baseZoom = 1.12; cinema.baseFocus = (hero.center + target) * 0.5
        }
    }

    func direct() {
        guard demo, let hero = player else { return }
        if let fa = finaleAt { directFinale(fa); return }
        let t = simTime - director.start
        let enemies = fighters.filter { $0.alive && !$0.isPlayer }
        let nearest = enemies.min { $0.center.dist(hero.center) < $1.center.dist(hero.center) }
        // opening: tight on the hero's portal, then pull out as the bots arrive
        if t < 2.4 {
            let p = hero.alive ? hero.center : (hero.spawnPoint ?? hero.center) + CGPoint(x: 0, y: 30)
            cinema.baseZoom = t < 1.6 ? 1.7 : 1.35
            cinema.baseFocus = p
            return
        }
        if simTime >= director.shotUntil {
            let close = nearest.map { $0.center.dist(hero.center) < 260 } ?? false
            director.shot = close && rng.chance(0.6) ? 2 : (director.shot == 0 ? 1 : (rng.chance(0.5) ? 0 : 1))
            director.shotUntil = simTime + Double(rng.range(2.8, 4.6))
        }
        let look = hero.alive ? (hero.input.aim - hero.center).normalized * 60 : .zero
        let heroP = (hero.alive ? hero.center : (hero.spawnPoint ?? hero.center)) + look + CGPoint(x: hero.vel.x * 0.12, y: 0)
        switch director.shot {
        case 0:
            cinema.baseZoom = 1.08
            let anchor = stage.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: size.width / 2, y: size.height / 2)
            cinema.baseFocus = (heroP + anchor) * 0.5
        case 2:
            let mid = nearest.map { (heroP + $0.center) * 0.5 } ?? heroP
            cinema.baseZoom = 1.5
            cinema.baseFocus = mid
        default:
            cinema.baseZoom = 1.28
            cinema.baseFocus = heroP
        }
    }
}
