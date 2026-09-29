import SpriteKit

struct FighterInput {
    var moveX: CGFloat = 0
    var jumpHeld = false, jumpPressed = false
    var down = false, downPressed = false
    var jet = false
    var fire = false, firePressed = false, fireReleased = false
    var grenade = false
    var melee = false
    var reload = false
    var aim = CGPoint.zero
    var switchTo = -1

    mutating func clearEdges() {
        jumpPressed = false; downPressed = false; firePressed = false; fireReleased = false
        grenade = false; melee = false; reload = false; switchTo = -1
    }
}

/// Movement tuning (points, seconds) for the 60-pt stickmen at 120 Hz.
enum Move {
    static let run: CGFloat = 360, groundAcc: CGFloat = 3400, airAcc: CGFloat = 2000
    static let gravity: CGFloat = 2200, lowJumpMul: CGFloat = 1.9, fastFallMul: CGFloat = 1.7
    static let jump: CGFloat = 800, doubleJump: CGFloat = 740
    static let wallSlide: CGFloat = 150, wallJumpX: CGFloat = 440, wallJumpY: CGFloat = 760
    static let coyote: CGFloat = 0.08, buffer: CGFloat = 0.12
    static let halfW: CGFloat = 8, height: CGFloat = 56
    static let maxFall: CGFloat = 1500
    static let jetAccel: CGFloat = 2800, jetMaxUp: CGFloat = 380, jetDrain: CGFloat = 1 / 1.6, jetRecharge: CGFloat = 1 / 1.1
}

final class Fighter {
    let id: Int
    let name: String
    let color: SKColor
    let isPlayer: Bool
    var pos = CGPoint.zero        // feet centre
    var vel = CGPoint.zero
    var facing: CGFloat = 1
    var grounded = false
    var groundY: CGFloat = 0
    var groundIsFloor = false
    var wallDir = 0               // wall we're touching: -1 left, +1 right
    var wallTimer: CGFloat = 0    // grace period for wall jumps
    var lastWall = 0
    var coyote: CGFloat = 0, jumpBuffer: CGFloat = 0
    var airJumps = 1
    var jetFuel: CGFloat = 1
    var jetting = false
    var hp: CGFloat = 100
    var alive = true
    var respawnAt = 0.0
    var spawnPoint: CGPoint?
    var invulnUntil = 0.0
    var kills = 0, deaths = 0
    var input = FighterInput()
    var lastHitBy = -1
    var lastHitTime = 0.0
    // one-frame events for FX/sound
    var evJump = false, evLand: CGFloat = 0, evWallJump = false
    var hitFlash: CGFloat = 0
    // animation triggers read (and decayed) by the rig at frame rate
    var flipT: CGFloat = 1        // < 1 while front-flipping
    var hitKick: CGFloat = 0, hitDirX: CGFloat = 0
    var switchT: CGFloat = 1
    var slashT: CGFloat = 1        // < 1 while swinging the knife
    var knifeCD = 0.0
    var armor: CGFloat = 0         // absorbs most damage until it breaks
    var landKick: CGFloat = 0
    let hpBack = SKSpriteNode(texture: Tex.white), hpFill = SKSpriteNode(texture: Tex.white)
    let marker = SKSpriteNode()
    var muzzle = CGPoint.zero
    var recoilKick: CGFloat = 0

    let node = SKNode()
    let rig: Rig
    let tag: SKSpriteNode
    var weapons = WeaponBelt()

    init(id: Int, name: String, color: SKColor, isPlayer: Bool) {
        self.id = id; self.name = name; self.color = color; self.isPlayer = isPlayer
        rig = Rig(color: color)
        tag = PixelFont.label(name, scale: 2, color: color.blended(withFraction: 0.35, of: .white) ?? color)
        tag.position = CGPoint(x: 0, y: 76)
        tag.zPosition = 30
        node.addChild(rig.root)
        node.addChild(tag)
        // small HP bar over bots, pixel arrow over the player
        for (b, w, c) in [(hpBack, CGFloat(30), SKColor(white: 0.05, alpha: 0.8)), (hpFill, CGFloat(28), color)] {
            b.size = CGSize(width: w, height: b === hpBack ? 6 : 4); b.anchorPoint = CGPoint(x: 0, y: 0.5)
            b.position = CGPoint(x: -15 + (b === hpFill ? 1 : 0), y: 88); b.color = c; b.colorBlendFactor = 1
            b.zPosition = 30; b.isHidden = true; node.addChild(b)
        }
        if isPlayer {
            let t = Tex.pixels("youarrow", ["kkkkkkk", "kyyyyyk", ".kyyyk.", "..kyk..", "...k..."])
            marker.texture = t; marker.size = CGSize(width: 14, height: 10); marker.position = CGPoint(x: 0, y: 94)
            marker.zPosition = 31; node.addChild(marker)
        }
        node.zPosition = 20 + CGFloat(id) * 0.5
    }

    var bodyRect: CGRect { CGRect(x: pos.x - Move.halfW, y: pos.y, width: Move.halfW * 2, height: Move.height) }
    var center: CGPoint { CGPoint(x: pos.x, y: pos.y + 30) }
    var shoulder: CGPoint { CGPoint(x: pos.x, y: pos.y + 42) }

    /// One fixed step of the kinematic platformer controller. `extra` are extra one-way
    /// platforms (tops of resting debris).
    func step(_ dt: CGFloat, level: Level?, extra: UnsafeBufferPointer<CGRect>, bounds: CGSize) {
        evJump = false; evLand = 0; evWallJump = false
        let inp = input
        coyote = grounded ? Move.coyote : max(0, coyote - dt)
        jumpBuffer = max(0, jumpBuffer - dt)
        wallTimer = max(0, wallTimer - dt)

        // Horizontal: accelerate toward target speed; stronger decel keeps knockback snappy.
        let target = inp.moveX * Move.run
        let a = (grounded ? Move.groundAcc : Move.airAcc) * dt
        if vel.x < target { vel.x = min(target, vel.x + a) } else if vel.x > target { vel.x = max(target, vel.x - a) }

        // Drop through a ledge.
        if inp.downPressed && grounded && !groundIsFloor {
            grounded = false; coyote = 0; pos.y -= 1.5
        }

        // Jumps: ground (with coyote time), wall, double, else buffer.
        func groundJump() { vel.y = Move.jump; grounded = false; coyote = 0; jumpBuffer = 0; evJump = true }
        if inp.jumpPressed {
            if grounded || coyote > 0 { groundJump() }
            else if wallTimer > 0 && lastWall != 0 {
                vel.x = -CGFloat(lastWall) * Move.wallJumpX; vel.y = Move.wallJumpY
                wallTimer = 0; evWallJump = true; facing = -CGFloat(lastWall)
            } else if airJumps > 0 { vel.y = Move.doubleJump; airJumps -= 1; evJump = true; flipT = 0 }
            else { jumpBuffer = Move.buffer }
        } else if jumpBuffer > 0 && grounded { groundJump() }

        // Vertical forces.
        var g = Move.gravity
        if vel.y > 0 && !inp.jumpHeld { g *= Move.lowJumpMul }
        if inp.down && vel.y < 0 && !grounded { g *= Move.fastFallMul }
        jetting = inp.jet && jetFuel > 0.02
        if jetting {
            vel.y = min(Move.jetMaxUp, vel.y + Move.jetAccel * dt)
            jetFuel = max(0, jetFuel - Move.jetDrain * dt)
            grounded = false
        } else {
            vel.y -= g * dt
            if grounded { jetFuel = min(1, jetFuel + Move.jetRecharge * dt) }
        }
        if !grounded && wallDir != 0 && inp.moveX * CGFloat(wallDir) > 0 && vel.y < -Move.wallSlide { vel.y = -Move.wallSlide }
        vel.y = max(vel.y, -Move.maxFall)

        // Sweep x against solid sides of big elements, then screen edges.
        let prevX = pos.x
        pos.x += vel.x * dt
        wallDir = 0
        if let level {
            var hitR = CGFloat.greatestFiniteMagnitude, hitL = -CGFloat.greatestFiniteMagnitude
            let q = CGRect(x: min(prevX, pos.x) - Move.halfW - 1, y: pos.y + 1, width: abs(pos.x - prevX) + Move.halfW * 2 + 2, height: Move.height - 2)
            let py = pos.y, px = pos.x, vx = vel.x
            level.query(q) { i in
                let e = level.elements[i]
                guard e.wall else { return }
                let r = e.rect
                guard py < r.maxY - 3, py + Move.height > r.minY else { return }
                if vx >= 0, prevX + Move.halfW <= r.minX + 0.5, px + Move.halfW > r.minX - 0.5 { hitR = min(hitR, r.minX) }
                if vx <= 0, prevX - Move.halfW >= r.maxX - 0.5, px - Move.halfW < r.maxX + 0.5 { hitL = max(hitL, r.maxX) }
            }
            if hitR < .greatestFiniteMagnitude { pos.x = hitR - Move.halfW; vel.x = min(0, vel.x); wallDir = 1 }
            if hitL > -.greatestFiniteMagnitude { pos.x = hitL + Move.halfW; vel.x = max(0, vel.x); wallDir = -1 }
        }
        if pos.x <= Move.halfW { pos.x = Move.halfW; vel.x = max(0, vel.x); wallDir = -1 }
        if pos.x >= bounds.width - Move.halfW { pos.x = bounds.width - Move.halfW; vel.x = min(0, vel.x); wallDir = 1 }
        if wallDir != 0 && !grounded { lastWall = wallDir; wallTimer = 0.1 }

        // Sweep y: land on one-way ledges only if the feet were at/above the top last step.
        let prevY = pos.y
        pos.y += vel.y * dt
        let wasGrounded = grounded
        grounded = false
        if vel.y <= 0 {
            var best = -CGFloat.greatestFiniteMagnitude
            var floor = false
            if pos.y <= 0 && prevY >= -0.01 { best = 0; floor = true }
            let x0 = pos.x - Move.halfW, x1 = pos.x + Move.halfW, py = pos.y
            if let level {
                let q = CGRect(x: x0, y: py - 1, width: Move.halfW * 2, height: prevY - py + 2)
                level.query(q) { i in
                    let top = level.elements[i].rect.maxY
                    if prevY >= top - 0.01, py <= top, top > best { best = top; floor = false }
                }
            }
            for r in extra where r.maxX > x0 && r.minX < x1 {
                let top = r.maxY
                if prevY >= top - 0.01, py <= top, top > best { best = top; floor = false }
            }
            if best > -CGFloat.greatestFiniteMagnitude {
                if !wasGrounded { evLand = -vel.y; landKick = max(landKick, evLand) }
                pos.y = best; vel.y = 0; grounded = true; groundY = best; groundIsFloor = floor
                airJumps = 1
            }
        } else if pos.y + Move.height > bounds.height + 200 {
            vel.y = min(vel.y, 0) // don't leave through the top forever
        }
        if !grounded && wasGrounded { coyote = Move.coyote }
    }
}
