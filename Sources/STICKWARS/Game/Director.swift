import SpriteKit

/// Demo-reel director, follow-cam style: the camera stays locked on one fighter (the "star").
/// When the star is killed, the kill plays in slow-mo and the camera hands over to the killer.
/// It opens on the player's portal and ends with a finale by whoever is the star at the time.
struct DirectorState {
    var start = 0.0
    var star = 0                 // fighter id the camera follows
    var pendingStar: Int?        // killer taking over after the kill beat
    var switchAt = 0.0
    var lastPos = CGPoint.zero   // where the star was (to hold on its death)
    var fired = false            // finale orb fired
    var streak = 0, streakAt = -10.0
}

extension GameScene {
    var starFighter: Fighter { fighters[min(director.star, fighters.count - 1)] }

    func startDirector() {
        director = DirectorState(start: simTime)
        finaleAt = nil; finaleCollapsedAt = nil
        cinema.blackout.alpha = 0
        cinema.filmBars = 38
        hud.cinematic = true
        // the player drops in first; the others portal in one by one a moment later
        for f in fighters {
            f.alive = false; f.node.isHidden = true; f.spawnPoint = nil
            f.respawnAt = simTime + (f.isPlayer ? 0.35 : 2.6 + Double(f.id) * 0.35)
        }
        // everyone fights with style: flips, wall jumps, sharp aim
        for b in brains {
            b.scripted = false
            b.stylish = true
            b.skillOverride = BotSkill(aimErr: 0.04, reaction: 0.14, burst: 0.9, pause: 0.25, grenadeChance: 0.008)
            b.holdUntil = b.f.isPlayer ? simTime + 2.3 : 0
        }
    }

    /// Called from kill(): the star died, hand the camera to its killer after the kill beat.
    func starKilled(_ f: Fighter, by k: Fighter?) {
        director.lastPos = f.center
        director.pendingStar = (k != nil && k !== f) ? k!.id : nil
        director.switchAt = simTime + 0.35
        cinema.slowMo(1.1, scale: 0.25, at: f.center, zoom: 1.5, force: true)
        cinema.impactFlash(0.3)
    }

    /// Called from kill(): the star got a kill.
    func starScored(_ victim: Fighter) {
        if simTime - director.streakAt < 3.5 { director.streak += 1 } else { director.streak = 1 }
        director.streakAt = simTime
        hud.callout(["KILL", "DOUBLE KILL", "TRIPLE KILL", "QUAD KILL", "RAMPAGE"][min(director.streak - 1, 4)], color: starFighter.color)
        cinema.slowMo(0.7, scale: 0.3, at: victim.center, zoom: 1.5)
    }

    private func nearestAlive(to p: CGPoint) -> Fighter? {
        fighters.filter { $0.alive }.min { $0.center.dist(p) < $1.center.dist(p) }
    }

    // MARK: finale

    /// Respawns stop; the star flips up and fires one oversized black hole into the others. Its
    /// collapse kills everyone left, the camera stays on the last one standing, and the reel fades.
    func startFinale() {
        if !starFighter.alive {
            if let a = nearestAlive(to: director.lastPos) { director.star = a.id }
            else { spawn(starFighter, at: spawnPoint()) }
        }
        finaleAt = simTime
        finaleCollapsedAt = nil
        director.fired = false
        director.pendingStar = nil
        if let b = brains.first(where: { $0.f === starFighter }) { b.scripted = true }
        starFighter.input = FighterInput()
        starFighter.input.switchTo = 7
        starFighter.invulnUntil = 0
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
        let others = fighters.filter { $0.alive && $0.id != director.star }
        guard !others.isEmpty else { return starFighter.center + CGPoint(x: starFighter.facing * 250, y: 0) }
        return others.reduce(CGPoint.zero) { $0 + $1.center } * (1 / CGFloat(others.count))
    }

    private func directFinale(_ fa: Double) {
        let t = simTime - fa
        let hero = starFighter
        let target = finaleTarget
        var inp = FighterInput()
        inp.aim = target
        hero.facing = target.x >= hero.pos.x ? 1 : -1
        if t > 0.2 && t < 0.25 { inp.jumpPressed = true }
        inp.jumpHeld = t < 0.6
        if t > 0.42 && t < 0.47 && hero.airJumps > 0 { inp.jumpPressed = true } // front flip at the top
        hero.input = inp
        if t > 0.7 && !director.fired {
            director.fired = true
            let dir = (target - hero.muzzle).normalized
            spawnProjectile(.blackhole, at: hero.muzzle, vel: dir * 650, owner: hero.id)
            projectiles[projectiles.count - 1].power = 2.3
            Audio.shared.play(.blackhole, volume: 1, pan: pan(hero.muzzle))
            shake(6)
        }
        if let c = finaleCollapsedAt, simTime - c > 0.12 {
            cinema.baseZoom = 1.55; cinema.baseFocus = hero.center + CGPoint(x: 0, y: 10)
        } else {
            cinema.baseZoom = 1.2; cinema.baseFocus = (hero.center + target) * 0.5
        }
    }

    // MARK: per frame

    func direct() {
        guard demo else { return }
        if let fa = finaleAt { directFinale(fa); return }
        let t = simTime - director.start
        // hand over to the killer after the kill beat (or the nearest fighter if there's none)
        if let next = director.pendingStar ?? (starFighter.alive ? nil : -1), simTime >= director.switchAt {
            if next >= 0, next < fighters.count, fighters[next].alive { director.star = next }
            else if let a = nearestAlive(to: director.lastPos) { director.star = a.id }
            director.pendingStar = nil
        }
        let s = starFighter
        if s.alive { director.lastPos = s.center }
        // opening: tight on the player's portal, then settle into the follow-cam
        if t < 2.4 {
            let p = s.alive ? s.center : (s.spawnPoint ?? s.center) + CGPoint(x: 0, y: 30)
            cinema.baseZoom = t < 1.6 ? 1.7 : 1.5
            cinema.baseFocus = p
            return
        }
        // follow-cam: always on the star, leading a little toward where it's aiming / moving
        let look = s.alive ? (s.input.aim - s.center).normalized * 55 : .zero
        let lead = s.alive ? CGPoint(x: s.vel.x * 0.12, y: s.vel.y * 0.05) : .zero
        let near = fighters.filter { $0.alive && $0.id != s.id }.map { $0.center.dist(director.lastPos) }.min() ?? 999
        cinema.baseZoom = near < 220 ? 1.55 : 1.4
        cinema.baseFocus = director.lastPos + look + lead
    }
}
