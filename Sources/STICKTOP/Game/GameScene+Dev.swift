import SpriteKit

extension GameScene {
    func setKey(_ code: UInt16, _ down: Bool) {
        if down { keysDown.insert(code) } else { keysDown.remove(code) }
    }

    func stateDump() -> String {
        var s = "scene \(Int(size.width))x\(Int(size.height)) app=\(appName) simTime=\(String(format: "%.2f", simTime))"
        if let c = canvas { s += " canvas \(c.pw)x\(c.ph) tiles \(c.tilesX * c.tilesY) lastDirty \(c.lastFlushCount)" }
        return s
    }

    /// Scene-specific harness commands; nil = unknown.
    func devCommand(_ cmd: String, _ a: [String]) -> String? { nil }

    /// Draws ledges (green), walls (red) and debris tops (yellow) over a snapshot image.
    func debugOverlay(on img: CGImage) -> CGImage? { nil }
}
