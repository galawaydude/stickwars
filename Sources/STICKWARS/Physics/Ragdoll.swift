import SpriteKit

/// Limp physics bodies pinned at the joints: a dead stick figure flies, tumbles and piles up
/// with the debris instead of playing a canned animation.
final class Ragdolls {
    private final class Doll {
        var nodes: [SKSpriteNode] = []
        var joints: [SKPhysicsJoint] = []
        let born: Double
        init(born: Double) { self.born = born }
    }
    let root = SKNode()
    private var dolls: [Doll] = []

    /// bones: torso, head, thighF, shinF, thighB, shinB, upperF, foreF, upperB, foreB (see Rig.bones).
    func spawn(_ bones: [BoneShot], front: SKColor, back: SKColor, vel: CGVector, spin: CGFloat, world: SKPhysicsWorld, time: Double) {
        guard bones.count == 10 else { return }
        if dolls.count >= 6 { remove(dolls.removeFirst(), world) }
        let d = Doll(born: time)
        var bodies: [SKPhysicsBody] = []
        for (i, b) in bones.enumerated() {
            let n: SKSpriteNode
            let body: SKPhysicsBody
            if b.head {
                n = SKSpriteNode(texture: Tex.circle, size: CGSize(width: Rig.headR * 2, height: Rig.headR * 2))
                n.position = b.a
                body = SKPhysicsBody(circleOfRadius: Rig.headR)
            } else {
                let v = b.b - b.a
                let len = max(2, v.length)
                n = SKSpriteNode(texture: Rig.capsule(len.rounded()), size: CGSize(width: len + Rig.thick, height: Rig.thick))
                n.position = CGPoint(x: (b.a.x + b.b.x) / 2, y: (b.a.y + b.b.y) / 2)
                n.zRotation = atan2(v.y, v.x)
                body = SKPhysicsBody(rectangleOf: CGSize(width: len + Rig.thick * 0.5, height: Rig.thick * 0.9))
            }
            n.color = b.backLayer ? back : front
            n.colorBlendFactor = 1
            n.zPosition = b.backLayer ? 1 : (i == 1 ? 3 : 2)
            body.categoryBitMask = PhysCat.ragdoll
            body.collisionBitMask = PhysCat.statics | PhysCat.edge | PhysCat.debris
            body.contactTestBitMask = 0
            body.density = 1.4
            body.friction = 0.6
            body.restitution = 0.15
            body.linearDamping = 0.25
            body.angularDamping = 0.6
            n.physicsBody = body
            root.addChild(n)
            d.nodes.append(n)
            bodies.append(body)
        }
        // joints: (bodyA, bodyB, anchor, limit)
        let torso = bones[0]
        func pin(_ a: Int, _ b: Int, _ at: CGPoint, _ limit: CGFloat?) {
            let j = SKPhysicsJointPin.joint(withBodyA: bodies[a], bodyB: bodies[b], anchor: at)
            if let limit {
                j.shouldEnableLimits = true
                j.lowerAngleLimit = -limit
                j.upperAngleLimit = limit
            }
            j.frictionTorque = 0.0005
            world.add(j)
            d.joints.append(j)
        }
        pin(0, 1, torso.b, 0.7)                 // neck
        pin(0, 2, torso.a, 2.2); pin(0, 4, torso.a, 2.2)   // hips
        pin(2, 3, bones[2].a, 2.3); pin(4, 5, bones[4].a, 2.3) // knees (thigh.a = knee)
        pin(0, 6, bones[6].a, nil); pin(0, 8, bones[8].a, nil) // shoulders
        pin(6, 7, bones[6].b, 2.4); pin(8, 9, bones[8].b, 2.4) // elbows
        for (i, b) in bodies.enumerated() {
            b.velocity = CGVector(dx: vel.dx * rng.range(0.85, 1.15), dy: vel.dy * rng.range(0.85, 1.15))
            b.angularVelocity = i == 0 ? spin : rng.range(-6, 6)
        }
        dolls.append(d)
    }

    /// Ragdolls lie around for a while, then fade.
    func update(time: Double, world: SKPhysicsWorld) {
        var i = 0
        while i < dolls.count {
            let age = time - dolls[i].born
            if age > 6 { remove(dolls[i], world); dolls.remove(at: i); continue }
            if age > 5 { for n in dolls[i].nodes { n.alpha = CGFloat(6 - age) } }
            i += 1
        }
    }

    private func remove(_ d: Doll, _ world: SKPhysicsWorld) {
        for j in d.joints { world.remove(j) }
        for n in d.nodes { n.removeFromParent() }
    }

    func clear(_ world: SKPhysicsWorld) {
        for d in dolls { remove(d, world) }
        dolls.removeAll()
    }
}
