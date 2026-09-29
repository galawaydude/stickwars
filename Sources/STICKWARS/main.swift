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
if args.contains("--selfcheck") {
    exit(SelfCheck.run() ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate(dev: args.contains("--dev"))
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
