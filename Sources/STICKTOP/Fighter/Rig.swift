import SpriteKit

/// Angles in "facing right" space: 0 = pointing down, +π/2 = forward. Torso lean 0 = upright.
struct Pose {
    var lean: CGFloat = 0
    var thighF: CGFloat = 0, shinF: CGFloat = 0, thighB: CGFloat = 0, shinB: CGFloat = 0
    var armUF: CGFloat = 0, armLF: CGFloat = 0, armUB: CGFloat = 0, armLB: CGFloat = 0

    mutating func blend(to t: Pose, _ k: CGFloat, armK: CGFloat) {
        lean += (t.lean - lean) * k
        thighF += (t.thighF - thighF) * k; shinF += (t.shinF - shinF) * k
        thighB += (t.thighB - thighB) * k; shinB += (t.shinB - shinB) * k
        armUF += (t.armUF - armUF) * armK; armLF += (t.armLF - armLF) * armK
        armUB += (t.armUB - armUB) * armK; armLB += (t.armLB - armLB) * armK
    }
}

/// Procedural stickman: forward kinematics from the pelvis, one capsule sprite per bone,
/// mirrored by facing via the root's xScale.
final class Rig {
    static let thigh: CGFloat = 12.5, shin: CGFloat = 12.5, torso: CGFloat = 19, upper: CGFloat = 10, fore: CGFloat = 10
    static let thick: CGFloat = 5.5, headR: CGFloat = 7.5

    let root = SKNode()
    private let torsoB, thighFB, shinFB, thighBB, shinBB, upperFB, foreFB, upperBB, foreBB: SKSpriteNode
    private let head: SKSpriteNode
    let gun = SKSpriteNode()
    private var pose = Pose()
    private var runPhase: CGFloat = 0
    private var landT: CGFloat = 0
    private var gunIndex = -1
    private let front: SKColor, back: SKColor
    /// Spin while dead (ragdoll-ish tumble).
    var spin: CGFloat = 0
    private(set) var muzzleLocal = CGPoint.zero
    private var frontBones: [SKSpriteNode] = [], backBones: [SKSpriteNode] = []
    private var flashing = false

    static func capsule(_ len: CGFloat) -> SKTexture {
        let s: CGFloat = 4, w = Int((len + thick) * s), h = Int(thick * s)
        return Tex.drawn("bone\(len)", w, h) { c in
            c.setFillColor(.white)
            c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: CGFloat(h) / 2, cornerHeight: CGFloat(h) / 2, transform: nil))
            c.fillPath()
        }
    }

    init(color: SKColor) {
        front = color
        back = color.blended(withFraction: 0.2, of: .black) ?? color
        func bone(_ len: CGFloat, _ c: SKColor, _ z: CGFloat) -> SKSpriteNode {
            let n = SKSpriteNode(texture: Rig.capsule(len), size: CGSize(width: len + Rig.thick, height: Rig.thick))
            n.color = c; n.colorBlendFactor = 1; n.zPosition = z
            return n
        }
        upperBB = bone(Rig.upper, back, 1); foreBB = bone(Rig.fore, back, 1.1)
        thighBB = bone(Rig.thigh, back, 2); shinBB = bone(Rig.shin, back, 2.1)
        torsoB = bone(Rig.torso, color, 3)
        thighFB = bone(Rig.thigh, color, 4); shinFB = bone(Rig.shin, color, 4.1)
        head = SKSpriteNode(texture: Tex.circle, size: CGSize(width: Rig.headR * 2, height: Rig.headR * 2))
        head.color = color; head.colorBlendFactor = 1; head.zPosition = 5
        upperFB = bone(Rig.upper, color, 7); foreFB = bone(Rig.fore, color, 7.1)
        gun.zPosition = 6
        for n in [upperBB, foreBB, thighBB, shinBB, torsoB, thighFB, shinFB, head, gun, upperFB, foreFB] { root.addChild(n) }
        frontBones = [thighFB, shinFB, torsoB, upperFB, foreFB, head]
        backBones = [thighBB, shinBB, upperBB, foreBB]
    }

    @inline(__always) private static func dir(_ a: CGFloat) -> CGPoint { CGPoint(x: sin(a), y: -cos(a)) }

    private func place(_ n: SKSpriteNode, _ a: CGPoint, _ b: CGPoint) {
        n.position = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        n.zRotation = atan2(b.y - a.y, b.x - a.x)
    }

    func setWeapon(_ i: Int) {
        guard i != gunIndex else { return }
        gunIndex = i
        let t = Weapons.texture(i), d = Weapons.all[i]
        gun.texture = t
        gun.size = CGSize(width: t.size().width * 2, height: t.size().height * 2)
        gun.anchorPoint = Tex.anchor(t, px: d.grip.0, d.grip.1)
        // muzzle offset from grip in points (gun space, y up)
        muzzleLocal = CGPoint(x: CGFloat(d.muzzle.0 - d.grip.0) * 2, y: CGFloat(d.grip.1 - d.muzzle.1) * 2)
    }

    /// Recomputes the pose from fighter state and lays out the bones. Returns the muzzle in world space.
    @discardableResult
    func update(_ f: Fighter, dt: CGFloat) -> CGPoint {
        let facing = f.facing
        root.xScale = facing
        let speed = abs(f.vel.x)
        var t = Pose()
        let aim = f.input.aim - f.shoulder
        let aimA = atan2(aim.x * facing, -aim.y) // arm angle toward crosshair in rig space
        let def = Weapons.all[max(0, gunIndex)]

        if !f.alive {
            t.lean = 0.4; t.thighF = 0.9; t.shinF = 0.2; t.thighB = -0.6; t.shinB = -1.2
            t.armUF = 2.4; t.armLF = 2.9; t.armUB = -1.8; t.armLB = -2.4
        } else if f.grounded {
            if speed > 30 {
                let backwards = f.vel.x * facing < 0
                runPhase += speed * dt * 0.075 * (backwards ? -1 : 1)
                let s = sin(runPhase), s2 = sin(runPhase + .pi)
                t.thighF = 0.95 * s; t.thighB = 0.95 * s2
                // knee bends only on the back-swing
                t.shinF = t.thighF - 1.3 * max(0, -cos(runPhase))
                t.shinB = t.thighB - 1.3 * max(0, -cos(runPhase + .pi))
                t.lean = (backwards ? -0.08 : 0.18) * min(1, speed / Move.run)
            } else {
                t.thighF = 0.14; t.shinF = 0.06; t.thighB = -0.14; t.shinB = -0.18; t.lean = 0.04
                runPhase = 0
            }
        } else if f.wallDir != 0 && f.vel.y < 0 {
            t.thighF = 0.8; t.shinF = -0.1; t.thighB = 0.4; t.shinB = -0.5; t.lean = -0.1
        } else if f.vel.y > 0 {
            t.thighF = 1.1; t.shinF = 0.1; t.thighB = -0.25; t.shinB = -1.0; t.lean = 0.1
        } else {
            t.thighF = 0.45; t.shinF = -0.25; t.thighB = -0.3; t.shinB = -0.7; t.lean = 0.05
        }
        // landing crouch and hit flinch
        if f.evLand > 250 { landT = min(1, f.evLand / 900) }
        landT = max(0, landT - dt * 5)
        t.thighF += landT * 0.9; t.shinF -= landT * 0.9; t.thighB += landT * 0.9; t.shinB -= landT * 0.9
        t.lean += f.hitFlash * -0.5

        if f.alive {
            // aim (recoil kicks the arm up a bit)
            let a = aimA + f.recoilKick
            t.armUF = a - 0.15; t.armLF = a
            if def.twoHanded { t.armUB = a + 0.05; t.armLB = a + 0.25 } else {
                t.armUB = -0.5 * sin(runPhase); t.armLB = t.armUB + 0.4
            }
        }

        let k = 1 - exp(-22 * dt), armK = 1 - exp(-45 * dt)
        pose.blend(to: t, k, armK: f.alive ? armK : k)

        // Forward kinematics with the pelvis at the origin.
        let p = pose
        let hip = CGPoint.zero
        let kneeF = hip + Rig.dir(p.thighF) * Rig.thigh, footF = kneeF + Rig.dir(p.shinF) * Rig.shin
        let kneeB = hip + Rig.dir(p.thighB) * Rig.thigh, footB = kneeB + Rig.dir(p.shinB) * Rig.shin
        let up = CGPoint(x: sin(p.lean), y: cos(p.lean))
        let neck = hip + up * Rig.torso
        let sh = neck - up * 2
        let elbowF = sh + Rig.dir(p.armUF) * Rig.upper, handF = elbowF + Rig.dir(p.armLF) * Rig.fore
        let elbowB = sh + Rig.dir(p.armUB) * Rig.upper, handB = elbowB + Rig.dir(p.armLB) * Rig.fore
        let headC = neck + up * (Rig.headR + 1.5)

        // Lift so the lowest foot touches the ground when grounded; otherwise hang at standing height.
        let lift = f.grounded || !f.alive ? -min(footF.y, footB.y) : Rig.thigh + Rig.shin - 1
        root.position = CGPoint(x: 0, y: lift)
        place(thighFB, kneeF, hip); place(shinFB, footF, kneeF)
        place(thighBB, kneeB, hip); place(shinBB, footB, kneeB)
        place(torsoB, hip, neck)
        place(upperFB, sh, elbowF); place(foreFB, elbowF, handF)
        place(upperBB, sh, elbowB); place(foreBB, elbowB, handB)
        head.position = headC
        gun.isHidden = !f.alive
        gun.position = handF
        let ga = p.armLF - .pi / 2
        gun.zRotation = ga
        root.zRotation = f.alive ? 0 : root.zRotation + spin * dt

        let flash = f.hitFlash > 0
        if flash != flashing {
            flashing = flash
            for n in frontBones { n.color = flash ? .white : front }
            for n in backBones { n.color = flash ? .white : back }
        }

        // muzzle in world space
        let m = CGPoint(x: handF.x + cos(ga) * muzzleLocal.x - sin(ga) * muzzleLocal.y,
                        y: handF.y + sin(ga) * muzzleLocal.x + cos(ga) * muzzleLocal.y + lift)
        return CGPoint(x: f.pos.x + m.x * facing, y: f.pos.y + m.y)
    }
}
