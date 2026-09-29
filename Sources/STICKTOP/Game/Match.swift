import SpriteKit

extension GameScene {
    func kill(_ f: Fighter, by killer: Int) {
        guard f.alive else { return }
        f.alive = false
        f.deaths += 1
        f.respawnAt = simTime + 2
        f.rig.spin = rng.range(6, 12) * (f.vel.x >= 0 ? -1 : 1)
        f.vel.y = max(f.vel.y, 350)
        if killer >= 0 && killer != f.id { fighters[killer].kills += 1 }
        particles.burst(f.center, n: 24, speed: 320, life: 0.7, color: f.color, size: 3)
        Audio.shared.play(.death, volume: 0.6, pan: pan(f.pos))
        shake(5)
    }

    func updateMatch(_ dt: Double) {
        for f in fighters where !f.alive {
            // ragdoll-ish tumble: keep flying under gravity, then fade
            f.vel.y -= 2200 * CGFloat(dt)
            f.pos = f.pos + f.vel * CGFloat(dt)
            if f.pos.y < 0 { f.pos.y = 0; f.vel.y = -f.vel.y * 0.3; f.vel.x *= 0.6; f.rig.spin *= 0.5 }
            f.node.alpha = CGFloat(clamp((f.respawnAt - simTime) / 1.2, 0, 1))
            if simTime >= f.respawnAt {
                spawn(f)
                f.invulnUntil = simTime + 2
            }
        }
    }

    func damageNumber(_ n: Int, at p: CGPoint) {
        guard let s = fx.spawn(PixelFont.texture("\(n)"), at: p + CGPoint(x: rng.range(-8, 8), y: 0), size: .zero, life: 0.6, z: 50) else { return }
        let t = PixelFont.texture("\(n)")
        s.size = CGSize(width: t.size().width * 2, height: t.size().height * 2)
        s.color = SKColor(srgbRed: 1, green: 0.9, blue: 0.3, alpha: 1)
        s.colorBlendFactor = 1
    }

    func updateHUD(_ dt: Double) {}
}
