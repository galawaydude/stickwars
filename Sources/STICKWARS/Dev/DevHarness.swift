import AppKit
import ApplicationServices
import ImageIO
import SpriteKit
import UniformTypeIdentifiers

/// Headless test driver. `kill -USR1 <pid>` runs the commands in /tmp/stickwars-cmd.txt and writes
/// results to /tmp/stickwars-out.txt (ending with "DONE"). SIGUSR2 quits. Never shows the window.
final class DevHarness {
    static let cmdPath = "/tmp/stickwars-cmd.txt", outPath = "/tmp/stickwars-out.txt"
    private unowned let app: AppDelegate
    private var sources: [DispatchSourceSignal] = []
    private var fake: CGImage?
    private var fakeWindows: [WindowInfo] = []
    private var desk: CGImage?      // last real screenshot (intro card of a demo reel)
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
        print("STICKWARS dev harness ready, pid \(getpid())")
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
            if a.first == "desktop" {
                fake = FakeDesktop.image(size: scene.size); fakeWindows = FakeDesktop.windows(size: scene.size)
            } else {
                fake = FakePage.image(size: scene.size, dark: a.first == "dark"); fakeWindows = FakePage.windows(size: scene.size)
            }
            return "fake \(fake!.width)x\(fake!.height)"
        case "play":
            if let img = fake {
                app.start(image: img, appName: "Safari", windows: fakeWindows, headless: true)
            } else {
                // Real screen (needs the installed app's Screen Recording grant). Optional delay so
                // the user can bring the apps they want to the front first.
                if let d = Double(a.first ?? "") { try? await Task.sleep(nanoseconds: UInt64(d * 1e9)) }
                do {
                    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Desktop"
                    let wins = ScreenCapture.windowList()
                    let img = try await ScreenCapture.capture()
                    fake = img
                    scene.realCaptureInDev = true
                    app.start(image: img, appName: front, windows: wins, headless: true)
                    // later 'play's reuse this snapshot, so several takes can be shot from one capture
                    fakeWindows = wins
                    desk = img
                } catch { return "capture failed: \(error)" }
            }
            let t0 = now()
            while scene.extracting, now() - t0 < 3 { try? await Task.sleep(nanoseconds: 5_000_000) }
            return "playing (headless) extraction \(String(format: "%.1f", scene.extractMs)) ms"
        case "demo":
            // player on autopilot against `n` bots (default 5)
            scene.demo = true
            scene.botOverride = Int(num(a, 0, 5))
            scene.configureFighters()
            if !scene.brains.contains(where: { $0.f === scene.player }) { scene.brains.append(Brain(scene.player)) }
            scene.newMatch()
            scene.startDirector()
            return "demo on, \(scene.fighters.count - 1) bots"
        case "record":
            let path = a.first(where: { $0.hasPrefix("/") }) ?? "/tmp/stickwars-demo.mp4"
            let secs = Double(a.first(where: { Double($0) != nil }) ?? "30") ?? 30
            return await record(path, seconds: secs)
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
            let path = a.first(where: { $0.hasPrefix("/") }) ?? "/tmp/stickwars-snap.png"
            var crop: CGRect?
            if let k = a.firstIndex(of: "crop"), k + 4 < a.count {
                crop = CGRect(x: num(a, k + 1), y: num(a, k + 2), width: num(a, k + 3), height: num(a, k + 4)) // scene points
            }
            return snap(path, lines: lines, crop: crop)
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

    /// Records a demo reel: intro card, `seconds` of autopiloted gameplay, outro card.
    @MainActor private func record(_ path: String, seconds: Double) async -> String {
        let fps = 60, W = 1920, H = Int((1920 * scene.size.height / scene.size.width / 2).rounded()) * 2
        let silent = path + ".video.mp4"
        guard let rec = try? Recorder(path: silent, width: W, height: H, fps: fps) else { return "recorder failed" }
        Audio.shared.resetCapture()
        Audio.shared.captureClock = { Double(rec.frames) / Double(fps) }
        defer { Audio.shared.captureClock = nil }
        if renderer == nil { renderer = SKRenderer(device: MTLCreateSystemDefaultDevice()!); renderer!.scene = scene }
        scene.isPaused = false
        let t0 = now()
        let desk = fake ?? self.desk
        // Intro: the untouched desktop, then the hotkey pops in.
        for i in 0..<Int(1.5 * Double(fps)) {
            let t = CGFloat(i) / CGFloat(fps)
            rec.appendDrawn { ctx in
                if let desk { ctx.interpolationQuality = .high; ctx.draw(desk, in: CGRect(x: 0, y: 0, width: W, height: H)) }
                let k = t < 0.5 ? 0 : min(1, (t - 0.5) / 0.18)
                if i == Int(0.5 * Double(fps)) { Audio.shared.play(.blip, volume: 0.8); Audio.shared.play(.pickup, volume: 0.6) }
                if i == Int(1.3 * Double(fps)) { Audio.shared.play(.portal, volume: 0.8) }
                if k > 0 {
                    let c = CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2)
                    let s = 150 * (0.8 + 0.2 * k) * (t > 1.2 ? 0.92 : 1)
                    ctx.setFillColor(CGColor(gray: 0, alpha: 0.35 * k)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
                    Recorder.drawKey("⌥", center: CGPoint(x: c.x - s * 1.15, y: c.y), size: s, alpha: k)
                    Recorder.drawKey("⇧", center: c, size: s, alpha: k)
                    Recorder.drawKey("F", center: CGPoint(x: c.x + s * 1.15, y: c.y), size: s, alpha: k)
                }
            }
        }
        // Gameplay: showcase weapons on the player's autopilot, a few seconds each.
        // weapon flow: SMG -> shotgun -> rockets -> black hole -> saw -> lightning -> laser
        let showcase = [1, 2, 3, 7, 8, 9, 6]
        let playerBrain = scene.brains.first { $0.f === scene.player }
        let total = Int(seconds * Double(fps))
        var finale = false
        var heroAlive = 0
        for i in 0..<total {
            let sec = Double(i) / Double(fps)
            let slot = showcase[min(showcase.count - 1, Int(max(0, sec - 2.4) / ((seconds - 2.4) / Double(showcase.count))))]
            if playerBrain?.lockedWeapon != slot { playerBrain?.lockedWeapon = slot; scene.player.input.switchTo = slot }
            // closing hero shot: long slow-mo push-in on the hero
            if !finale && sec > seconds - 2.6 && scene.player.alive {
                finale = true
                scene.cinema.slowMo(2.6, scale: 0.22, at: scene.player.center, zoom: 1.6, force: true)
            }
            vt += 1.0 / Double(fps)
            renderer!.update(atTime: vt)
            if scene.player.alive { heroAlive += 1 }
            rec.appendScene(renderer!, keep: i == total - 1)
            if i % 30 == 0 { try? await Task.sleep(nanoseconds: 100_000) } // let background work (nav graph) land
        }
        let musicEnd = Double(rec.frames) / Double(fps)
        Audio.shared.play(.win, volume: 0.9)
        // Outro: fade the last frame to the logo.
        let last = rec.lastFrame
        let icon = AppIcon.image(512)
        for i in 0..<Int(2.6 * Double(fps)) {
            let t = CGFloat(i) / CGFloat(fps)
            let k = min(1, t / 0.6)
            rec.appendDrawn { ctx in
                if let last { ctx.draw(last, in: CGRect(x: 0, y: 0, width: W, height: H)) }
                ctx.setFillColor(CGColor(srgbRed: 0.04, green: 0.03, blue: 0.1, alpha: 0.92 * k)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
                let a = min(1, max(0, (t - 0.3) / 0.5))
                ctx.setAlpha(a)
                let s: CGFloat = 300
                ctx.draw(icon, in: CGRect(x: CGFloat(W) / 2 - s / 2, y: CGFloat(H) / 2 - 20, width: s, height: s))
                ctx.setAlpha(1)
                Recorder.drawText("STICKWARS", size: 84, color: .white, center: CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2 - 70), alpha: a)
                Recorder.drawText("Turn any screen into a stickman battlefield.  ⌥⇧F", size: 28, weight: .medium,
                                  color: NSColor(white: 0.85, alpha: 1), center: CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2 - 140), alpha: a)
                Recorder.drawText("github.com/galawaydude/stickwars", size: 24, weight: .regular,
                                  color: NSColor(srgbRed: 0.55, green: 0.9, blue: 1, alpha: 1), center: CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2 - 190), alpha: a, mono: true)
            }
        }
        await rec.finish()
        // soundtrack: captured effects + beat, muxed with ffmpeg
        let duration = Double(rec.frames) / Double(fps)
        let wav = URL(fileURLWithPath: path + ".audio.wav")
        var muxed = false
        do {
            try Audio.shared.writeCapture(duration: duration, musicFrom: 1.8, musicTo: musicEnd + 1.2, to: wav)
            if let ff = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: { FileManager.default.fileExists(atPath: $0) }) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: ff)
                p.arguments = ["-nostdin", "-y", "-loglevel", "error", "-i", silent, "-i", wav.path, "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", path]
                try p.run(); p.waitUntilExit()
                muxed = p.terminationStatus == 0
            }
        } catch {}
        if muxed { try? FileManager.default.removeItem(atPath: silent); try? FileManager.default.removeItem(at: wav) }
        else { try? FileManager.default.moveItem(atPath: silent, toPath: path) }
        return String(format: "hero alive %.0f%%, kills %d, deaths %d. ", Double(heroAlive) * 100 / Double(max(1, total)), scene.player.kills, scene.player.deaths) + String(format: "recorded %@ (audio %@, %d sounds) ", path, muxed ? "yes" : "no", Audio.shared.captured.count) + String(format: "recorded %@ %dx%d %d frames (%.1f s video) in %.1f s", path, W, H, rec.frames, Double(rec.frames) / Double(fps), now() - t0)
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

    private func snap(_ path: String, lines: Bool, crop: CGRect? = nil) -> String {
        guard let tex = app.skView.texture(from: scene) else { return "snap failed" }
        var img = tex.cgImage()
        if lines, let ov = scene.debugOverlay(on: img) { img = ov }
        if let c = crop {
            let s = CGFloat(img.width) / scene.size.width
            let r = CGRect(x: c.minX * s, y: (scene.size.height - c.maxY) * s, width: c.width * s, height: c.height * s)
            if let cr = img.cropping(to: r) { img = cr }
        }
        let url = URL(fileURLWithPath: path) as CFURL
        guard let dst = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { return "snap write failed" }
        CGImageDestinationAddImage(dst, img, nil)
        CGImageDestinationFinalize(dst)
        return "snap \(path) \(img.width)x\(img.height)"
    }
}
