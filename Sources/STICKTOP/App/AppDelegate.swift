import AppKit
import ApplicationServices
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Dev mode: no status item, hotkey or permission prompts; driven by the harness only.
    let dev: Bool
    var settings = Settings()
    private(set) var window: GameWindow!
    private(set) var skView: GameView!
    private(set) var scene: GameScene!
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var harness: DevHarness?
    private(set) var playing = false
    private var starting = false
    private var transitioning = false
    private var lastToggle = 0.0
    private var prevApp: NSRunningApplication?
    private var cursorHidden = false
    private var playItem: NSMenuItem?

    init(dev: Bool) { self.dev = dev }

    func applicationDidFinishLaunching(_ note: Notification) {
        let frame = NSScreen.screens[0].frame
        window = GameWindow(frame: frame)
        skView = GameView(frame: NSRect(origin: .zero, size: frame.size))
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = max(60, NSScreen.screens[0].maximumFramesPerSecond)
        skView.isAsynchronous = true
        skView.allowsTransparency = false
        window.contentView = skView
        scene = GameScene(size: frame.size)
        scene.app = self
        skView.presentScene(scene)
        skView.isPaused = true
        Audio.shared.muted = settings.muted || dev

        if dev {
            harness = DevHarness(app: self)
        } else {
            buildMenu()
            hotKey = HotKey.optionShiftF { [weak self] in self?.toggle() }
            // Ask now, while nothing covers the screen. Grants apply after relaunch.
            if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
            if !AXIsProcessTrusted() {
                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(opts)
            }
        }
    }

    // MARK: menu

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "figure.boxing", accessibilityDescription: "STICKTOP")
        let menu = NSMenu()
        menu.autoenablesItems = false
        let play = NSMenuItem(title: "Play", action: #selector(menuToggle), keyEquivalent: "f")
        play.keyEquivalentModifierMask = [.option, .shift]
        play.target = self
        menu.addItem(play); playItem = play
        menu.addItem(withTitle: "New Match", action: #selector(menuNewMatch), keyEquivalent: "").target = self

        let bots = NSMenu()
        for n in 0...5 {
            let b = NSMenuItem(title: "\(n)", action: #selector(menuBots(_:)), keyEquivalent: "")
            b.tag = n; b.target = self; b.state = n == settings.bots ? .on : .off
            bots.addItem(b)
        }
        let botsItem = NSMenuItem(title: "Bots", action: nil, keyEquivalent: ""); botsItem.submenu = bots
        menu.addItem(botsItem)

        let diff = NSMenu()
        for d in Difficulty.allCases {
            let b = NSMenuItem(title: d.title, action: #selector(menuDifficulty(_:)), keyEquivalent: "")
            b.tag = d.rawValue; b.target = self; b.state = d == settings.difficulty ? .on : .off
            diff.addItem(b)
        }
        let diffItem = NSMenuItem(title: "Difficulty", action: nil, keyEquivalent: ""); diffItem.submenu = diff
        menu.addItem(diffItem)

        let mute = NSMenuItem(title: "Mute", action: #selector(menuMute(_:)), keyEquivalent: "")
        mute.target = self; mute.state = settings.muted ? .on : .off
        menu.addItem(mute)

        menu.addItem(.separator())
        for line in ["A / D  move", "W / Space  jump (double, wall)", "S  drop through / fast fall", "Shift  jetpack",
                     "Mouse  aim · click fire", "Right click  grenade", "1–7 / scroll  weapon · R reload", "Esc / ⌥⇧F  pause · F3 debug"] {
            let i = NSMenuItem(title: line, action: nil, keyEquivalent: ""); i.isEnabled = false
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit STICKTOP", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuNewMatch() { scene.newMatch(); if !playing { play() } }
    @objc private func menuBots(_ s: NSMenuItem) {
        settings.bots = s.tag
        s.menu?.items.forEach { $0.state = $0.tag == s.tag ? .on : .off }
        scene.newMatch()
    }
    @objc private func menuDifficulty(_ s: NSMenuItem) {
        settings.difficulty = Difficulty(rawValue: s.tag) ?? .normal
        s.menu?.items.forEach { $0.state = $0.tag == s.tag ? .on : .off }
    }
    @objc private func menuMute(_ s: NSMenuItem) {
        settings.muted.toggle()
        s.state = settings.muted ? .on : .off
        Audio.shared.muted = settings.muted
    }

    // MARK: play / pause

    func toggle() {
        let t = now()
        guard t - lastToggle > 0.3, !transitioning else { return }
        lastToggle = t
        if playing { pause() } else { play() }
    }

    func play() {
        guard !playing, !starting else { return }
        guard CGPreflightScreenCaptureAccess() else { showPermissionAlert(); return }
        starting = true
        let front = NSWorkspace.shared.frontmostApplication
        prevApp = front?.processIdentifier == getpid() ? nil : front
        let name = prevApp?.localizedName ?? "Desktop"
        let windows = ScreenCapture.windowList()
        Task { @MainActor in
            do {
                let img = try await ScreenCapture.capture()
                self.start(image: img, appName: name, windows: windows, headless: false)
            } catch {
                self.starting = false
                self.showPermissionAlert()
            }
        }
    }

    /// Loads the snapshot and (unless headless) takes over the screen with keyboard focus.
    func start(image: CGImage, appName: String, windows: [WindowInfo], headless: Bool) {
        // Screen resolution changed since the scene was built: start over at the new size.
        let size = NSScreen.screens[0].frame.size
        if scene.size != size {
            skView.frame = NSRect(origin: .zero, size: size)
            scene = GameScene(size: size)
            scene.app = self
            skView.presentScene(scene)
        }
        scene.loadSnapshot(image, appName: appName, windows: windows)
        playing = true
        starting = false
        playItem?.title = "Pause"
        guard !headless else { return }
        window.setFrame(NSScreen.screens[0].frame, display: false)
        setTransparent(true)
        transitioning = true
        // Melt the new frame in over the (dimmed) desktop; the fight resumes when it lands.
        scene.startMelt(out: false) { [weak self] in
            self?.setTransparent(false)
            self?.transitioning = false
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(skView)
        skView.isPaused = false
        if !cursorHidden { NSCursor.hide(); cursorHidden = true }
    }

    /// See-through window while a melt shows the desktop behind it.
    private func setTransparent(_ on: Bool) {
        skView.allowsTransparency = on
        window.isOpaque = !on
        window.backgroundColor = on ? .clear : .black
    }

    func pause() {
        guard playing, !transitioning else { return }
        playing = false
        playItem?.title = "Play"
        Audio.shared.stopAll()
        scene.didPause()
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        guard window.isVisible else { skView.isPaused = true; return }
        // Freeze everyone where they are and melt the frame away, DOOM style.
        transitioning = true
        window.ignoresMouseEvents = true
        setTransparent(true)
        prevApp?.activate()
        scene.startMelt(out: true) { [weak self] in
            guard let self else { return }
            self.skView.isPaused = true
            self.window.orderOut(nil)
            self.window.ignoresMouseEvents = false
            self.setTransparent(false)
            self.transitioning = false
        }
    }

    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "STICKTOP needs Screen Recording permission"
        a.informativeText = "STICKTOP turns a still picture of your screen into the level. It never saves or sends the picture anywhere.\n\nEnable STICKTOP under System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen STICKTOP (macOS applies the grant after a relaunch)."
        a.addButton(withTitle: "Open System Settings")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
