import SpriteKit

enum WeaponKind { case hitscan, rocket, plasma, charge, laser }

/// How hard a hit hits the snapshot.
enum Power: Int { case letter, word, heavy }

struct WeaponDef {
    let name: String
    let kind: WeaponKind
    let interval: Double      // seconds between shots
    let auto: Bool
    let damage: CGFloat
    let pellets: Int
    let spread: CGFloat       // max random angle, radians
    let recoil: CGFloat       // self knockback, pt/s
    let mag: Int              // 0 = heat based
    let reload: Double
    let heat: CGFloat         // per shot, overheat at 1
    let power: Power
    let carve: CGFloat        // hole radius on big elements, pt
    let tracer: SKColor
    let tracerWidth: CGFloat
    let sound: Sound
    let range: CGFloat
    let knock: CGFloat        // knockback to the target
    let shake: CGFloat
    let twoHanded: Bool
    let speed: CGFloat        // projectiles
    let art: [String]
    let grip: (Int, Int)      // grip pixel
    let muzzle: (Int, Int)    // muzzle pixel
}

enum Weapons {
    static let all: [WeaponDef] = [
        WeaponDef(name: "PISTOL", kind: .hitscan, interval: 0.2, auto: false, damage: 20, pellets: 1, spread: 0.015, recoil: 60,
                  mag: 12, reload: 0.9, heat: 0, power: .letter, carve: 5, tracer: SKColor(srgbRed: 1, green: 0.9, blue: 0.4, alpha: 1),
                  tracerWidth: 1.5, sound: .pistol, range: 1500, knock: 140, shake: 1, twoHanded: false, speed: 0,
                  art: ["...kkkkkkkkkkkkk",
                        "..kwssssssssslck",
                        "..kllllllllllgck",
                        "..kgggggggggkkkk",
                        "..kdkyykdkkk....",
                        "..kddkkdk.......",
                        "..kddkkk........",
                        "..kddk..........",
                        "..kkkk.........."], grip: (4, 6), muzzle: (15, 1)),
        WeaponDef(name: "SMG", kind: .hitscan, interval: 0.075, auto: true, damage: 9, pellets: 1, spread: 0.07, recoil: 22,
                  mag: 36, reload: 1.3, heat: 0, power: .letter, carve: 4, tracer: SKColor(srgbRed: 1, green: 1, blue: 0.6, alpha: 1),
                  tracerWidth: 1.2, sound: .smg, range: 1300, knock: 60, shake: 1, twoHanded: true, speed: 0,
                  art: ["...kkkkkkkkkkkkkkk....",
                        "..kwsssssssssssslk....",
                        ".klllllllllllllllgkkkk",
                        "kkgaaaaaaaaaaaaagglcck",
                        "kdgggggggggggggggkkkkk",
                        "kdkkkkyykkdddkkkk.....",
                        "kk..kdddk.kbbk........",
                        "....kdddk.kbbk........",
                        "....kdddk.kbbk........",
                        "....kkkkk.kkkk........"], grip: (6, 7), muzzle: (21, 3)),
        WeaponDef(name: "SHOTGUN", kind: .hitscan, interval: 0.75, auto: false, damage: 9, pellets: 8, spread: 0.2, recoil: 480,
                  mag: 6, reload: 1.5, heat: 0, power: .word, carve: 6, tracer: SKColor(srgbRed: 1, green: 0.75, blue: 0.4, alpha: 1),
                  tracerWidth: 1.2, sound: .shotgun, range: 750, knock: 110, shake: 4, twoHanded: true, speed: 0,
                  art: ["......kkkkkkkkkkkkkkkkkkk.",
                        "kkkkkkwsssssssssssssssslkk",
                        "klllllllllllllllllllllgcck",
                        "kgggggkkkkkkkkkkkkkkkkkkkk",
                        "kdddddkyydkdddddddddddk...",
                        "kddkk.kddk.kyyyyyyyyyk....",
                        "kkk...kddk.kkkkkkkkkkk....",
                        "......kddk................",
                        "......kkkk................"], grip: (7, 6), muzzle: (25, 2)),
        WeaponDef(name: "ROCKET", kind: .rocket, interval: 1.0, auto: false, damage: 95, pellets: 1, spread: 0, recoil: 200,
                  mag: 3, reload: 2.0, heat: 0, power: .heavy, carve: 0, tracer: .orange, tracerWidth: 0, sound: .rocket,
                  range: 2000, knock: 0, shake: 3, twoHanded: true, speed: 950,
                  art: ["...kkkkkkkkkkkkkkkkkkkkkk..",
                        "..kwssssssssssssssssssslkk.",
                        "kkkllllllllllllllllllllgcck",
                        "kyykbbbbbbbbbbbbbbbbbbbbcck",
                        "kyykaaaaaaaaaaaaaaaaaaaacck",
                        "kkkkgggggggggggggggggggggkk",
                        "...kkkkkkkdyydkkkkkkkkkkk..",
                        ".........kdddkkbbk.........",
                        ".........kdddk.kbk.........",
                        ".........kdddk.kkk.........",
                        ".........kkkkk............."], grip: (11, 8), muzzle: (26, 3)),
        WeaponDef(name: "PLASMA", kind: .plasma, interval: 0.11, auto: true, damage: 13, pellets: 1, spread: 0.03, recoil: 30,
                  mag: 0, reload: 0, heat: 0.07, power: .letter, carve: 4, tracer: SKColor(srgbRed: 0.35, green: 0.95, blue: 1, alpha: 1),
                  tracerWidth: 0, sound: .plasma, range: 2000, knock: 80, shake: 1, twoHanded: true, speed: 1100,
                  art: ["....kkkkkkkkkkkkk......",
                        "...kbbbbbbbbbbbbbk.....",
                        "..kbaaaaaaaaaaaaabkkkk.",
                        ".kbawwwwwwwwwwwwaabslk.",
                        "kkdddddddddddddddddcck",
                        "kdgggggggggggggggggkkk",
                        "kdkkkyykkkkddddkkkk...",
                        "kk..kdddk..kbbk.......",
                        "....kdddk..kbbk.......",
                        "....kdddk..kkkk.......",
                        "....kkkkk............."], grip: (6, 8), muzzle: (21, 4)),
        WeaponDef(name: "BLASTER", kind: .charge, interval: 0.35, auto: false, damage: 25, pellets: 1, spread: 0.01, recoil: 120,
                  mag: 5, reload: 1.8, heat: 0, power: .word, carve: 8, tracer: SKColor(srgbRed: 0.6, green: 0.8, blue: 1, alpha: 1),
                  tracerWidth: 3, sound: .blaster, range: 1600, knock: 200, shake: 3, twoHanded: true, speed: 0,
                  art: [".....kkkkkkkkkkkkkkkk....",
                        "...kkggggggggggggggggkk..",
                        "..kwssssssssssssssssslk..",
                        ".kbbbbbbbbbbbbbbbbbbbbbkk",
                        "kkaaaaaaaaaaaaaaaaaaaaaak",
                        "kdawwwwwwwwwwwwwwwwwwwwak",
                        "kdddddddddddddddddddkkkkk",
                        "kddkkyykkkkdddddddk......",
                        "kdk.kdddk..kkkkkkkk......",
                        "kk..kdddk................",
                        "....kdddk................",
                        "....kkkkk................"], grip: (6, 9), muzzle: (24, 5)),
        WeaponDef(name: "LASER", kind: .laser, interval: 0.55, auto: false, damage: 38, pellets: 1, spread: 0, recoil: 70,
                  mag: 0, reload: 0, heat: 0.3, power: .letter, carve: 3, tracer: SKColor(srgbRed: 1, green: 0.25, blue: 0.3, alpha: 1),
                  tracerWidth: 3, sound: .laser, range: 2200, knock: 160, shake: 2, twoHanded: true, speed: 0,
                  art: ["........kkkkkkkkkkkkkkkkkkk..",
                        "......kkwssssssssssssssssslkk",
                        "....kkllllllllllllllllllllrrk",
                        "..kkggggggggggggggggggkkkkkk.",
                        "kkdddkaaaaaaaaaaaaaakdk......",
                        "kddddkkyykkkkkkkkkkkkk.......",
                        "kddk.kdddk...................",
                        "kkk..kdddk...................",
                        ".....kdddk...................",
                        ".....kkkkk..................."], grip: (7, 7), muzzle: (28, 2)),
    ]

    static let grenadeRadius: CGFloat = 82, grenadeDamage: CGFloat = 90, grenadeFuse = 1.5, grenadeMax = 3, grenadeRecharge = 5.0
    static let rocketRadius: CGFloat = 72

    static func texture(_ i: Int) -> SKTexture { Tex.pixels("gun\(i)", all[i].art) }
}

struct WeaponState {
    var ammo: Int
    var reloadLeft = 0.0
    var heat: CGFloat = 0
    var overheated = false
    var charge: CGFloat = 0
    var charging = false
}

struct WeaponBelt {
    var current = 0
    var slots: [WeaponState] = Weapons.all.map { WeaponState(ammo: $0.mag) }
    var cooldown = 0.0
    var grenades = Weapons.grenadeMax
    var grenadeTimer = 0.0
    var def: WeaponDef { Weapons.all[current] }

    mutating func refill() {
        slots = Weapons.all.map { WeaponState(ammo: $0.mag) }
        grenades = Weapons.grenadeMax
        cooldown = 0
    }
}
