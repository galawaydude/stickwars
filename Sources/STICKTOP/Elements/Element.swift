import CoreGraphics

enum ElementKind: UInt8 {
    case text      // a word or letter group; letters can be shot out
    case control   // button, field, small icon
    case image     // photo, big icon, panel; carves and crumbles
    case line      // divider / container top edge
    case ledge     // window title-bar top: a ledge only, bullets pass through
}

enum ElementState: UInt8 { case solid, loose, destroyed }

/// One solid piece of the snapshot, in scene points (origin bottom-left).
struct Element {
    var rect: CGRect
    var kind: ElementKind
    var hp: CGFloat
    var maxHP: CGFloat
    /// Carved-away area in pt².
    var carved: CGFloat = 0
    /// Letter rects for text, computed lazily from the canvas on first hit.
    var letters: [CGRect]?
    var state: ElementState = .solid
    /// Big enough for solid sides (wall slide / wall jump). Text never gets walls.
    var wall: Bool
    var fromAX: Bool

    init(rect: CGRect, kind: ElementKind, fromAX: Bool = false) {
        self.rect = rect
        self.kind = kind
        self.fromAX = fromAX
        wall = (kind == .image || kind == .control) && rect.height >= 34 && rect.width >= 24
        let a = rect.width * rect.height
        switch kind {
        case .text: hp = 1
        case .control: hp = clamp(a / 30, 10, 90)
        case .image: hp = clamp(a / 25, 40, 700)
        case .line: hp = 8
        case .ledge: hp = .infinity
        }
        maxHP = hp
    }

    /// Big elements get holes carved; small ones get knocked loose whole.
    var isBig: Bool { kind == .image || (kind == .control && rect.width * rect.height > 2400) }
    var shootable: Bool { kind != .ledge }
}
