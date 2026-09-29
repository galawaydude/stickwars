import AppKit

let args = CommandLine.arguments
if args.contains("--selfcheck") {
    exit(SelfCheck.run() ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate(dev: args.contains("--dev"))
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
