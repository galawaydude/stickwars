import CoreGraphics
import Foundation
import QuartzCore
import SpriteKit

@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
@inline(__always) func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

extension CGPoint {
    @inline(__always) static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    @inline(__always) static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    @inline(__always) static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    @inline(__always) var length: CGFloat { (x * x + y * y).squareRoot() }
    @inline(__always) var normalized: CGPoint { let l = length; return l > 1e-6 ? CGPoint(x: x / l, y: y / l) : CGPoint(x: 1, y: 0) }
    @inline(__always) func dist(_ o: CGPoint) -> CGFloat { (self - o).length }
}

extension CGRect {
    @inline(__always) var center: CGPoint { CGPoint(x: midX, y: midY) }
    var area: CGFloat { width * height }
}

/// Small fast deterministic RNG (xorshift64*), a value type so hot paths don't allocate.
struct RNG {
    var s: UInt64
    init(_ seed: UInt64 = UInt64(CACurrentMediaTime() * 1e6) | 1) { s = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    @inline(__always) mutating func next() -> UInt64 {
        s ^= s >> 12; s ^= s << 25; s ^= s >> 27
        return s &* 2685821657736338717
    }
    /// Uniform in [0, 1).
    @inline(__always) mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    @inline(__always) mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
    @inline(__always) mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    @inline(__always) mutating func chance(_ p: CGFloat) -> Bool { unit() < p }
}

/// Global game RNG (main thread only).
var rng = RNG()

@inline(__always) func now() -> Double { CACurrentMediaTime() }

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// Packed RGBA8 colour (r in the low byte), matching the canvas memory layout.
struct RGBA: Equatable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex: UInt32) { self.init(UInt8(hex >> 16 & 255), UInt8(hex >> 8 & 255), UInt8(hex & 255)) }
    var sk: SKColor { SKColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255) }
}
