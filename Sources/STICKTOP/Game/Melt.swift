import SpriteKit

/// DOOM-style screen melt. The current frame is frozen into thin columns that slide down with
/// staggered, accelerating starts (out), or fall into place from above (in). The simulation and
/// physics are frozen meanwhile, so everyone stays exactly where they were.
extension GameScene {
    var melting: Bool { meltDone != nil }

    func startMelt(out: Bool, done: @escaping () -> Void) {
        meltRoot.isHidden = true
        guard let tex = view?.texture(from: self) else { done(); return }
        tex.filteringMode = .nearest
        meltRoot.removeAllChildren()
        meltCols.removeAll(keepingCapacity: true)
        meltDelay.removeAll(keepingCapacity: true)
        let cw: CGFloat = 6
        let n = Int((size.width / cw).rounded(.up))
        var d = rng.range(0, 0.1)
        for i in 0..<n {
            // neighbouring columns start close together, like the original's random walk
            d = clamp(d + rng.range(-0.022, 0.022), 0, 0.3)
            let x0 = CGFloat(i) * cw, w = min(cw, size.width - x0)
            let sub = SKTexture(rect: CGRect(x: x0 / size.width, y: 0, width: w / size.width, height: 1), in: tex)
            sub.filteringMode = .nearest
            let s = SKSpriteNode(texture: sub, size: CGSize(width: w, height: size.height))
            s.anchorPoint = .zero
            s.position = CGPoint(x: x0, y: out ? 0 : size.height)
            meltRoot.addChild(s)
            meltCols.append(s)
            meltDelay.append(CGFloat(d))
        }
        meltRoot.isHidden = false
        for layer in [backdrop, canvasRoot, physicsRoot, world, hudRoot] { layer.isHidden = true }
        backgroundColor = out ? .clear : SKColor(white: 0, alpha: 0.55)
        physicsWorld.speed = 0
        meltOut = out
        meltT = 0
        meltDone = done
        Audio.shared.play(.melt, volume: 0.6)
    }

    func updateMelt(_ dt: Double) {
        meltT += CGFloat(min(dt, 1.0 / 30))
        var finished = true
        let H = size.height
        for i in 0..<meltCols.count {
            let t = meltT - meltDelay[i]
            let fall = t > 0 ? 700 * t + 3200 * t * t : 0
            let y = meltOut ? -fall : max(0, H - fall)
            if meltOut ? y > -H : y > 0 { finished = false }
            meltCols[i].position.y = y.rounded()
        }
        guard finished, let done = meltDone else { return }
        meltDone = nil
        meltRoot.removeAllChildren()
        meltCols.removeAll(keepingCapacity: true)
        for layer in [backdrop, canvasRoot, physicsRoot, world, hudRoot] { layer.isHidden = false }
        backgroundColor = .black
        physicsWorld.speed = 1
        resetClock()
        done()
    }
}
