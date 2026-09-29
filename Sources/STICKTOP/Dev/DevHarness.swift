import AppKit
import ApplicationServices
import ImageIO
import SpriteKit
import UniformTypeIdentifiers

/// Headless test driver. `kill -USR1 <pid>` runs the commands in /tmp/sticktop-cmd.txt and writes
/// results to /tmp/sticktop-out.txt (ending with "DONE"). SIGUSR2 quits. Never shows the window.
final class DevHarness {
    static let cmdPath = "/tmp/sticktop-cmd.txt", outPath = "/tmp/sticktop-out.txt"
    private unowned let app: AppDelegate
    private var sources: [DispatchSourceSignal] = []
    private var fake: CGImage?
    private var renderer: SKRenderer?
    private var vt = now()
    private var busy = false

    init(app: AppDelegate) {
        self.app = app
        for sig in [SIGUSR1, SIGUSR2] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { [weak self] in
                if sig == SIGUSR2 { NSApp.terminate(nil) } else { self?.run() }
            }
            s.resume()
            sources.append(s)
        }
        try? "READY \(getpid())\n".write(toFile: DevHarness.outPath, atomically: true, encoding: .utf8)
        print("STICKTOP dev harness ready, pid \(getpid())")
    }

    private var scene: GameScene { app.scene }

    private func run() {
        guard !busy, let text = try? String(contentsOfFile: DevHarness.cmdPath, encoding: .utf8) else { return }
        busy = true
        Task { @MainActor in
            var out = ""
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ").map(String.init)
                guard let cmd = parts.first else { continue }
                out += "> \(line)\n"
                out += await self.exec(cmd, Array(parts.dropFirst())) + "\n"
            }
            out += "DONE\n"
            try? out.write(toFile: DevHarness.outPath, atomically: true, encoding: .utf8)
            self.busy = false
        }
    }

    private func num(_ a: [String], _ i: Int, _ d: CGFloat = 0) -> CGFloat { i < a.count ? CGFloat(Double(a[i]) ?? Double(d)) : d }

    @MainActor private func exec(_ cmd: String, _ a: [String]) async -> String {
        switch cmd {
        case "fake":
            fake = FakePage.image(size: scene.size)
            return "fake \(fake!.width)x\(fake!.height)"
        case "play":
            if let img = fake {
                app.start(image: img, appName: "Safari", windows: FakePage.windows(size: scene.size), headless: true)
            } else {
                do {
                    let img = try await ScreenCapture.capture()
                    app.start(image: img, appName: "Screen", windows: ScreenCapture.windowList(), headless: true)
                } catch { return "capture failed: \(error)" }
            }
            let t0 = now()
            while scene.extracting, now() - t0 < 3 { try? await Task.sleep(nanoseconds: 5_000_000) }
            return "playing (headless) extraction \(String(format: "%.1f", scene.extractMs)) ms"
        case "pause":
            app.pause(); return "paused"
        case "step":
            // yield regularly so background results (nav graph) land like they would between frames
            var left = Int(num(a, 0, 1))
            while left > 0 {
                let k = min(12, left); step(k); left -= k
                try? await Task.sleep(nanoseconds: 200_000)
            }
            return "stepped \(Int(num(a, 0, 1)))"
        case "perf":
            let n = Int(num(a, 0, 240))
            return perf(n)
        case "perfblast":
            // perf with an explosion every 30 frames and SMG fire from the player
            let n = Int(num(a, 0, 240))
            return perf(n) { [unowned self] k in
                if k % 30 == 0 { _ = self.scene.devCommand("blast", ["\(Int.random(in: 100...1400))", "\(Int.random(in: 100...900))", "70"]) }
                if k % 6 == 0 { _ = self.scene.devCommand("shoot", ["\(Int.random(in: 0...1500))", "\(Int.random(in: 0...900))", "\(Int.random(in: 0...1500))", "\(Int.random(in: 0...900))"]) }
            }
        case "snap":
            let lines = a.contains("lines")
            let path = a.first(where: { $0.hasPrefix("/") }) ?? "/tmp/sticktop-snap.png"
            return snap(path, lines: lines)
        case "state":
            let ax = AXIsProcessTrusted(), sc = CGPreflightScreenCaptureAccess()
            return "screenRecording=\(sc) accessibility=\(ax) appActive=\(NSApp.isActive) windowKey=\(app.window.isKeyWindow) windowVisible=\(app.window.isVisible) viewPaused=\(app.skView.isPaused) playing=\(app.playing)\n" + scene.stateDump()
        case "key":
            let code = UInt16(num(a, 0)); let down = a.count < 2 || a[1] == "down"
            scene.setKey(code, down); return "key \(code) \(down)"
        default:
            return scene.devCommand(cmd, a) ?? "unknown command \(cmd)"
        }
    }

    /// Drives scene.update (and SpriteKit physics) manually at 120 Hz; works with the display asleep.
    private func step(_ n: Int) {
        if renderer == nil {
            renderer = SKRenderer(device: MTLCreateSystemDefaultDevice()!)
            renderer!.scene = scene
        }
        scene.isPaused = false
        for _ in 0..<n {
            vt += 1.0 / 120
            renderer!.update(atTime: vt)
        }
    }

    private func perf(_ n: Int, each: ((Int) -> Void)? = nil) -> String {
        step(1)
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue() else { return "no metal" }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(scene.size.width * 2),
                                                            height: Int(scene.size.height * 2), mipmapped: false)
        desc.usage = [.renderTarget]
        let tex = dev.makeTexture(descriptor: desc)!
        var total = 0.0, worst = 0.0, upd = 0.0
        var times: [Double] = []
        for k in 0..<n {
            let t0 = now()
            each?(k)
            vt += 1.0 / 120
            renderer!.update(atTime: vt)
            let t1 = now()
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = tex
            rp.colorAttachments[0].loadAction = .clear
            rp.colorAttachments[0].storeAction = .store
            let cb = q.makeCommandBuffer()!
            renderer!.render(withViewport: CGRect(x: 0, y: 0, width: tex.width, height: tex.height), commandBuffer: cb, renderPassDescriptor: rp)
            cb.commit()
            let dt = (now() - t0) * 1000
            total += dt; worst = max(worst, dt); upd += (t1 - t0) * 1000; times.append(dt)
            cb.waitUntilCompleted()
        }
        times.sort()
        let p95 = times.isEmpty ? 0 : times[min(times.count - 1, times.count * 95 / 100)]
        return String(format: "perf %d frames: avg %.3f ms (update %.3f ms) p95 %.3f worst %.3f ms main-thread CPU", n, total / Double(n), upd / Double(n), p95, worst)
    }

    private func snap(_ path: String, lines: Bool) -> String {
        guard let tex = app.skView.texture(from: scene) else { return "snap failed" }
        var img = tex.cgImage()
        if lines, let ov = scene.debugOverlay(on: img) { img = ov }
        let url = URL(fileURLWithPath: path) as CFURL
        guard let dst = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { return "snap write failed" }
        CGImageDestinationAddImage(dst, img, nil)
        CGImageDestinationFinalize(dst)
        return "snap \(path) \(img.width)x\(img.height)"
    }
}
