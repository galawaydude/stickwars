import SpriteKit

enum PhysCat {
    static let debris: UInt32 = 1 << 0
    static let statics: UInt32 = 1 << 1
    static let edge: UInt32 = 1 << 2
}

/// Rigid-body debris: pieces of the snapshot flying and piling with SpriteKit physics.
/// Capped at ~350 live pieces; the oldest and long-resting ones fade out.
final class DebrisSystem {
    final class Piece {
        let node: SKSpriteNode
        let born: Double
        var restSince = 0.0
        var slowTime: CGFloat = 0
        var frozen = false
        var fade: CGFloat = 0          // > 0 = fading, per-second rate
        let big: Bool
        init(node: SKSpriteNode, born: Double, big: Bool) { self.node = node; self.born = born; self.big = big }
    }

    let root = SKNode()
    private(set) var pieces: [Piece] = []
    let cap = 350
    private(set) var spawnedTotal = 0

    /// Spawns a piece textured with `image` covering scene rect `r`. `poly` (scene coords, convex)
    /// gives a polygon body, otherwise a rectangle.
    @discardableResult
    func spawn(_ image: CGImage, rect r: CGRect, poly: [CGPoint]? = nil, vel: CGVector, spin: CGFloat, time: Double) -> SKSpriteNode? {
        guard r.width >= 1.5, r.height >= 1.5 else { return nil }
        let tex = SKTexture(cgImage: image)
        tex.filteringMode = .linear
        let n = SKSpriteNode(texture: tex, size: r.size)
        n.position = r.center
        n.zPosition = 5
        var body: SKPhysicsBody?
        if let poly, poly.count >= 3, Fracture.isConvex(poly) {
            let path = CGMutablePath()
            let c = r.center
            var pts = poly.map { CGPoint(x: $0.x - c.x, y: $0.y - c.y) }
            if Fracture.area(pts) < 0 { pts.reverse() }
            path.addLines(between: pts); path.closeSubpath()
            body = SKPhysicsBody(polygonFrom: path)
        }
        let b = body ?? SKPhysicsBody(rectangleOf: CGSize(width: max(2, r.width - 0.5), height: max(2, r.height - 0.5)))
        b.categoryBitMask = PhysCat.debris
        b.collisionBitMask = PhysCat.debris | PhysCat.statics | PhysCat.edge
        b.contactTestBitMask = 0
        b.friction = 0.6
        b.restitution = 0.2
        b.linearDamping = 0.15
        b.angularDamping = 0.5
        // bigger pieces are denser so small letters don't shove slabs around
        b.density = 0.8 + min(2.2, r.width * r.height / 2000)
        n.physicsBody = b
        root.addChild(n)
        b.velocity = vel
        b.angularVelocity = spin
        pieces.append(Piece(node: n, born: time, big: r.width >= 14 || r.height >= 14))
        spawnedTotal += 1
        if pieces.count > cap {
            // fade the oldest non-fading pieces fast
            var over = pieces.count - cap
            for p in pieces where over > 0 && p.fade == 0 { p.fade = 4; over -= 1 }
        }
        return n
    }

    func update(time: Double, dt: CGFloat) {
        var i = 0
        while i < pieces.count {
            let p = pieces[i]
            let n = p.node
            if p.fade > 0 {
                n.alpha -= p.fade * dt
                if n.alpha <= 0 { n.removeFromParent(); pieces.swapAt(i, pieces.count - 1); pieces.removeLast(); continue }
            } else if let b = n.physicsBody {
                // Box2D rarely sleeps small stacked pieces, so near-still pieces are frozen
                // (made static) and woken again when disturbed or their support disappears.
                if !p.frozen {
                    let v = b.velocity
                    if v.dx * v.dx + v.dy * v.dy < 64 && abs(b.angularVelocity) < 0.5 { p.slowTime += dt } else { p.slowTime = 0 }
                    if p.slowTime > 0.4 { b.isDynamic = false; p.frozen = true; p.restSince = time }
                } else if time - p.restSince > 20 { p.fade = 1 }
                if n.position.y < -200 { p.fade = 10 }
            }
            i += 1
        }
    }

    var liveCount: Int { pieces.count }
    var awakeCount: Int { pieces.reduce(0) { $0 + ($1.frozen ? 0 : 1) } }

    private func wake(_ p: Piece) {
        guard p.frozen, let b = p.node.physicsBody else { return }
        p.frozen = false; p.slowTime = 0
        b.isDynamic = true
    }

    /// Wakes frozen pieces touching r, and (transitively) the ones resting on them.
    func wake(near r: CGRect) {
        var queue = [r]
        var guardN = 0
        while let q = queue.popLast(), guardN < 400 {
            guardN += 1
            let qq = q.insetBy(dx: -1, dy: -3)
            for p in pieces where p.frozen && p.fade == 0 && p.node.frame.intersects(qq) {
                wake(p); queue.append(p.node.frame)
            }
        }
    }

    /// Wakes the piece owning `body` (before applying a hit to it).
    func wake(body: SKPhysicsBody) {
        for p in pieces where p.node.physicsBody === body { wake(p); wake(near: p.node.frame); return }
    }

    /// Tops of large resting pieces, usable as one-way platforms by fighters.
    func collectPlatforms(into out: inout [CGRect]) {
        out.removeAll(keepingCapacity: true)
        for p in pieces where p.big && p.fade == 0 && p.frozen {
            let f = p.node.frame
            if f.width >= 12 { out.append(f) }
        }
    }

    /// Fighters running through pieces nudge them.
    func nudge(_ body: CGRect, vx: CGFloat) {
        guard abs(vx) > 60 else { return }
        let c = body.center
        for p in pieces where p.fade == 0 {
            let pos = p.node.position
            if abs(pos.x - c.x) > 60 || abs(pos.y - c.y) > 60 { continue }
            let f = p.node.frame
            guard f.intersects(body), body.minY < f.maxY - 3, let b = p.node.physicsBody else { continue }
            if p.frozen { wake(p); wake(near: f) }
            b.velocity = CGVector(dx: b.velocity.dx + (vx * 0.8 - b.velocity.dx) * 0.25, dy: max(b.velocity.dy, 60))
        }
    }

    /// Pushes pieces away from an explosion.
    func blast(_ c: CGPoint, radius: CGFloat, speed: CGFloat) {
        for p in pieces {
            let d = p.node.position - c
            let l = d.length
            guard l < radius * 1.6, let b = p.node.physicsBody else { continue }
            wake(p)
            let k = (1 - l / (radius * 1.6)) * speed
            let n = d.normalized
            b.velocity = CGVector(dx: b.velocity.dx + n.x * k, dy: b.velocity.dy + n.y * k + k * 0.3)
            b.angularVelocity += rng.range(-8, 8)
        }
    }

    func clear() {
        for p in pieces { p.node.removeFromParent() }
        pieces.removeAll()
    }
}

/// Static rectangle bodies mirroring the solid elements, so debris lands on remaining text and ledges.
final class StaticBodies {
    let root = SKNode()
    private var nodes: [SKNode?] = []

    func sync(_ level: Level) {
        if !level.removed.isEmpty {
            for i in level.removed where i < nodes.count { nodes[i]?.removeFromParent(); nodes[i] = nil }
            level.removed.removeAll(keepingCapacity: true)
        }
        if !level.added.isEmpty {
            if nodes.count < level.elements.count { nodes.append(contentsOf: [SKNode?](repeating: nil, count: level.elements.count - nodes.count)) }
            for i in level.added {
                let e = level.elements[i]
                guard e.state == .solid, nodes[i] == nil else { continue }
                let n = SKNode()
                n.position = e.rect.center
                let b = SKPhysicsBody(rectangleOf: CGSize(width: max(1, e.rect.width), height: max(1, e.rect.height)))
                b.isDynamic = false
                b.categoryBitMask = PhysCat.statics
                b.collisionBitMask = 0
                b.friction = 0.7
                b.restitution = 0.1
                n.physicsBody = b
                root.addChild(n)
                nodes[i] = n
            }
            level.added.removeAll(keepingCapacity: true)
        }
    }

    func clear() {
        root.removeAllChildren()
        nodes.removeAll()
    }
}
