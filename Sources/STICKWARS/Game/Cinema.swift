import SpriteKit

/// Slow-motion "shots": time slows, the camera pushes in on the moment, letterbox bars slide in,
/// and audio drops in pitch. Everything eases back to normal on its own.
final class Cinema {
    let cam = SKCameraNode()
    private(set) var timeScale: CGFloat = 1
    private var target: CGFloat = 1
    private var until = 0.0           // real time the shot ends
    private var cooldownUntil = 0.0
    private var clock = 0.0           // real (unscaled) time
    private var zoom: CGFloat = 1, zoomTarget: CGFloat = 1
    private var focus = CGPoint.zero
    let barTop = SKSpriteNode(texture: Tex.white), barBottom = SKSpriteNode(texture: Tex.white)
    let flash = SKSpriteNode(texture: Tex.white)
    /// Fade-to-black for the end of demo reels.
    let blackout = SKSpriteNode(texture: Tex.white)
    let size: CGSize

    init(size: CGSize) {
        self.size = size
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        focus = cam.position
        for b in [barTop, barBottom] {
            b.color = .black; b.colorBlendFactor = 1
            b.size = CGSize(width: size.width + 40, height: 60)
            b.zPosition = -5
        }
        barTop.anchorPoint = CGPoint(x: 0.5, y: 0); barBottom.anchorPoint = CGPoint(x: 0.5, y: 1)
        flash.size = CGSize(width: size.width + 40, height: size.height + 40)
        flash.color = .white; flash.colorBlendFactor = 1; flash.alpha = 0; flash.zPosition = -4
        flash.anchorPoint = .zero; flash.position = CGPoint(x: -20, y: -20)   // cover the whole screen
        flash.blendMode = .add
        blackout.size = flash.size; blackout.anchorPoint = .zero; blackout.position = CGPoint(x: -20, y: -20)
        blackout.color = .black; blackout.colorBlendFactor = 1; blackout.alpha = 0; blackout.zPosition = 50
    }

    var active: Bool { clock < until }

    /// Starts a slow-motion shot of `duration` real seconds focused on `at`.
    func slowMo(_ duration: Double, scale: CGFloat = 0.3, at: CGPoint, zoom z: CGFloat = 1.3, force: Bool = false) {
        guard force || clock >= cooldownUntil else { return }
        until = clock + duration
        cooldownUntil = until + 2.5
        target = scale
        zoomTarget = z
        focus = at
    }

    func impactFlash(_ strength: CGFloat = 0.35) { flash.alpha = max(flash.alpha, strength) }

    /// Director camera (demo reels): framing used between slow-mo shots. Default = whole screen.
    var baseZoom: CGFloat = 1
    var baseFocus: CGPoint?
    /// Constant film letterbox height (demo reels).
    var filmBars: CGFloat = 0
    private var camPos: CGPoint?

    /// Advances with the real frame time; returns the time scale to apply to the simulation.
    func update(_ realDt: Double) -> CGFloat {
        clock += realDt
        let dt = CGFloat(realDt)
        let ending = clock >= until
        let wantScale: CGFloat = ending ? 1 : target
        let wantZoom: CGFloat = ending ? baseZoom : zoomTarget
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let wantFocus = ending ? (baseFocus ?? center) : focus
        // snap into slow-mo quickly, ease out of it
        timeScale += (wantScale - timeScale) * (1 - exp(-(ending ? 5 : 18) * dt))
        if abs(timeScale - 1) < 0.01 && ending { timeScale = 1 }
        zoom += (wantZoom - zoom) * (1 - exp(-(ending ? 3 : 7) * dt))
        if abs(zoom - wantZoom) < 0.002 && ending { zoom = wantZoom }
        let s = 1 / zoom
        cam.setScale(s)
        // ease the camera toward its focus, keeping the view inside the screen
        var p = camPos ?? center
        p = p + (wantFocus - p) * (1 - exp(-(ending ? 3.2 : 8) * dt))
        if zoom <= 1.0005 && baseFocus == nil { p = center }
        camPos = p
        let halfW = size.width * s / 2, halfH = size.height * s / 2
        cam.position = CGPoint(x: clamp(p.x, halfW, size.width - halfW), y: clamp(p.y, halfH, size.height - halfH))
        // letterbox
        let bar = max(filmBars, 56 * clamp((zoom - max(1, baseZoom)) / 0.25, 0, 1))
        barTop.position = CGPoint(x: size.width / 2, y: size.height - bar)
        barBottom.position = CGPoint(x: size.width / 2, y: bar)
        barTop.isHidden = bar < 0.5; barBottom.isHidden = bar < 0.5
        flash.alpha = max(0, flash.alpha - dt * 5)
        Audio.shared.rate = Float(0.5 + 0.5 * timeScale)
        return timeScale
    }

    var zoomed: Bool { zoom > 1.001 }

    func reset() {
        until = 0; timeScale = 1; zoom = 1; target = 1; camPos = nil
        cam.setScale(1)
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        barTop.isHidden = true; barBottom.isHidden = true
        flash.alpha = 0
        blackout.alpha = 0
        Audio.shared.rate = 1
    }
}
