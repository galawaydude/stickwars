import AppKit
import SpriteKit

/// Borderless full-screen window above the menu bar and Dock.
final class GameWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        colorSpace = NSColorSpace.sRGB
    }
}

/// SKView that keeps the view's Metal layer in sRGB so copied/erased pixels match the capture exactly.
final class GameView: SKView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (layer as? CAMetalLayer)?.colorspace = sRGB
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }

    // All input goes straight to the game scene (SKView doesn't forward every event type).
    private var game: GameScene? { scene as? GameScene }
    private func point(_ e: NSEvent) -> CGPoint {
        let v = convert(e.locationInWindow, from: nil)
        game?.mouseView = v
        guard let s = scene else { return .zero }
        return s.convertPoint(fromView: v)
    }
    override func keyDown(with e: NSEvent) { game?.key(e.keyCode, down: true, isRepeat: e.isARepeat) }
    override func keyUp(with e: NSEvent) { game?.key(e.keyCode, down: false) }
    override func flagsChanged(with e: NSEvent) { game?.shiftDown = e.modifierFlags.contains(.shift) }
    override func mouseMoved(with e: NSEvent) { game?.mouse = point(e) }
    override func mouseDragged(with e: NSEvent) { game?.mouse = point(e) }
    override func rightMouseDragged(with e: NSEvent) { game?.mouse = point(e) }
    override func mouseDown(with e: NSEvent) { game?.mouse = point(e); game?.mouseButton(true) }
    override func mouseUp(with e: NSEvent) { game?.mouseButton(false) }
    override func rightMouseDown(with e: NSEvent) { game?.mouse = point(e); game?.grenadePressed() }
    override func rightMouseUp(with e: NSEvent) {}
    override func scrollWheel(with e: NSEvent) { game?.scroll(e) }
}
