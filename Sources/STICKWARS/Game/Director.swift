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

    func direct() {
        guard demo, let hero = player else { return }
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
