import ApplicationServices
import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--make-icon"), i + 1 < args.count {
    do { try AppIcon.writeIconset(URL(fileURLWithPath: args[i + 1])); exit(0) } catch { print(error); exit(1) }
}
if let i = args.firstIndex(of: "--setup-snapshot"), i + 1 < args.count {
    _ = NSApplication.shared
    SetupWindow(onPlay: {}).snapshot(args[i + 1])
    exit(0)
}
if args.contains("--capture-test") {
    // Diagnostics: one capture, stats only (no window, nothing kept), then quit.
    _ = NSApplication.shared
    Task {
        var out = "screenRecording=\(CGPreflightScreenCaptureAccess()) accessibility=\(AXIsProcessTrusted())\n"
        do {
            let t0 = now()
            let img = try await ScreenCapture.capture()
            out += String(format: "capture %dx%d in %.0f ms bpc=%d blank=%@\n", img.width, img.height, (now() - t0) * 1000, img.bitsPerComponent,
                          ScreenCapture.isBlank(img) ? "YES" : "no")
        } catch { out += "capture error: \(error)\n" }
        try? out.write(toFile: "/tmp/stickwars-capture-test.txt", atomically: true, encoding: .utf8)
        exit(0)
    }
    RunLoop.main.run()
}
if args.contains("--selfcheck") {
    exit(SelfCheck.run() ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate(dev: args.contains("--dev"))
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
