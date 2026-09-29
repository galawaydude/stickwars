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

/// One bone in scene space (for ragdolls).
struct BoneShot {
    var a: CGPoint, b: CGPoint
    var head: Bool
    var backLayer: Bool
}

/// Procedural stickman in the style of Alan Becker's animations: forward kinematics from the
/// pelvis, one capsule sprite per bone, snappy pose blending, front flips on double jumps,
/// flinches, breathing, and a gun that kicks, reloads, swaps and charges.
final class Rig {
    static let thigh: CGFloat = 12.5, shin: CGFloat = 12.5, torso: CGFloat = 18, upper: CGFloat = 10, fore: CGFloat = 10
    static let thick: CGFloat = 5.5, headR: CGFloat = 8.5
    static let pivotY: CGFloat = 30   // flips rotate around the body's middle

    /// root: flip rotation + facing mirror. inner: offset so the feet touch the ground.
    let root = SKNode()
    private let inner = SKNode()
    private let torsoB, thighFB, shinFB, thighBB, shinBB, upperFB, foreFB, upperBB, foreBB: SKSpriteNode
    private let head: SKSpriteNode
    let gun = SKSpriteNode()
    private let chargeGlow = SKSpriteNode()
    private var pose = Pose()
    private var runPhase: CGFloat = 0
    private var landT: CGFloat = 0
    private var clock: CGFloat = rng.range(0, 10)
    private var gunIndex = -1
    private let front: SKColor, back: SKColor
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
        chargeGlow.texture = Tex.pixels("glow", [".cc.", "cwwc", "cwwc", ".cc."])
        chargeGlow.size = CGSize(width: 8, height: 8)
        chargeGlow.blendMode = .add
        chargeGlow.isHidden = true
        chargeGlow.zPosition = 1
        gun.addChild(chargeGlow)
        root.position = CGPoint(x: 0, y: Rig.pivotY)
        root.addChild(inner)
        for n in [upperBB, foreBB, thighBB, shinBB, torsoB, thighFB, shinFB, head, gun, upperFB, foreFB] { inner.addChild(n) }
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
        chargeGlow.position = muzzleLocal
    }

    @inline(__always) private static func easeOut(_ t: CGFloat) -> CGFloat { 1 - (1 - t) * (1 - t) * (1 - t) }

    /// Recomputes the pose from fighter state and lays out the bones. Returns the muzzle in world space.
    @discardableResult
    func update(_ f: Fighter, dt: CGFloat) -> CGPoint {
        clock += dt
        let facing = f.facing
        root.xScale = facing
        let speed = abs(f.vel.x)
        var t = Pose()
        let def = Weapons.all[max(0, gunIndex)]
        let slot = f.weapons.slots[f.weapons.current]

        // Front flip on double jump (rotates around the body's middle).
        var flipAngle: CGFloat = 0
        if f.flipT < 1 {
            f.flipT = min(1, f.flipT + dt / 0.36)
            flipAngle = -facing * 2 * .pi * Rig.easeOut(f.flipT)
            if f.grounded { f.flipT = 1; flipAngle = 0 }
        }
        root.zRotation = flipAngle
        let flipping = f.flipT < 1

        if flipping {
            // tucked
            t.thighF = 1.9; t.shinF = 0.2; t.thighB = 1.6; t.shinB = -0.1; t.lean = 0.35
        } else if f.grounded {
            if speed > 30 {
                let backwards = f.vel.x * facing < 0
                runPhase += speed * dt * 0.078 * (backwards ? -1 : 1)
                let amp = 1.05 * min(1, speed / Move.run + 0.25)
                t.thighF = amp * sin(runPhase); t.thighB = amp * sin(runPhase + .pi)
                // knee bends only on the back-swing
                t.shinF = t.thighF - 1.45 * max(0, -cos(runPhase))
                t.shinB = t.thighB - 1.45 * max(0, -cos(runPhase + .pi))
                t.lean = (backwards ? -0.1 : 0.26) * min(1, speed / Move.run)
            } else {
                // idle: planted stance with a little breathing
                let br = sin(clock * 2.6)
                t.thighF = 0.3; t.shinF = 0.12 - br * 0.03; t.thighB = -0.28; t.shinB = -0.34 + br * 0.03
                t.lean = 0.05 + br * 0.025
                runPhase = 0
            }
        } else if f.jetting {
            t.thighF = 0.35; t.shinF = -0.35; t.thighB = -0.15; t.shinB = -0.7; t.lean = 0.2
        } else if f.wallDir != 0 && f.vel.y < 0 {
            t.thighF = 0.9; t.shinF = -0.15; t.thighB = 0.45; t.shinB = -0.55; t.lean = -0.12
        } else if f.vel.y > 0 {
            t.thighF = 1.25; t.shinF = 0.15; t.thighB = -0.2; t.shinB = -1.1; t.lean = 0.12
        } else {
            t.thighF = 0.5; t.shinF = -0.2; t.thighB = -0.35; t.shinB = -0.8; t.lean = 0.06
        }
        // landing crouch
        if f.landKick > 0 { landT = max(landT, min(1, f.landKick / 900)); f.landKick = 0 }
        landT = max(0, landT - dt * 4.5)
        t.thighF += landT * 1.0; t.shinF -= landT * 1.0; t.thighB += landT * 1.0; t.shinB -= landT * 1.0
        t.lean += landT * 0.25
        // flinch away from hits (head snaps back, torso bends)
        f.hitKick = max(0, f.hitKick - dt * 5)
        t.lean -= f.hitKick * f.hitDirX * facing * 0.9

        if f.alive {
            // aim at the crosshair; compensate the flip so the gun keeps tracking
            var a = atan2((f.input.aim - f.shoulder).x * facing, -(f.input.aim - f.shoulder).y) - flipAngle * facing
            a += f.recoilKick
            // reload: gun dips down and comes back up; weapon switch: quick lowered swap
            if slot.reloadLeft > 0 && def.reload > 0 {
                let r = CGFloat(1 - slot.reloadLeft / def.reload)
                let bump = sin(.pi * clamp(r, 0, 1))
                a = a + (0.75 - a) * 0.8 * bump
            }
            if f.switchT < 1 {
                f.switchT = min(1, f.switchT + dt / 0.22)
                a = a + (0.5 - a) * (1 - f.switchT)
            }
            // idle weapon sway
            if f.grounded && speed < 30 { a += sin(clock * 1.7) * 0.02 }
            t.armUF = a - 0.15; t.armLF = a
            if def.twoHanded { t.armUB = a + 0.05; t.armLB = a + 0.3 } else {
                // free arm pumps with the run
                t.armUB = f.grounded && speed > 30 ? -0.9 * sin(runPhase) : 0.25; t.armLB = t.armUB + 0.9
            }
        }

        let k = 1 - exp(-22 * dt), armK = flipping ? 1 : 1 - exp(-45 * dt)
        pose.blend(to: t, k, armK: armK)

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
        let headC = neck + up * (Rig.headR + 1) + CGPoint(x: -f.hitKick * f.hitDirX * facing * 2, y: 0)

        // Lift so the lowest foot touches the ground when grounded; otherwise hang at standing height.
        let lift = f.grounded && !flipping ? -min(footF.y, footB.y) : Rig.thigh + Rig.shin - 1
        inner.position = CGPoint(x: 0, y: lift - Rig.pivotY)
        place(thighFB, kneeF, hip); place(shinFB, footF, kneeF)
        place(thighBB, kneeB, hip); place(shinBB, footB, kneeB)
        place(torsoB, hip, neck)
        place(upperFB, sh, elbowF); place(foreFB, elbowF, handF)
        place(upperBB, sh, elbowB); place(foreBB, elbowB, handB)
        head.position = headC

        // Gun: rotates with the forearm, slides back on recoil, pops in on swap, shakes when charged.
        let ga = p.armLF - .pi / 2
        let slide = f.recoilKick * 9
        var gp = CGPoint(x: handF.x - cos(ga) * slide, y: handF.y - sin(ga) * slide)
        if slot.charging {
            let c = slot.charge
            gp.x += rng.range(-1, 1) * c * 1.5; gp.y += rng.range(-1, 1) * c * 1.5
            chargeGlow.isHidden = false
            chargeGlow.setScale(0.6 + c * 2.2 + sin(clock * 40) * 0.2 * c)
            chargeGlow.alpha = 0.5 + c * 0.5
        } else if !chargeGlow.isHidden { chargeGlow.isHidden = true }
        gun.position = gp
        gun.zRotation = ga
        gun.setScale(f.switchT < 1 ? 0.55 + 0.45 * Rig.easeOut(f.switchT) : 1)
        gun.isHidden = !f.alive

        let flash = f.hitFlash > 0
        if flash != flashing {
            flashing = flash
            for n in frontBones { n.color = flash ? .white : front }
            for n in backBones { n.color = flash ? .white : back }
        }

        // muzzle in world space (exact, including flips)
        if let parent = root.parent {
            let m = gun.convert(muzzleLocal, to: parent)
            return CGPoint(x: f.pos.x + m.x, y: f.pos.y + m.y)
        }
        return f.shoulder
    }

    /// Current bones in scene space, for spawning a ragdoll.
    func bones(in scene: SKNode) -> [BoneShot] {
        func ends(_ n: SKSpriteNode) -> BoneShot {
            let half = (n.size.width - Rig.thick) / 2
            let a = CGPoint(x: n.position.x - cos(n.zRotation) * half, y: n.position.y - sin(n.zRotation) * half)
            let b = CGPoint(x: n.position.x + cos(n.zRotation) * half, y: n.position.y + sin(n.zRotation) * half)
            return BoneShot(a: inner.convert(a, to: scene), b: inner.convert(b, to: scene), head: false, backLayer: backBones.contains(n))
        }
        // order matters: torso, head, thighF, shinF, thighB, shinB, upperF, foreF, upperB, foreB
        var out = [ends(torsoB)]
        let h = inner.convert(head.position, to: scene)
        out.append(BoneShot(a: h, b: h, head: true, backLayer: false))
        for n in [thighFB, shinFB, thighBB, shinBB, upperFB, foreFB, upperBB, foreBB] { out.append(ends(n)) }
        return out
    }

    var colors: (SKColor, SKColor) { (front, back) }
}
