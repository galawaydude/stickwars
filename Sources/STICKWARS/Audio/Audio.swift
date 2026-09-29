import AVFoundation

enum Sound: Int, CaseIterable {
    case pistol, smg, shotgun, rocket, plasma, blaster, charge, laser, explosion, shatter, pop, jump, land, hit, kill,
         pickup, blip, reload, empty, grenade, bounce, portal, win, death, blackhole, collapse, saw, grind, zap, slash, clank
}

/// Synthesized sounds played through a round-robin pool of player nodes. The only singleton.
final class Audio {
    static let shared = Audio()
    var muted = false
    /// Dev: run the whole audio path at zero volume (for crash testing without noise).
    var silentTest = false
    private let sr: Double = 44100
    /// Set while recording a demo reel: sounds are captured with this clock's timestamps.
    var captureClock: (() -> Double)?
    private(set) var captured: [(Sound, Float, Float, Double)] = []
    private var lastCapture = [Double](repeating: -1, count: Sound.allCases.count)
    private var engine: AVAudioEngine?
    private var varispeed: AVAudioUnitVarispeed?
    /// Playback rate (slow-motion lowers pitch and speed together).
    var rate: Float = 1 { didSet { if abs(rate - oldValue) > 0.005 { varispeed?.rate = rate } } }
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [AVAudioPCMBuffer] = []
    private var lastStart = [Double](repeating: 0, count: Sound.allCases.count)
    private var next = 0
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!

    private func setup() -> Bool {
        if engine != nil { return true }
        let e = AVAudioEngine()
        // players -> submix -> varispeed -> main mixer (varispeed has a single input bus)
        let sub = AVAudioMixerNode()
        let vs = AVAudioUnitVarispeed()
        e.attach(sub); e.attach(vs)
        e.connect(sub, to: vs, format: format)
        e.connect(vs, to: e.mainMixerNode, format: format)
        for _ in 0..<14 {
            let p = AVAudioPlayerNode()
            e.attach(p)
            e.connect(p, to: sub, format: format)
            players.append(p)
        }
        varispeed = vs
        e.mainMixerNode.outputVolume = silentTest ? 0 : 0.55
        buffers = Sound.allCases.map { buffer(synth($0)) }
        do { try e.start() } catch { return false }
        engine = e
        // output device changed (headphones, AirPlay...): the engine stops; start it again
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { _ in
            if !e.isRunning { try? e.start() }
        }
        return true
    }

    /// Pan is -1...1. Repeats of the same sound are throttled to one start per 35 ms.
    func play(_ s: Sound, volume: Float = 1, pan: Float = 0) {
        // Demo recording: log the sound on the video clock instead of playing it.
        if let clock = captureClock {
            let t = clock()
            if t - lastCapture[s.rawValue] > 0.035 { lastCapture[s.rawValue] = t; captured.append((s, volume, pan, t)) }
            return
        }
        guard !muted else { return }
        let t = now()
        guard t - lastStart[s.rawValue] > 0.035 else { return }
        lastStart[s.rawValue] = t
        guard setup(), let e = engine, e.isRunning else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.volume = volume
        p.pan = max(-1, min(1, pan))
        p.scheduleBuffer(buffers[s.rawValue], at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
    }

    func stopAll() { players.forEach { $0.stop() } }

    /// Synthesizes every sound without playing anything; returns length and peak per sound (dev check).
    func synthCheck() -> String {
        Sound.allCases.map { snd in
            let d = synth(snd)
            let peak = d.reduce(0) { max($0, abs($1)) }
            let bad = d.contains { !$0.isFinite }
            return String(format: "%@ %.2fs peak %.2f%@", "\(snd)", Double(d.count) / sr, peak, bad ? " NAN" : "")
        }.joined(separator: ", ")
    }

    // MARK: synthesis

    private func buffer(_ data: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count))!
        b.frameLength = AVAudioFrameCount(data.count)
        data.withUnsafeBufferPointer { src in b.floatChannelData![0].update(from: src.baseAddress!, count: data.count) }
        return b
    }

    private var seed: UInt32 = 12345
    private func white() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 23) - 1 }

    /// One-pole low-passed noise with exponential decay.
    private func noise(_ dur: Double, cutoff: Float, decay: Float, gain: Float = 1) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n), y: Float = 0
        let a = min(1, cutoff)
        for i in 0..<n {
            y += a * (white() - y)
            let t = Float(i) / Float(sr)
            out[i] = y * exp(-t * decay) * gain
        }
        return out
    }

    /// Frequency sweep f0 -> f1 (exponential), decaying. wave: 0 sine, 1 square, 2 saw.
    private func sweep(_ dur: Double, _ f0: Float, _ f1: Float, decay: Float, wave: Int = 0, gain: Float = 1) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n), ph: Float = 0
        for i in 0..<n {
            let u = Float(i) / Float(n)
            let f = f0 * pow(f1 / f0, u)
            ph += f / Float(sr)
            ph -= floor(ph)
            let v: Float = wave == 0 ? sin(ph * 2 * .pi) : wave == 1 ? (ph < 0.5 ? 1 : -1) : ph * 2 - 1
            out[i] = v * exp(-Float(i) / Float(sr) * decay) * gain
        }
        return out
    }

    private func mix(_ parts: [Float]...) -> [Float] {
        let n = parts.map(\.count).max() ?? 0
        var out = [Float](repeating: 0, count: n)
        for p in parts { for i in 0..<p.count { out[i] += p[i] } }
        // soft clip + short attack ramp to avoid clicks
        for i in 0..<n { out[i] = tanh(out[i]) * min(1, Float(i) / 40) }
        return out
    }

    private func pings(_ count: Int, dur: Double, lo: Float, hi: Float) -> [Float] {
        let n = Int(dur * sr)
        var out = [Float](repeating: 0, count: n)
        for _ in 0..<count {
            let start = Int(abs(white()) * Float(n) * 0.5)
            let f = lo + abs(white()) * (hi - lo)
            let len = min(n - start, Int(0.12 * sr))
            for i in 0..<len {
                out[start + i] += sin(Float(i) / Float(sr) * f * 2 * .pi) * exp(-Float(i) / Float(sr) * 30) * 0.35
            }
        }
        return out
    }

    private func synth(_ s: Sound) -> [Float] {
        switch s {
        case .pistol: return mix(noise(0.14, cutoff: 0.5, decay: 38, gain: 0.9), sweep(0.12, 220, 60, decay: 30, gain: 0.8))
        case .smg: return mix(noise(0.07, cutoff: 0.55, decay: 60, gain: 0.8), sweep(0.06, 260, 90, decay: 50, gain: 0.5))
        case .shotgun: return mix(noise(0.35, cutoff: 0.35, decay: 14, gain: 1.2), sweep(0.25, 140, 40, decay: 16, gain: 1))
        case .rocket: return mix(noise(0.45, cutoff: 0.12, decay: 7, gain: 1), sweep(0.3, 90, 300, decay: 8, wave: 2, gain: 0.25))
        case .plasma: return mix(sweep(0.16, 1400, 300, decay: 20, wave: 1, gain: 0.25), sweep(0.16, 700, 200, decay: 18, gain: 0.5))
        case .blaster: return mix(sweep(0.4, 500, 60, decay: 9, wave: 2, gain: 0.6), noise(0.3, cutoff: 0.25, decay: 12, gain: 0.8))
        case .charge: return sweep(0.25, 200, 900, decay: 3, wave: 1, gain: 0.15)
        case .laser: return mix(sweep(0.3, 2400, 500, decay: 10, gain: 0.5), sweep(0.3, 1200, 250, decay: 10, wave: 1, gain: 0.15))
        case .explosion: return mix(noise(1.0, cutoff: 0.08, decay: 4.5, gain: 1.6), sweep(0.6, 110, 28, decay: 6, gain: 1.2), noise(0.2, cutoff: 0.6, decay: 25, gain: 0.5))
        case .shatter: return mix(pings(18, dur: 0.5, lo: 2200, hi: 7000), noise(0.25, cutoff: 0.9, decay: 18, gain: 0.25))
        case .pop: return sweep(0.06, 700, 1500, decay: 40, gain: 0.45)
        case .jump: return sweep(0.09, 280, 620, decay: 25, gain: 0.35)
        case .land: return mix(sweep(0.08, 130, 50, decay: 40, gain: 0.6), noise(0.06, cutoff: 0.2, decay: 50, gain: 0.4))
        case .hit: return mix(noise(0.06, cutoff: 0.7, decay: 60, gain: 0.6), sweep(0.07, 600, 300, decay: 40, wave: 1, gain: 0.2))
        case .kill: return mix(sweep(0.12, 880, 880, decay: 10, wave: 1, gain: 0.2), sweep(0.35, 660, 220, decay: 6, wave: 1, gain: 0.2))
        case .pickup: return mix(sweep(0.08, 660, 660, decay: 20, wave: 1, gain: 0.2), sweep(0.16, 990, 1320, decay: 12, wave: 1, gain: 0.2))
        case .blip: return sweep(0.05, 900, 900, decay: 40, wave: 1, gain: 0.18)
        case .reload: return mix(noise(0.04, cutoff: 0.9, decay: 90, gain: 0.5), shifted(noise(0.05, cutoff: 0.8, decay: 80, gain: 0.6), by: 0.18))
        case .empty: return noise(0.03, cutoff: 0.9, decay: 120, gain: 0.5)
        case .grenade: return noise(0.18, cutoff: 0.15, decay: 16, gain: 0.5)
        case .bounce: return sweep(0.05, 500, 300, decay: 60, gain: 0.35)
        case .portal: return mix(sweep(0.5, 200, 1200, decay: 4, wave: 1, gain: 0.12), sweep(0.5, 400, 2400, decay: 5, gain: 0.25))
        case .win: return mix(sweep(0.15, 523, 523, decay: 6, wave: 1, gain: 0.2), shifted(sweep(0.15, 659, 659, decay: 6, wave: 1, gain: 0.2), by: 0.15), shifted(sweep(0.4, 784, 784, decay: 4, wave: 1, gain: 0.2), by: 0.3))
        case .blackhole: return mix(sweep(0.9, 420, 50, decay: 2.5, gain: 0.7), noise(0.9, cutoff: 0.05, decay: 2.5, gain: 0.8), sweep(0.9, 1200, 200, decay: 4, wave: 1, gain: 0.08))
        case .collapse: return mix(sweep(0.25, 60, 900, decay: 6, gain: 0.5), shifted(noise(0.8, cutoff: 0.1, decay: 5, gain: 1.4), by: 0.2), shifted(sweep(0.5, 90, 30, decay: 6, gain: 1), by: 0.2))
        case .saw: return mix(sweep(0.3, 900, 1400, decay: 8, wave: 1, gain: 0.18), noise(0.3, cutoff: 0.7, decay: 10, gain: 0.35))
        case .grind: return mix(noise(0.14, cutoff: 0.9, decay: 25, gain: 0.5), sweep(0.14, 2400, 1600, decay: 25, wave: 2, gain: 0.15))
        case .zap: return mix(noise(0.08, cutoff: 0.95, decay: 45, gain: 0.45), sweep(0.08, 1800, 2600, decay: 40, wave: 1, gain: 0.12))
        case .slash: return mix(noise(0.16, cutoff: 0.55, decay: 22, gain: 0.6), sweep(0.14, 1500, 500, decay: 25, gain: 0.25))
        case .clank: return mix(pings(5, dur: 0.35, lo: 900, hi: 2400), noise(0.1, cutoff: 0.8, decay: 40, gain: 0.5))
        case .death: return mix(sweep(0.4, 400, 60, decay: 7, wave: 1, gain: 0.25), noise(0.2, cutoff: 0.3, decay: 20, gain: 0.5))
        }
    }

    private func shifted(_ a: [Float], by sec: Double) -> [Float] {
        [Float](repeating: 0, count: Int(sec * sr)) + a
    }

    // MARK: demo soundtrack

    func resetCapture() { captured.removeAll(); lastCapture = [Double](repeating: -1, count: Sound.allCases.count) }

    /// Mixes the captured sound effects over a synthesized drum-and-bass loop (music plays between
    /// musicFrom and musicTo seconds) and writes a stereo WAV.
    func writeCapture(duration: Double, musicFrom: Double, musicTo: Double, to url: URL) throws {
        let n = Int(duration * sr)
        var L = [Float](repeating: 0, count: n), R = L
        func add(_ buf: [Float], at t: Double, gain: Float, pan: Float) {
            let start = Int(t * sr)
            let gl = gain * sqrt(0.5 * (1 - pan)), gr = gain * sqrt(0.5 * (1 + pan))
            for i in 0..<buf.count where start + i >= 0 && start + i < n { L[start + i] += buf[i] * gl; R[start + i] += buf[i] * gr }
        }
        // music: 128 BPM, A minor progression, kick / snare / hats / bass
        let beat = 60.0 / 128
        let kick = sweep(0.28, 130, 42, decay: 11, gain: 0.9)
        let snare = mix(noise(0.18, cutoff: 0.6, decay: 18, gain: 0.7), sweep(0.1, 220, 160, decay: 30, gain: 0.3))
        let hat = noise(0.04, cutoff: 1, decay: 90, gain: 0.25)
        let roots: [Float] = [110, 87.31, 130.81, 98]   // A2 F2 C3 G2
        var t = musicFrom, step = 0
        while t < musicTo {
            let bar = step / 16, s16 = step % 16
            let fade = Float(min(1, (musicTo - t) / 1.5))
            if s16 % 4 == 0 { add(kick, at: t, gain: 0.55 * fade, pan: 0) }
            if s16 == 4 || s16 == 12 { add(snare, at: t, gain: 0.35 * fade, pan: 0.05) }
            if s16 % 2 == 0 { add(hat, at: t, gain: 0.3 * fade, pan: s16 % 4 == 0 ? -0.3 : 0.3) }
            if s16 % 2 == 0 {
                let f = roots[bar % 4] * ([1, 1, 2, 1, 1.5, 1, 2, 1.5] as [Float])[(s16 / 2) % 8]
                add(sweep(beat / 2 * 0.9, f, f, decay: 5, wave: 2, gain: 0.22), at: t, gain: 0.6 * fade, pan: 0)
            }
            t += beat / 4; step += 1
        }
        // sound effects
        for (snd, vol, pan, at) in captured { add(cached(snd), at: at, gain: vol * 0.8, pan: pan) }
        // soft limiter
        for i in 0..<n { L[i] = tanh(L[i] * 0.9); R[i] = tanh(R[i] * 0.9) }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        L.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: n) }
        R.withUnsafeBufferPointer { buf.floatChannelData![1].update(from: $0.baseAddress!, count: n) }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        try file.write(from: buf)
    }

    private var synthCache: [Int: [Float]] = [:]
    private func cached(_ s: Sound) -> [Float] {
        if let b = synthCache[s.rawValue] { return b }
        let b = synth(s); synthCache[s.rawValue] = b; return b
    }
}
