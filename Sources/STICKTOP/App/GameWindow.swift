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
}
