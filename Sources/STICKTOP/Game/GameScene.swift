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

    // Fighters
    var fighters: [Fighter] = []
    var player: Fighter!
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

    // Debug overlay
    let debugLabel = SKSpriteNode()
    var showDebug = false
    private var debugTimer = 0.0

    override init(size: CGSize) {
        level = Level(size: size)
        super.init(size: size)
        scaleMode = .fill
        anchorPoint = .zero
        backgroundColor = .black
        backdrop.anchorPoint = .zero
        backdrop.zPosition = -10
        canvasRoot.zPosition = 0
        world.zPosition = 10
        hudRoot.zPosition = 1000
        addChild(backdrop); addChild(canvasRoot); addChild(world); addChild(hudRoot)
        debugLabel.anchorPoint = CGPoint(x: 0, y: 1)
        debugLabel.position = CGPoint(x: 12, y: size.height - 120)
        debugLabel.isHidden = true
        hudRoot.addChild(debugLabel)
        player = Fighter(id: 0, name: "YOU", color: SKColor(srgbRed: 0xF0 / 255, green: 0x7D / 255, blue: 0x2A / 255, alpha: 1), isPlayer: true)
        fighters = [player]
        world.addChild(player.node)
        player.node.isHidden = true
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
        level.reset([])
        lastTime = 0
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
        for f in fighters where f.node.isHidden || f.pos == .zero { spawn(f) }
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

    func spawn(_ f: Fighter) {
        f.pos = spawnPoint()
        f.vel = .zero
        f.grounded = true
        f.groundY = f.pos.y
        f.alive = true
        f.hp = 100
        f.node.isHidden = false
        f.node.alpha = 1
        f.weapons.refill()
    }

    func didPause() {
        keysDown.removeAll()
        mouseDown = false
        shiftDown = false
    }

    func newMatch() {}

    // MARK: loop

    override func update(_ currentTime: TimeInterval) {
        let t0 = now()
        var dt = lastTime == 0 ? fixedDT : currentTime - lastTime
        lastTime = currentTime
        dt = clamp(dt, 0, 0.1)
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
        simTime += dt
        guard !extracting else { return }
        readPlayerInput()
        let fdt = CGFloat(dt)
        platforms.withUnsafeBufferPointer { plat in
            for f in fighters where f.alive {
                f.step(fdt, level: level, extra: plat, bounds: size)
            }
        }
        for f in fighters { f.input.clearEdges() }
    }

    func frameUpdate(_ dt: Double) {
        let fdt = CGFloat(dt)
        for f in fighters {
            f.node.position = CGPoint(x: f.pos.x.rounded(), y: f.pos.y.rounded())
            f.hitFlash = max(0, f.hitFlash - fdt)
            f.recoilKick = max(0, f.recoilKick - fdt * 6)
            f.rig.update(f, dt: fdt)
        }
        if showDebug {
            debugTimer -= dt
            if debugTimer <= 0 {
                debugTimer = 0.25
                PixelFont.set(debugLabel, debugText(), scale: 2, color: .green)
            }
        }
    }

    func debugText() -> String {
        String(format: "FPS %.0f  FRAME %.2f MS  ELEMENTS %d  TILES %d  EXTRACT %.0f MS", fps, frameMs, level.solidCount,
               canvas?.lastFlushCount ?? 0, extractMs)
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

    override func keyDown(with e: NSEvent) { key(e.keyCode, down: true, isRepeat: e.isARepeat) }
    override func keyUp(with e: NSEvent) { key(e.keyCode, down: false) }
    override func flagsChanged(with e: NSEvent) { shiftDown = e.modifierFlags.contains(.shift) }
    override func mouseMoved(with e: NSEvent) { mouse = e.location(in: self) }
    override func mouseDragged(with e: NSEvent) { mouse = e.location(in: self) }
    override func rightMouseDragged(with e: NSEvent) { mouse = e.location(in: self) }
    override func mouseDown(with e: NSEvent) { mouse = e.location(in: self); mouseButton(true) }
    override func mouseUp(with e: NSEvent) { mouseButton(false) }
    override func rightMouseDown(with e: NSEvent) { pendingGrenade = true }
    override func scrollWheel(with e: NSEvent) {
        guard abs(e.scrollingDeltaY) > 0.5 || abs(e.deltaY) > 0.1 else { return }
        let n = Weapons.all.count
        let dir = (e.scrollingDeltaY != 0 ? e.scrollingDeltaY : e.deltaY) > 0 ? -1 : 1
        pendingSwitch = (player.weapons.current + dir + n) % n
    }
}
