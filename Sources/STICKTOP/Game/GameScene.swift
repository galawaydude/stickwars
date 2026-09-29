import SpriteKit

/// Orchestrates one fight on one snapshot. Systems live in extensions / small types in other files.
final class GameScene: SKScene {
    weak var app: AppDelegate?

    // Layers (explicit z because ignoresSiblingOrder = true)
    let backdrop = SKSpriteNode()
    let canvasRoot = SKNode()
    let world = SKNode()          // shaken; holds everything dynamic
    let hudRoot = SKNode()
    private(set) var canvas: Canvas?
    var appName = "Desktop"
    var extracting = false
    var extractMs = 0.0

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

    override init(size: CGSize) {
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
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: snapshot

    func loadSnapshot(_ image: CGImage, appName: String, windows: [WindowInfo]) {
        self.appName = appName
        if backdrop.size != size {
            backdrop.texture = Backdrop.texture(size: size)
            backdrop.size = size
        }
        canvas?.node.removeFromParent()
        let c = Canvas(image: image, pointSize: size)
        canvas = c
        canvasRoot.addChild(c.node)
        lastTime = 0
    }

    func didPause() {
        keysDown.removeAll()
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
        while acc >= fixedDT, steps < 8 {
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
    }

    func frameUpdate(_ dt: Double) {}

    // MARK: input

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { app?.pause(); return } // Esc
        keysDown.insert(e.keyCode)
    }

    override func keyUp(with e: NSEvent) { keysDown.remove(e.keyCode) }
    override func mouseMoved(with e: NSEvent) { mouse = e.location(in: self) }
    override func mouseDragged(with e: NSEvent) { mouse = e.location(in: self) }
}
