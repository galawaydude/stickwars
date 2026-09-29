import SpriteKit

/// Orchestrates one fight on one snapshot. Systems live in extensions and small types elsewhere.
final class GameScene: SKScene {
    weak var app: AppDelegate?

    // Layers (explicit z because ignoresSiblingOrder = true)
    let backdrop = SKSpriteNode()
    let canvasRoot = SKNode()
    let world = SKNode()          // shaken; holds everything dynamic
    let hudRoot = SKNode()
    private(set) var canvas: Canvas?
    var appName = "Desktop"
    var level: Level
    var extracting = false
    var extractMs = 0.0
    var extractInfo = ""
    private var extractGen = 0
    var windows: [WindowInfo] = []

    // Dynamic systems
    let physicsRoot = SKNode()     // static bodies + debris; not shaken so physics stays consistent
    let debris = DebrisSystem()
    let statics = StaticBodies()
    let particles = Particles()
    let fx = FXPool()
    let projectileRoot = SKNode()
    var projectiles: [Projectile] = []
    var projectilePool: [SKSpriteNode] = []
    let crosshair = SKSpriteNode(texture: Art.crosshair)
    var shakeAmp: CGFloat = 0
    var hitStopLeft = 0.0
    var scratch: [Int] = []

    // Fighters, bots and the match
    var fighters: [Fighter] = []
    var player: Fighter!
    var brains: [Brain] = []
    var portals: [SKSpriteNode] = []
    var nav = NavGraph()
    var navVersion = -1, navBuilding = false, navAt = 0.0
    var matchOver = false, matchOverAt = 0.0, bannerLeft = -1
    var matchStarted = false
    var pickups: [Pickup] = []
    var pickupAt = 0.0
    let hud: HUD
    var platforms: [CGRect] = []   // tops of resting debris, refreshed per step

    // Timing
    let fixedDT = 1.0 / 120.0
    private var lastTime = 0.0
    private var acc = 0.0
    var simTime = 0.0
    var frameMs = 0.0
    var fps = 0.0
    private var fpsFrames = 0, fpsStart = 0.0

    // Input state
    var keysDown = Set<UInt16>()
    var mouse = CGPoint(x: 400, y: 400)
    var mouseDown = false
    private var pendingJump = false, pendingDown = false, pendingFire = false, pendingRelease = false
    private var pendingGrenade = false, pendingReload = false, pendingSwitch = -1
    var shiftDown = false

    // Screen melt (pause / resume transition)
    let meltRoot = SKNode()
    var meltCols: [SKSpriteNode] = []
    var meltDelay: [CGFloat] = []
    var meltT: CGFloat = 0
    var meltOut = true
    var meltDone: (() -> Void)?

    // Debug overlay
    let debugLabel = SKSpriteNode()
    var showDebug = false
    private var debugTimer = 0.0

    override init(size: CGSize) {
        level = Level(size: size)
        // generate all static pixel art up front and pack it into one atlas
        for i in 0..<Weapons.all.count { _ = Weapons.texture(i) }
        _ = [Art.rocket, Art.plasma, Art.grenade, Art.flash, Art.blast, Art.crosshair, Art.medkit] + Art.portalFrames
        Tex.packAtlas()
        hud = HUD(size: size)
        super.init(size: size)
        scaleMode = .fill
        anchorPoint = .zero
        backgroundColor = .black
        backdrop.anchorPoint = .zero
        backdrop.zPosition = -10
        canvasRoot.zPosition = 0
        world.zPosition = 10
        hudRoot.zPosition = 1000
        physicsRoot.zPosition = 5
        addChild(backdrop); addChild(canvasRoot); addChild(physicsRoot); addChild(world); addChild(hudRoot)
        physicsRoot.addChild(statics.root)
        physicsRoot.addChild(debris.root)
        particles.node.zPosition = 40
        fx.node.zPosition = 45
        projectileRoot.zPosition = 30
        world.addChild(particles.node); world.addChild(fx.node); world.addChild(projectileRoot)
        crosshair.size = CGSize(width: 22, height: 22)
        crosshair.zPosition = 500
        hudRoot.addChild(crosshair)
        hudRoot.addChild(hud.root)
        meltRoot.zPosition = 5000
        addChild(meltRoot)
        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.speed = 1
        // Thick floor and side walls so fast debris can't tunnel out.
        let bounds = SKNode()
        let t: CGFloat = 400, W = size.width, H = size.height
        let walls = SKPhysicsBody(bodies: [
            SKPhysicsBody(rectangleOf: CGSize(width: W + 2 * t, height: t), center: CGPoint(x: W / 2, y: -t / 2)),
            SKPhysicsBody(rectangleOf: CGSize(width: t, height: H * 4), center: CGPoint(x: -t / 2, y: H * 2)),
            SKPhysicsBody(rectangleOf: CGSize(width: t, height: H * 4), center: CGPoint(x: W + t / 2, y: H * 2)),
        ])
        walls.isDynamic = false
        walls.categoryBitMask = PhysCat.edge
        walls.friction = 0.8
        bounds.physicsBody = walls
        physicsRoot.addChild(bounds)
        debugLabel.anchorPoint = CGPoint(x: 0, y: 1)
        debugLabel.position = CGPoint(x: 14, y: size.height - 140)
        debugLabel.isHidden = true
        hudRoot.addChild(debugLabel)
        player = Fighter(id: 0, name: "YOU", color: SKColor(srgbRed: 0xF0 / 255, green: 0x7D / 255, blue: 0x2A / 255, alpha: 1), isPlayer: true)
        fighters = [player]
        world.addChild(player.node)
        player.node.isHidden = true
        player.alive = false
        player.rig.setWeapon(0)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: snapshot

    func loadSnapshot(_ image: CGImage, appName: String, windows: [WindowInfo]) {
        self.appName = appName
        self.windows = windows
        if backdrop.size != size {
            backdrop.texture = Backdrop.texture(size: size)
            backdrop.size = size
        }
        canvas?.node.removeFromParent()
        let c = Canvas(image: image, pointSize: size)
        canvas = c
        canvasRoot.addChild(c.node)
        statics.clear()
        debris.clear()
        particles.clear()
        fx.clear()
        clearProjectiles()
        for p in pickups { p.node.removeFromParent() }
        pickups.removeAll()
        pickupAt = simTime + 8
        navVersion = -1
        nav = NavGraph()
        configureFighters()
        if !matchStarted { matchStarted = true; newMatch() }
        level.reset([])
        lastTime = 0
        shakeAmp = 0
        for f in fighters { f.vel = .zero }
        // Extraction off the main thread; the level becomes solid when it lands.
        extracting = true
        extractGen += 1
        let gen = extractGen, sz = size
        let useAX = !(app?.dev ?? false)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let ex = Extractor.run(image: image, windows: windows, screen: sz, useAX: useAX)
            DispatchQueue.main.async {
                guard let self, gen == self.extractGen else { return }
                self.applyExtraction(ex)
            }
        }
    }

    private func applyExtraction(_ ex: Extraction) {
        level.reset(ex.elements)
        extracting = false
        extractMs = ex.ms
        extractInfo = "ax \(ex.axCount) px \(ex.pixelCount)"
    }

    /// Random open spot on top of some element (or the floor).
    func spawnPoint() -> CGPoint {
        for _ in 0..<60 {
            guard level.elements.count > 0 else { break }
            let e = level.elements[rng.int(level.elements.count)]
            guard e.state == .solid, e.rect.width >= 20, e.rect.maxY > 60, e.rect.maxY < size.height - 90 else { continue }
            let p = CGPoint(x: clamp(e.rect.minX + rng.range(8, max(9, e.rect.width - 8)), 20, size.width - 20), y: e.rect.maxY)
            var blocked = false
            level.query(CGRect(x: p.x - Move.halfW, y: p.y + 2, width: Move.halfW * 2, height: Move.height)) { i in
                if level.elements[i].wall { blocked = true }
            }
            if !blocked { return p }
        }
        return CGPoint(x: rng.range(40, size.width - 40), y: 0)
    }

    func spawn(_ f: Fighter, at p: CGPoint) {
        f.pos = p
        f.vel = .zero
        f.grounded = true
        f.groundY = f.pos.y
        f.alive = true
        f.hp = 100
        f.node.isHidden = false
        f.node.alpha = 1
        f.weapons.refill()
        f.lastHitBy = -1
        f.jetFuel = 1
        f.spawnPoint = nil
        f.rig.setWeapon(f.weapons.current)
        f.rig.root.zRotation = 0
    }

    func resetClock() { lastTime = 0; acc = 0 }

    func didPause() {
        keysDown.removeAll()
        mouseDown = false
        shiftDown = false
    }

    // MARK: loop

    override func update(_ currentTime: TimeInterval) {
        let t0 = now()
        var dt = lastTime == 0 ? fixedDT : currentTime - lastTime
        lastTime = currentTime
        dt = clamp(dt, 0, 0.1)
        if melting { updateMelt(dt); return }
        if hitStopLeft > 0 {
            hitStopLeft -= dt
            physicsWorld.speed = 0
            dt = 0
        } else if physicsWorld.speed == 0 { physicsWorld.speed = 1 }
        acc += dt
        var steps = 0
        while acc >= fixedDT - 1e-6, steps < 8 {
            fixedStep(fixedDT)
            acc -= fixedDT
            steps += 1
        }
        if steps == 8 { acc = 0 }
        frameUpdate(dt)
        canvas?.flush()
        frameMs = (now() - t0) * 1000
        fpsFrames += 1
        if currentTime - fpsStart >= 0.5 { fps = Double(fpsFrames) / (currentTime - fpsStart); fpsFrames = 0; fpsStart = currentTime }
    }

    func fixedStep(_ dt: Double) {
        guard !extracting else { return }
        simTime += dt
        readPlayerInput()
        for b in brains { b.think(self, dt) }
        let fdt = CGFloat(dt)
        debris.collectPlatforms(into: &platforms)
        platforms.withUnsafeBufferPointer { plat in
            for f in fighters where f.alive {
                f.step(fdt, level: level, extra: plat, bounds: size)
                if f.evLand > 500 {
                    particles.burst(f.pos, n: 6, speed: 120, life: 0.35, color: SKColor(white: 0.85, alpha: 1), size: 2, gravity: 200,
                                    dir: CGPoint(x: 0, y: 1), cone: 1.4)
                    if f.isPlayer { Audio.shared.play(.land, volume: 0.4, pan: pan(f.pos)) }
                }
                if f.evJump && f.isPlayer { Audio.shared.play(.jump, volume: 0.3, pan: pan(f.pos)) }
                if f.jetting && rng.chance(0.6) {
                    particles.emit(f.pos.x - f.facing * 4, f.pos.y + 34, vx: rng.range(-30, 30), vy: -rng.range(200, 320), life: 0.25,
                                   color: rng.chance(0.5) ? SKColor(srgbRed: 0.4, green: 0.9, blue: 1, alpha: 1) : .orange, size: 2, gravity: 0)
                }
            }
        }
        for f in fighters where f.alive { updateWeapons(f, dt) }
        updateProjectiles(fdt)
        updateMatch(dt)
        for f in fighters { f.input.clearEdges() }
    }

    func frameUpdate(_ dt: Double) {
        let fdt = CGFloat(dt)
        for f in fighters {
            f.node.position = CGPoint(x: f.pos.x.rounded(), y: f.pos.y.rounded())
            f.hitFlash = max(0, f.hitFlash - fdt)
            f.recoilKick = max(0, f.recoilKick - fdt * 6)
            f.muzzle = f.rig.update(f, dt: fdt)
            if f.alive { debris.nudge(f.bodyRect, vx: f.vel.x) }
        }
        particles.update(fdt)
        fx.update(fdt)
        debris.update(time: simTime, dt: fdt)
        for i in level.removed { debris.wake(near: level.elements[i].rect) }
        statics.sync(level)
        // Screen shake in whole points, on the world layer only.
        if shakeAmp > 0.5 {
            world.position = CGPoint(x: (rng.range(-1, 1) * shakeAmp).rounded(), y: (rng.range(-1, 1) * shakeAmp).rounded())
            shakeAmp *= CGFloat(exp(-12 * dt))
        } else if world.position != .zero { world.position = .zero; shakeAmp = 0 }
        crosshair.position = CGPoint(x: mouse.x.rounded(), y: mouse.y.rounded())
        updateHUD(dt)
        if showDebug {
            debugTimer -= dt
            if debugTimer <= 0 {
                debugTimer = 0.25
                PixelFont.set(debugLabel, debugText(), scale: 2, color: .green)
            }
        }
    }

    func debugText() -> String {
        String(format: "FPS %.0f  UPDATE %.2f MS  ELEMENTS %d  BODIES %d  PARTICLES %d  TILES %d  EXTRACT %.0f MS", fps, frameMs,
               level.solidCount, debris.liveCount, particles.count, canvas?.lastFlushCount ?? 0, extractMs)
    }

    // MARK: input

    private func readPlayerInput() {
        var i = player.input
        let left = keysDown.contains(0) || keysDown.contains(123), right = keysDown.contains(2) || keysDown.contains(124)
        i.moveX = (right ? 1 : 0) - (left ? 1 : 0)
        i.jumpHeld = keysDown.contains(13) || keysDown.contains(49) || keysDown.contains(126)
        i.down = keysDown.contains(1) || keysDown.contains(125)
        i.jet = shiftDown
        i.fire = mouseDown
        i.aim = mouse
        if pendingJump { i.jumpPressed = true; pendingJump = false }
        if pendingDown { i.downPressed = true; pendingDown = false }
        if pendingFire { i.firePressed = true; pendingFire = false }
        if pendingRelease { i.fireReleased = true; pendingRelease = false }
        if pendingGrenade { i.grenade = true; pendingGrenade = false }
        if pendingReload { i.reload = true; pendingReload = false }
        if pendingSwitch >= 0 { i.switchTo = pendingSwitch; pendingSwitch = -1 }
        player.input = i
        if player.alive { player.facing = mouse.x >= player.pos.x ? 1 : -1 }
    }

    /// Shared by real key events and the dev harness.
    func key(_ code: UInt16, down: Bool, isRepeat: Bool = false) {
        if down {
            if isRepeat { return }
            keysDown.insert(code)
            switch code {
            case 53: app?.pause()                                  // Esc
            case 13, 49, 126: pendingJump = true                   // W, Space, Up
            case 1, 125: pendingDown = true                        // S, Down
            case 15: pendingReload = true                          // R
            case 99: showDebug.toggle(); debugLabel.isHidden = !showDebug   // F3
            case 18, 19, 20, 21, 23, 22, 26:                       // 1-7
                pendingSwitch = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6][code]!
            default: break
            }
        } else {
            keysDown.remove(code)
        }
    }

    func mouseButton(_ down: Bool) {
        if down { mouseDown = true; pendingFire = true } else { mouseDown = false; pendingRelease = true }
    }

    // Events arrive from GameView (not the SKView forwarding) so each is handled exactly once.
    func grenadePressed() { pendingGrenade = true }
    func scroll(_ e: NSEvent) {
        guard abs(e.scrollingDeltaY) > 0.5 || abs(e.deltaY) > 0.1 else { return }
        let n = Weapons.all.count
        let dir = (e.scrollingDeltaY != 0 ? e.scrollingDeltaY : e.deltaY) > 0 ? -1 : 1
        pendingSwitch = (player.weapons.current + dir + n) % n
    }
}
