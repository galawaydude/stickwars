import CoreGraphics
import SpriteKit

/// Vector art for weapons and gear (SVG path data in view-box points, y down, gun pointing right).
/// Every piece gets the same dark sticker outline; cyan/blue glow strips and yellow details.
enum Pal {
    static let K: UInt32 = 0x121219, D: UInt32 = 0x343846, G: UInt32 = 0x5C6274, L: UInt32 = 0x969EB0, S: UInt32 = 0xCED4E0
    static let W: UInt32 = 0xFFFFFF, C: UInt32 = 0x5AEBFF, B: UInt32 = 0x2878FF, N: UInt32 = 0x143CAA, Y: UInt32 = 0xFFD640
    static let O: UInt32 = 0xFF8C28, R: UInt32 = 0xE83A3A, P: UInt32 = 0x7A3CE0, V: UInt32 = 0x2A0E48, M: UInt32 = 0xD24BFF
    static let E: UInt32 = 0x3CC85A, Wood: UInt32 = 0x8A5A2B, Cu: UInt32 = 0xD9823B
}

struct GunArt {
    let svg: SVG
    let grip: CGPoint      // view-box point held by the hand
    let muzzle: CGPoint    // view-box point where shots leave
}

enum GunArts {
    typealias S = SVG
    static let pistol = GunArt(svg: SVG(w: 32, h: 18, els: [
        S.R(6, 1.5, 25, 6, Pal.S, rx: 1.5),
        S.R(6, 7, 20, 3.5, Pal.G),
        S.P("M7 9 H13 L11.5 17 H5.5 Z", Pal.D),
        S.P("M13 10 H17 V12.5 Q17 14 15 14 H13", nil, stroke: Pal.D, width: 1.4),
        S.R(29, 3, 3, 3, Pal.D),
        S.R(9, 3.2, 16, 1.3, Pal.C, outline: false),
        S.R(7, 2.5, 1.2, 4, Pal.L, outline: false), S.R(9.5, 2.5 + 3, 1, 1, Pal.W, outline: false),
        S.R(14, 10.5, 1.2, 2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 9, y: 13), muzzle: CGPoint(x: 32, y: 4.5))

    static let smg = GunArt(svg: SVG(w: 44, h: 22, els: [
        S.P("M6 5 H1 V11 H3 L6 9 Z", Pal.D),
        S.R(6, 3, 28, 8, Pal.G, rx: 2),
        S.R(9, 1, 20, 2.5, Pal.D),
        S.R(34, 4.5, 9, 3, Pal.D), S.R(40, 3.5, 3, 5, Pal.K),
        S.P("M9 11 H14 L12.5 20 H7.5 Z", Pal.D),
        S.P("M19 11 H24 L25 20 H20 Z", Pal.B),
        S.R(20.5, 12, 1.2, 6, Pal.C, outline: false),
        S.R(8, 5.8, 24, 1.5, Pal.C, outline: false),
        S.R(7, 3.6, 26, 1, Pal.S, outline: false),
        S.R(14.5, 11, 1.2, 2.2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 11, y: 16), muzzle: CGPoint(x: 43, y: 6))

    static let shotgun = GunArt(svg: SVG(w: 56, h: 18, els: [
        S.P("M10 3 L1 6 V12 L3 13 L10 9 Z", Pal.Wood),
        S.R(18, 2, 37, 4, Pal.S),
        S.R(22, 6.5, 26, 3, Pal.D),
        S.R(30, 6, 12, 4.5, Pal.O, rx: 1.5),
        S.R(32, 6.5, 0.8, 3.5, Pal.Wood, outline: false), S.R(35, 6.5, 0.8, 3.5, Pal.Wood, outline: false), S.R(38, 6.5, 0.8, 3.5, Pal.Wood, outline: false),
        S.R(10, 2, 12, 8, Pal.G, rx: 1.5),
        S.P("M11 9 H16 L14 16 H9 Z", Pal.D),
        S.R(11, 4, 10, 1.4, Pal.C, outline: false),
        S.R(19, 2.6, 34, 0.9, Pal.W, outline: false),
        S.R(16, 9.5, 1.2, 2, Pal.Y, outline: false),
        S.R(53, 1, 1.5, 1.2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 12.5, y: 12.5), muzzle: CGPoint(x: 55, y: 4))

    static let rocket = GunArt(svg: SVG(w: 60, h: 24, els: [
        S.R(1, 0.5, 8, 13, Pal.D), S.R(1, 3, 2, 8, Pal.O, outline: false),
        S.R(8, 2, 46, 10, Pal.N, rx: 2),
        S.R(52, 1, 7, 12, Pal.D), S.R(57, 3.5, 2, 7, Pal.K, outline: false),
        S.R(26, 0, 6, 2.5, Pal.G),
        S.R(10, 3, 42, 2, Pal.B, outline: false),
        S.R(14, 7, 34, 1.5, Pal.C, outline: false),
        S.R(44, 2, 2, 10, Pal.Y, outline: false), S.R(47.5, 2, 2, 10, Pal.Y, outline: false),
        S.P("M20 12 H25 L24 22 H19 Z", Pal.D),
        S.P("M34 12 H38 L37.5 18 H34.5 Z", Pal.D),
        S.R(25.5, 12.5, 1.2, 2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 22, y: 17), muzzle: CGPoint(x: 59, y: 7))

    static let plasma = GunArt(svg: SVG(w: 50, h: 22, els: [
        S.P("M6 4 L1 5.5 V11 L6 11 Z", Pal.D),
        S.P("M6 4 Q8 1 14 1 H38 Q43 1 45 5 V11 H6 Z", Pal.G),
        S.R(45, 6, 5, 4, Pal.D),
        S.R(38, 2.5, 1.5, 8, Pal.B, outline: false), S.R(41, 3.5, 1.5, 7, Pal.B, outline: false),
        S.R(16, 3.5, 18, 5, Pal.V, rx: 2.5),
        S.R(17.5, 4.7, 15, 2.6, Pal.C, rx: 1.3, outline: false),
        S.R(19, 5.4, 11, 1.1, Pal.W, outline: false),
        S.P("M10 11 H15 L13.5 20 H8.5 Z", Pal.D),
        S.R(22, 11, 6, 5, Pal.B),
        S.R(15.5, 11.5, 1.2, 2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 12, y: 16), muzzle: CGPoint(x: 50, y: 8))

    static let blaster = GunArt(svg: SVG(w: 54, h: 24, els: [
        S.P("M5 6 L1 7 V13 L5 14 Z", Pal.D),
        S.R(5, 4, 40, 11, Pal.G, rx: 3),
        S.R(8, 2, 30, 3, Pal.S, rx: 1),
        S.R(20, 3, 3, 13, Pal.B), S.R(26, 3, 3, 13, Pal.B), S.R(32, 3, 3, 13, Pal.B),
        S.R(21, 4, 1, 11, Pal.C, outline: false), S.R(27, 4, 1, 11, Pal.C, outline: false), S.R(33, 4, 1, 11, Pal.C, outline: false),
        S.P("M45 6 H52 L53 7 V12 L52 13 H45 Z", Pal.D),
        S.R(51, 7.5, 2, 4, Pal.C, outline: false),
        S.R(8, 10, 34, 1.8, Pal.C, outline: false),
        S.P("M10 15 H15 L13.5 22.5 H8.5 Z", Pal.D),
        S.R(15.5, 15.5, 1.2, 2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 12, y: 19), muzzle: CGPoint(x: 53, y: 9.5))

    static let laser = GunArt(svg: SVG(w: 62, h: 20, els: [
        S.P("M6 3 L1 4 V12 L4 13 L10 11 Z", Pal.D),
        S.R(24, 3.5, 36, 3.5, Pal.S),
        S.R(58, 3, 3.5, 4.5, Pal.R),
        S.P("M6 3 H30 V11 H10 L6 8 Z", Pal.G),
        S.R(14, 0, 12, 3, Pal.D, rx: 1.5), S.R(24, 0.8, 2, 1.4, Pal.C, outline: false),
        S.R(30, 7, 22, 2.5, Pal.D),
        S.R(12, 7.6, 40, 1.3, Pal.C, outline: false),
        S.R(25, 4, 33, 0.8, Pal.W, outline: false),
        S.P("M14 11 H19 L17.5 19 H12.5 Z", Pal.D),
        S.R(19.5, 11.5, 1.2, 2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 16, y: 15), muzzle: CGPoint(x: 61.5, y: 5.2))

    static let blackhole = GunArt(svg: SVG(w: 56, h: 26, els: [
        S.P("M5 6 Q7 3 12 3 H36 V17 H5 Z", Pal.D),
        S.P("M47 2 L55 6 V7.5 L47 5 Z", Pal.S), S.P("M47 18 L55 14 V12.5 L47 15 Z", Pal.S),
        S.C(42, 10, 9, Pal.V),
        S.C(42, 10, 6.5, nil, stroke: Pal.M, width: 1.3, outline: false),
        S.C(42, 10, 4.2, Pal.K, outline: false),
        S.C(42, 10, 8.3, nil, stroke: Pal.P, width: 1.4, outline: false),
        S.R(8, 4, 26, 1.2, Pal.L, outline: false),
        S.R(8, 8, 24, 1.8, Pal.M, outline: false),
        S.R(14, 12, 2, 4, Pal.K, outline: false), S.R(18, 12, 2, 4, Pal.K, outline: false), S.R(22, 12, 2, 4, Pal.K, outline: false),
        S.P("M10 17 H16 L14.5 24.5 H8.5 Z", Pal.D),
        S.R(16.5, 17.5, 1.2, 2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 12, y: 21), muzzle: CGPoint(x: 55, y: 10))

    static let saw = GunArt(svg: SVG(w: 52, h: 26, els: [
        S.P("M12 6 V2 H26 V6", nil, stroke: Pal.D, width: 2.5),
        S.R(4, 6, 30, 11, Pal.O, rx: 2),
        S.P("M8 6 L12 6 L7 17 L3 17 Z", Pal.K, alpha: 0.55, outline: false),
        S.P("M16 6 L20 6 L15 17 L11 17 Z", Pal.K, alpha: 0.55, outline: false),
        S.P("M24 6 L28 6 L23 17 L19 17 Z", Pal.K, alpha: 0.55, outline: false),
        S.R(34, 7.5, 9, 7, Pal.D),
        S.P("M43 4 H47 V6 H45 V16 H47 V18 H43 Z", Pal.G),
        S.R(6, 7.2, 26, 1, Pal.Y, outline: false),
        S.P("M9 17 H15 L13.5 24.5 H7.5 Z", Pal.D),
        S.R(15.5, 17.5, 1.2, 2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 11.5, y: 21), muzzle: CGPoint(x: 50, y: 11))

    static let lightning = GunArt(svg: SVG(w: 52, h: 24, els: [
        S.P("M5 6 L1 7 V13 L5 14 Z", Pal.D),
        S.R(5, 5, 28, 10, Pal.G, rx: 2),
        S.R(33, 8, 15, 3, Pal.S),
        S.R(34, 3, 3, 13, Pal.Cu, rx: 1), S.R(38.5, 4, 3, 11, Pal.Cu, rx: 1), S.R(43, 5, 3, 9, Pal.Cu, rx: 1),
        S.C(49, 9.5, 3.5, Pal.C),
        S.C(49, 9.5, 1.6, Pal.W, outline: false),
        S.R(8, 6, 24, 1, Pal.L, outline: false),
        S.R(8, 9.2, 22, 1.6, Pal.C, outline: false),
        S.P("M10 15 H15 L13.5 22.5 H8.5 Z", Pal.D),
        S.R(15.5, 15.5, 1.2, 2, Pal.Y, outline: false),
    ]), grip: CGPoint(x: 12, y: 19), muzzle: CGPoint(x: 52, y: 9.5))

    static let knife = GunArt(svg: SVG(w: 34, h: 10, outline: 1.2, els: [
        S.R(0.5, 3, 10, 4.5, Pal.D, rx: 1.5),
        S.R(2.5, 3, 1, 4.5, Pal.K, outline: false), S.R(5.5, 3, 1, 4.5, Pal.K, outline: false),
        S.R(10, 1, 2.2, 8.5, Pal.G, rx: 1),
        S.P("M12 3 H28 L33.5 5.2 L28 7.5 H12 Z", Pal.S),
        S.P("M12 6.6 H28 L33.2 5.3", nil, stroke: Pal.W, width: 0.8, outline: false),
        S.R(13, 4.2, 12, 0.8, Pal.L, outline: false),
        S.R(0.8, 4.7, 1, 1, Pal.C, outline: false),
    ]), grip: CGPoint(x: 5, y: 5.2), muzzle: CGPoint(x: 33.5, y: 5.2))

    /// Spinning blade (saw launcher projectile and the one loaded in the gun).
    static let sawBlade: SVG = {
        var d = "M"
        let teeth = 12
        for i in 0..<(teeth * 2) {
            let a = CGFloat(i) / CGFloat(teeth * 2) * .pi * 2
            let r: CGFloat = i % 2 == 0 ? 10 : 7.2
            d += String(format: "%.2f %.2f ", 10 + cos(a) * r, 10 + sin(a) * r) + (i == 0 ? "L" : "")
        }
        d += "Z"
        return SVG(w: 20, h: 20, outline: 1, els: [
            SVG.P(d, Pal.S),
            SVG.C(10, 10, 5.5, Pal.L, outline: false),
            SVG.C(10, 10, 2.6, Pal.D, outline: false),
            SVG.P("M10 3 L11 7 L9 7 Z", Pal.W, outline: false),
        ])
    }()

    /// Armour vest, drawn along the torso bone (x = hip -> neck).
    static let vest = SVG(w: 20, h: 12, outline: 1, els: [
        SVG.P("M0 2 Q0 0 3 0 H16 Q20 0 20 3 V9 Q20 12 16 12 H3 Q0 12 0 10 Z", Pal.N),
        SVG.R(3, 1.5, 6, 9, Pal.B, rx: 1, outline: false),
        SVG.R(11, 1.5, 6, 9, Pal.B, rx: 1, outline: false),
        SVG.R(3.5, 2, 5, 1, Pal.C, outline: false), SVG.R(11.5, 2, 5, 1, Pal.C, outline: false),
        SVG.R(9.5, 0, 1, 12, Pal.K, outline: false),
    ])

    static let helmet = SVG(w: 20, h: 11, outline: 1, els: [
        SVG.P("M1 10 Q1 1 10 1 Q19 1 19 10 Z", Pal.N),
        SVG.P("M4 9 Q4 3.5 10 3", nil, stroke: Pal.C, width: 1.2, outline: false),
        SVG.R(0, 8.5, 20, 2.5, Pal.G, rx: 1),
    ])

    /// Pickup icons.
    static let armorPickup = SVG(w: 22, h: 24, els: [
        SVG.P("M11 1 L21 5 V11 Q21 19 11 23 Q1 19 1 11 V5 Z", Pal.N),
        SVG.P("M11 4 L18 7 V11 Q18 17 11 20 Z", Pal.B, outline: false),
        SVG.P("M6 12 L10 16 L16 8", nil, stroke: Pal.C, width: 2, outline: false),
    ])

    static let medkit = SVG(w: 22, h: 18, els: [
        SVG.R(1, 3, 20, 14, Pal.W, rx: 2.5),
        SVG.R(8, 0.5, 6, 3.5, Pal.L, rx: 1),
        SVG.R(9, 6, 4, 9, Pal.R, outline: false), SVG.R(6.5, 8.5, 9, 4, Pal.R, outline: false),
    ])
}
