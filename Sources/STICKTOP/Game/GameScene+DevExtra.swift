import SpriteKit

extension GameScene {
    func extraState() -> String {
        var vmax: CGFloat = 0, wmax: CGFloat = 0, slow = 0
        for p in debris.pieces { if let b = p.node.physicsBody {
            let v = hypot(b.velocity.dx, b.velocity.dy); vmax = max(vmax, v); wmax = max(wmax, abs(b.angularVelocity)); if v < 2 { slow += 1 } } }
        return String(format: "debris vmax=%.2f wmax=%.2f slow=%d\n", vmax, wmax, slow) + String(format: "debris live=%d awake=%d spawned=%d platforms=%d particles=%d fx=%d projectiles=%d staticBodies=%d",
               debris.liveCount, debris.awakeCount, debris.spawnedTotal, platforms.count, particles.count, fx.count, projectiles.count,
               statics.root.children.count)
    }

    func devCommandExtra(_ cmd: String, _ a: [String]) -> String? {
        func n(_ i: Int) -> CGFloat { i < a.count ? CGFloat(Double(a[i]) ?? 0) : 0 }
        switch cmd {
        case "blast":
            let t0 = now()
            explode(at: CGPoint(x: n(0), y: n(1)), radius: a.count > 2 ? n(2) : 70, damage: 60, owner: -1)
            let t1 = now()
            canvas?.flush()
            return String(format: "blast %.2f ms (+flush %.2f ms)", (t1 - t0) * 1000, (now() - t1) * 1000)
        case "shoot":
            let from = CGPoint(x: n(0), y: n(1)), to = CGPoint(x: n(2), y: n(3))
            let dir = (to - from).normalized
            let def = player.weapons.def
            switch def.kind {
            case .hitscan, .charge:
                for _ in 0..<def.pellets {
                    let ang = atan2(dir.y, dir.x) + rng.range(-def.spread, def.spread)
                    shoot(from: from, dir: CGPoint(x: cos(ang), y: sin(ang)), def: def, owner: -1, damage: def.damage, power: def.power,
                          carve: def.carve, width: def.tracerWidth)
                }
            case .laser: laser(from: from, dir: dir, def: def, owner: -1)
            case .rocket: spawnProjectile(.rocket, at: from, vel: dir * def.speed, owner: -1)
            case .plasma: spawnProjectile(.plasma, at: from, vel: dir * def.speed, owner: -1, bounces: 3)
            }
            return "shot \(def.name)"
        case "bots":
            var out = "nav nodes=\(nav.nodes.count) edges=\(nav.edges.reduce(0) { $0 + $1.count })\n"
            for b in brains { out += b.debug(self) + "\n" }
            return out
        case "grenade":
            spawnProjectile(.grenade, at: CGPoint(x: n(0), y: n(1)), vel: CGPoint(x: n(2), y: n(3)), owner: -1, fuse: 1.5)
            return "grenade"
        case "give":
            let names = Weapons.all.map { $0.name.lowercased() }
            let i = Int(a.first ?? "") .map { $0 - 1 } ?? names.firstIndex(of: (a.first ?? "").lowercased()) ?? 0
            player.weapons.current = clamp(i, 0, Weapons.all.count - 1)
            player.rig.setWeapon(player.weapons.current)
            return "weapon \(player.weapons.def.name)"
        default: return nil
        }
    }

    func extraOverlay(_ ctx: CGContext) {
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.6, blue: 0.9, alpha: 1))
        for p in debris.pieces { ctx.stroke(p.node.frame) }
    }
}
