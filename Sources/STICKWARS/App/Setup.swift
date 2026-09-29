import AppKit
import ApplicationServices
import ServiceManagement

/// First-run / permissions window: live status for Screen Recording and Accessibility, buttons that
/// jump straight to the right Settings pane, a relaunch button (Screen Recording only takes effect
/// after a relaunch), open-at-login, and Play.
final class SetupWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var timer: Timer?
    private let onPlay: () -> Void
    private let screenIcon = NSImageView(), axIcon = NSImageView()
    private let screenButton = NSButton(), axButton = NSButton()
    private let relaunchBox = NSStackView()
    private let playButton = NSButton()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let loginCheck = NSButton(checkboxWithTitle: "Open STICKWARS at login", target: nil, action: nil)
    /// Set once the user asked for Screen Recording in this run: the grant needs a relaunch.
    private var requestedScreen = false

    static var screenGranted: Bool { CGPreflightScreenCaptureAccess() }
    static var axGranted: Bool { AXIsProcessTrusted() }

    init(onPlay: @escaping () -> Void) {
        self.onPlay = onPlay
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470), styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "STICKWARS Setup"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = build()
        fit()
        window.center()
    }

    func show(notice text: String? = nil) {
        notice.stringValue = text ?? ""
        notice.isHidden = text == nil
        fit()
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        // Poll only while the window is open (Accessibility updates live; Screen Recording after relaunch).
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    var isVisible: Bool { window.isVisible }

    /// Dev: renders the window content to a PNG without putting it on screen.
    func snapshot(_ path: String) {
        window.appearance = NSAppearance(named: .aqua)
        refresh()
        guard let v = window.contentView else { return }
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil }

    // MARK: layout

    private func label(_ s: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.isSelectable = false
        return l
    }

    private func row(icon: NSImageView, title: String, detail: String, button: NSButton, action: Selector) -> NSView {
        icon.symbolConfiguration = .init(pointSize: 22, weight: .regular)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let text = NSStackView(views: [label(title, weight: .semibold), label(detail, size: 12, color: .secondaryLabelColor)])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 2
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.bezelStyle = .rounded
        button.target = self; button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
        let r = NSStackView(views: [icon, text, button])
        r.orientation = .horizontal; r.alignment = .centerY; r.spacing = 12
        return r
    }

    private func build() -> NSView {
        let logo = NSImageView(image: AppIcon.nsImage)
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.widthAnchor.constraint(equalToConstant: 84).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 84).isActive = true
        let titles = NSStackView(views: [label("STICKWARS", size: 26, weight: .heavy),
                                         label("Freeze any screen into a level and wreck it in a stickman gunfight.", color: .secondaryLabelColor)])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 4
        let header = NSStackView(views: [logo, titles])
        header.spacing = 16; header.alignment = .centerY

        let screenRow = row(icon: screenIcon, title: "Screen Recording (required)",
                            detail: "Takes one still picture of your screen to build the level. Nothing is saved or sent anywhere.",
                            button: screenButton, action: #selector(grantScreen))
        let axRow = row(icon: axIcon, title: "Accessibility (recommended)",
                        detail: "Reads where buttons and text are, so fighters stand exactly on them. Never controls your apps.",
                        button: axButton, action: #selector(grantAX))

        let relaunchText = label("Turned on Screen Recording? macOS applies it after STICKWARS restarts.", size: 12, color: .systemOrange)
        let relaunch = NSButton(title: "Relaunch STICKWARS", target: self, action: #selector(relaunchApp))
        relaunch.bezelStyle = .rounded
        relaunchBox.setViews([relaunchText, relaunch], in: .leading)
        relaunchBox.orientation = .horizontal; relaunchBox.spacing = 12; relaunchBox.alignment = .centerY

        loginCheck.target = self; loginCheck.action = #selector(toggleLogin)
        let hint = label("Play anytime with ⌥⇧F.  Esc pauses and gives your desktop back.", size: 12, color: .secondaryLabelColor)
        playButton.title = "Play Now"
        playButton.bezelStyle = .rounded
        playButton.keyEquivalent = "\r"
        playButton.target = self; playButton.action = #selector(play)
        let footer = NSStackView(views: [loginCheck, NSView(), playButton])
        footer.orientation = .horizontal; footer.alignment = .centerY

        let box = NSBox(); box.boxType = .separator
        notice.font = .systemFont(ofSize: 12, weight: .semibold)
        notice.textColor = .systemRed
        notice.isHidden = true
        let stack = NSStackView(views: [header, box, notice, screenRow, axRow, relaunchBox, hint, footer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        for v in [box, notice, screenRow, axRow, footer] { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true }
        return stack
    }

    // MARK: state

    private func setStatus(_ icon: NSImageView, _ button: NSButton, ok: Bool, pending: Bool = false) {
        icon.image = NSImage(systemSymbolName: ok ? "checkmark.circle.fill" : pending ? "clock.fill" : "exclamationmark.circle.fill",
                             accessibilityDescription: nil)
        icon.contentTintColor = ok ? .systemGreen : pending ? .systemOrange : .systemRed
        button.title = ok ? "Granted" : pending ? "Open Settings" : "Grant Access"
        button.isEnabled = !ok
    }

    /// Sizes the window to its content (the relaunch row comes and goes).
    private func fit() {
        guard let v = window.contentView else { return }
        v.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 560, height: v.fittingSize.height))
    }

    private func refresh() {
        let screen = SetupWindow.screenGranted, ax = SetupWindow.axGranted
        setStatus(screenIcon, screenButton, ok: screen, pending: requestedScreen)
        setStatus(axIcon, axButton, ok: ax)
        let hideRelaunch = screen || (!requestedScreen && notice.isHidden)
        if relaunchBox.isHidden != hideRelaunch { relaunchBox.isHidden = hideRelaunch; fit() }
        playButton.isEnabled = screen
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: actions

    @objc private func grantScreen() {
        // The first request shows the system prompt and adds STICKWARS to the Settings list.
        if !requestedScreen { _ = CGRequestScreenCaptureAccess() }
        requestedScreen = true
        openPane("Privacy_ScreenCapture")
        refresh()
    }

    @objc private func grantAX() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) { openPane("Privacy_Accessibility") }
        refresh()
    }

    private func openPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    @objc private func relaunchApp() {
        // Start a fresh copy shortly after we quit (the hotkey can only belong to one process).
        let path = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            SMAppService.openSystemSettingsLoginItems()
        }
        refresh()
    }

    @objc private func play() {
        window.close()
        // let the window disappear before the snapshot is taken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [onPlay] in onPlay() }
    }
}
