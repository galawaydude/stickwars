import AppKit
import ApplicationServices
import ServiceManagement
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
    private var lastToggle = 0.0
    private var prevApp: NSRunningApplication?
    private var cursorHidden = false
    private var playItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var setup: SetupWindow?
    private var escMonitor: Any?
    private var watchdogToken = 0

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
        scene.prewarm(in: skView)
        Audio.shared.muted = settings.muted || (dev && !CommandLine.arguments.contains("--audio"))
        Audio.shared.silentTest = dev

        if dev {
            harness = DevHarness(app: self)
        } else {
            NSApp.applicationIconImage = AppIcon.nsImage
            buildMenu()
            hotKey = HotKey.optionShiftF { [weak self] in self?.toggle() }
            // First run, or Screen Recording still missing: the setup window walks through it
            // (instead of surprise system prompts), while nothing covers the screen.
            // It keeps coming back until Screen Recording works and the user has played once, so after
            // macOS's own "Quit & Reopen" it reappears with green checks and Play Now.
            if !SetupWindow.screenGranted || !UserDefaults.standard.bool(forKey: "setupSeen") { showSetup() }
            // Safety: anything else taking focus (a system dialog, Cmd-Tab, a notification click)
            // pauses the game so the overlay never sits on top of something you need.
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.playing else { return }
                self.pause()
            }
            // Esc works even if the keyboard focus got lost (needs Accessibility; harmless without it).
            escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
                if e.keyCode == 53, self?.playing == true { DispatchQueue.main.async { self?.pause() } }
            }
        }
    }

    // MARK: menu

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "figure.boxing", accessibilityDescription: "STICKWARS")
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
        menu.addItem(withTitle: "Setup & Permissions…", action: #selector(menuSetup), keyEquivalent: "").target = self
        let login = NSMenuItem(title: "Open at Login", action: #selector(menuLogin(_:)), keyEquivalent: "")
        login.target = self
        menu.addItem(login); loginItem = login
        menu.delegate = self
        menu.addItem(withTitle: "Quit STICKWARS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuSetup() { showSetup() }
    @objc private func menuLogin(_ s: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { SMAppService.openSystemSettingsLoginItems() }
    }

    func showSetup(notice: String? = nil) {
        if setup == nil { setup = SetupWindow { [weak self] in self?.play() } }
        setup?.show(notice: notice)
    }
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
        guard t - lastToggle > 0.3 else { return }
        lastToggle = t
        if playing { pause() } else { play() }
    }

    func play() {
        guard !playing, !starting else { return }
        guard SetupWindow.screenGranted else { showSetup(); return }
        if setup?.isVisible == true { return }
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
                self.showSetup()
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
        // A blank capture (permission not in effect yet, display asleep...) would cover the screen
        // with a flat colour: never take over the screen with it.
        if !headless && ScreenCapture.isBlank(image) {
            starting = false
            showSetup(notice: "The screenshot came back blank, so the game didn't start. If you just turned on Screen Recording, click Relaunch.")
            return
        }
        scene.loadSnapshot(image, appName: appName, windows: windows)
        if !headless { UserDefaults.standard.set(true, forKey: "setupSeen") }
        playing = true
        starting = false
        playItem?.title = "Pause"
        guard !headless else { return }
        window.setFrame(NSScreen.screens[0].frame, display: false)
        scene.renderedFrames = 0
        skView.isPaused = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(skView)
        armWatchdog()
    }

    /// Watchdog: the game must be drawing and own the keyboard shortly after it appears, otherwise
    /// it gets out of the way instead of leaving an overlay you can't control.
    private func armWatchdog() {
        watchdogToken += 1
        let token = watchdogToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.playing, token == self.watchdogToken else { return }
            if !self.window.isKeyWindow || !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
                self.window.makeKeyAndOrderFront(nil)
                self.window.makeFirstResponder(self.skView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.playing, token == self.watchdogToken else { return }
                if self.scene.renderedFrames < 5 {
                    self.emergencyExit("The game didn't start drawing, so it stepped aside. Try ⌥⇧F again.")
                } else if !self.window.isKeyWindow {
                    self.emergencyExit("STICKWARS couldn't get keyboard focus, so it stepped aside. Try ⌥⇧F again.")
                }
            }
        }
    }

    /// Called by the scene once real frames are on screen: only now hide the cursor.
    func framesOnScreen() {
        guard playing, !cursorHidden, window.isVisible else { return }
        NSCursor.hide(); cursorHidden = true
    }

    private func emergencyExit(_ why: String) {
        pause()
        showSetup(notice: why)
    }

    func pause() {
        guard playing else { return }
        playing = false
        watchdogToken += 1
        playItem?.title = "Play"
        skView.isPaused = true
        scene.didPause()
        Audio.shared.stopAll()
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        if window.isVisible {
            window.orderOut(nil)
            prevApp?.activate()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off }
}
