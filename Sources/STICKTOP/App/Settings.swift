import Foundation

enum Difficulty: Int, CaseIterable {
    case easy, normal, hard
    var title: String { ["Easy", "Normal", "Hard"][rawValue] }
}

/// Persisted menu options.
struct Settings {
    var bots: Int { didSet { UserDefaults.standard.set(bots, forKey: "bots") } }
    var difficulty: Difficulty { didSet { UserDefaults.standard.set(difficulty.rawValue, forKey: "difficulty") } }
    var muted: Bool { didSet { UserDefaults.standard.set(muted, forKey: "muted") } }

    init() {
        let d = UserDefaults.standard
        bots = d.object(forKey: "bots") as? Int ?? 3
        difficulty = Difficulty(rawValue: d.integer(forKey: "difficulty")) ?? .normal
        if d.object(forKey: "difficulty") == nil { difficulty = .normal }
        muted = d.bool(forKey: "muted")
    }
}
