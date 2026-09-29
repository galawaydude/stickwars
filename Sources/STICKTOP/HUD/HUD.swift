import SpriteKit

/// Pixel HUD: top-left panel (app, kills, HP, jet), scores, bottom hotbar, kill feed, banner.
final class HUD {
    let root = SKNode()
    private let size: CGSize
    private let panel = SKSpriteNode()
    private let appLabel = SKSpriteNode(), killsLabel = SKSpriteNode(), hpLabel = SKSpriteNode()
    private let hpBack = SKSpriteNode(texture: Tex.white), hpFill = SKSpriteNode(texture: Tex.white)
    private let jetBack = SKSpriteNode(texture: Tex.white), jetFill = SKSpriteNode(texture: Tex.white)
    private var scoreLabels: [SKSpriteNode] = []
    private var slots: [SKSpriteNode] = [], icons: [SKSpriteNode] = [], numbers: [SKSpriteNode] = []
    private let selector = SKSpriteNode()
    private let ammoLabel = SKSpriteNode(), grenadeLabel = SKSpriteNode()
    private let banner = SKSpriteNode(), bannerSub = SKSpriteNode()
    private struct FeedLine { let node: SKNode; let until: Double }
    private var feed: [FeedLine] = []
    // cached shown values (avoid rebuilding strings every frame)
    private var shown = (app: "", kills: -1, hp: -1, weapon: -1, ammo: -1, grenades: -1, scores: -1)

    static func panelTexture(_ w: Int, _ h: Int, border: SKColor = SKColor(white: 0.75, alpha: 1), fill: CGFloat = 0.62, inner: CGFloat = 0.08) -> SKTexture {
        Tex.drawn("panel\(w)x\(h)\(border.hashValue)\(fill)\(inner)", w, h, nearest: true) { c in
            c.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 0.95))
            c.fill(CGRect(x: 1, y: 0, width: w - 2, height: h)); c.fill(CGRect(x: 0, y: 1, width: w, height: h - 2))
            c.setFillColor(border.cgColor)
            c.fill(CGRect(x: 2, y: 1, width: w - 4, height: h - 2)); c.fill(CGRect(x: 1, y: 2, width: w - 2, height: h - 4))
            c.setFillColor(CGColor(srgbRed: inner, green: inner, blue: inner * 1.3, alpha: min(1, fill + 0.3)))
            c.clear(CGRect(x: 3, y: 3, width: w - 6, height: h - 6))
            c.fill(CGRect(x: 3, y: 3, width: w - 6, height: h - 6))
        }
    }

    init(size: CGSize) {
        self.size = size
        let H = size.height
        panel.texture = HUD.panelTexture(130, 50)
        panel.size = CGSize(width: 260, height: 100)
        panel.anchorPoint = CGPoint(x: 0, y: 1)
        panel.position = CGPoint(x: 12, y: H - 12)
        root.addChild(panel)
        for (n, y) in [(appLabel, H - 30), (killsLabel, H - 54), (hpLabel, H - 78)] {
            n.anchorPoint = CGPoint(x: 0, y: 0.5); n.position = CGPoint(x: 26, y: y); n.zPosition = 1; root.addChild(n)
        }
        for (b, f, y, h) in [(hpBack, hpFill, H - 78, CGFloat(10)), (jetBack, jetFill, H - 96, CGFloat(4))] {
            b.anchorPoint = CGPoint(x: 0, y: 0.5); f.anchorPoint = CGPoint(x: 0, y: 0.5)
            b.size = CGSize(width: 140, height: h + 4); f.size = CGSize(width: 136, height: h)
            b.position = CGPoint(x: 112, y: y); f.position = CGPoint(x: 114, y: y)
            b.color = SKColor(white: 0.08, alpha: 1); b.colorBlendFactor = 1
            f.colorBlendFactor = 1; b.zPosition = 1; f.zPosition = 2
            root.addChild(b); root.addChild(f)
        }
        jetBack.position.x = 26; jetFill.position.x = 28
        jetBack.size.width = 226; jetFill.size.width = 222
        jetFill.color = SKColor(srgbRed: 0.35, green: 0.9, blue: 1, alpha: 1)

        // hotbar
        let n = Weapons.all.count, slotW: CGFloat = 58, gap: CGFloat = 4
        let total = CGFloat(n) * slotW + CGFloat(n - 1) * gap
        let x0 = size.width / 2 - total / 2
        for i in 0..<n {
            let s = SKSpriteNode(texture: HUD.panelTexture(29, 29, border: SKColor(white: 0.5, alpha: 1), fill: 0.7, inner: 0.2))
            s.size = CGSize(width: slotW, height: slotW)
            s.position = CGPoint(x: x0 + slotW / 2 + CGFloat(i) * (slotW + gap), y: 14 + slotW / 2)
            root.addChild(s); slots.append(s)
            let t = Weapons.texture(i)
            let sc: CGFloat = t.size().width * 2 <= slotW - 8 ? 2 : 1
            let ic = SKSpriteNode(texture: t, size: CGSize(width: t.size().width * sc, height: t.size().height * sc))
            ic.position = s.position + CGPoint(x: 0, y: -2); ic.zPosition = 2
            root.addChild(ic); icons.append(ic)
            let num = PixelFont.label("\(i + 1)", scale: 2, color: SKColor(white: 0.8, alpha: 1))
            num.anchorPoint = CGPoint(x: 0, y: 1)
            num.position = s.position + CGPoint(x: -slotW / 2 + 5, y: slotW / 2 - 4); num.zPosition = 3
            root.addChild(num); numbers.append(num)
        }
        selector.texture = HUD.panelTexture(31, 31, border: SKColor(srgbRed: 0.35, green: 0.95, blue: 1, alpha: 1), fill: 0.7, inner: 0.28)
        selector.size = CGSize(width: slotW + 4, height: slotW + 4)
        selector.zPosition = 1
        root.addChild(selector)
        ammoLabel.anchorPoint = CGPoint(x: 0.5, y: 0); ammoLabel.position = CGPoint(x: size.width / 2, y: 14 + slotW + 8)
        grenadeLabel.anchorPoint = CGPoint(x: 0, y: 0.5); grenadeLabel.position = CGPoint(x: x0 + total + 12, y: 14 + slotW / 2)
        root.addChild(ammoLabel); root.addChild(grenadeLabel)

        banner.position = CGPoint(x: size.width / 2, y: size.height / 2 + 40); banner.zPosition = 20; banner.isHidden = true
        bannerSub.position = CGPoint(x: size.width / 2, y: size.height / 2 - 30); bannerSub.zPosition = 20; bannerSub.isHidden = true
        root.addChild(banner); root.addChild(bannerSub)
    }

    func update(_ s: GameScene) {
        let p = s.player!
        if s.appName != shown.app { shown.app = s.appName; PixelFont.set(appLabel, String(s.appName.prefix(18)).uppercased(), scale: 2, color: .white) }
        if p.kills != shown.kills {
            shown.kills = p.kills
            PixelFont.set(killsLabel, "KILLS \(p.kills) / FIRST TO \(GameScene.scoreLimit)", scale: 2, color: SKColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1))
        }
        let hp = max(0, Int(p.hp.rounded()))
        if hp != shown.hp {
            shown.hp = hp
            PixelFont.set(hpLabel, "HP \(hp)", scale: 2, color: .white)
            hpFill.xScale = CGFloat(hp) / 100
            hpFill.color = hp > 60 ? SKColor(srgbRed: 0.3, green: 0.9, blue: 0.4, alpha: 1) : hp > 30 ? SKColor(srgbRed: 1, green: 0.8, blue: 0.2, alpha: 1) : SKColor(srgbRed: 1, green: 0.25, blue: 0.2, alpha: 1)
        }
        jetFill.xScale = max(0.001, p.jetFuel)

        // scores (compact, under the panel)
        var sc = s.fighters.count
        for f in s.fighters { sc = sc &* 31 &+ f.kills }
        if sc != shown.scores {
            shown.scores = sc
            while scoreLabels.count < s.fighters.count {
                let l = SKSpriteNode(); l.anchorPoint = CGPoint(x: 0, y: 0.5); root.addChild(l); scoreLabels.append(l)
            }
            var x: CGFloat = 16
            for (i, l) in scoreLabels.enumerated() {
                guard i < s.fighters.count else { l.isHidden = true; continue }
                let f = s.fighters[i]
                l.isHidden = false
                PixelFont.set(l, "\(f.name) \(f.kills)", scale: 2, color: f.color.blended(withFraction: 0.3, of: .white) ?? f.color)
                l.position = CGPoint(x: x, y: size.height - 126)
                x += l.size.width + 12
            }
        }

        // hotbar
        let w = p.weapons.current
        if w != shown.weapon {
            shown.weapon = w
            selector.position = slots[w].position
            for (i, ic) in icons.enumerated() { ic.alpha = i == w ? 1 : 0.55 }
        }
        let st = p.weapons.slots[w], def = p.weapons.def
        // integer key of everything the ammo line shows, so the string is only built on change
        let key = w | st.ammo << 4 | (st.reloadLeft > 0 ? 1 : 0) << 12 | Int(st.heat * 100) << 13 | (st.overheated ? 1 : 0) << 21
            | (st.charging ? 1 : 0) << 22 | Int(st.charge * 100) << 23
        if key != shown.ammo {
            shown.ammo = key
            var ammo: String
            if st.reloadLeft > 0 { ammo = "\(def.name)  RELOADING" }
            else if def.mag > 0 { ammo = "\(def.name)  \(st.ammo)/\(def.mag)" }
            else { ammo = st.overheated ? "\(def.name)  OVERHEAT" : "\(def.name)  HEAT \(Int(st.heat * 100))%" }
            if def.kind == .charge && st.charging { ammo = "\(def.name)  CHARGE \(Int(st.charge * 100))%" }
            PixelFont.set(ammoLabel, ammo, scale: 2, color: st.overheated || st.reloadLeft > 0 ? .orange : .white)
        }
        if p.weapons.grenades != shown.grenades {
            shown.grenades = p.weapons.grenades
            PixelFont.set(grenadeLabel, "GRENADES \(p.weapons.grenades)", scale: 2, color: SKColor(srgbRed: 0.6, green: 1, blue: 0.6, alpha: 1))
        }

        // kill feed fade
        let t = s.simTime
        var i = 0
        while i < feed.count {
            let left = feed[i].until - t
            if left <= 0 { feed[i].node.removeFromParent(); feed.remove(at: i); continue }
            feed[i].node.alpha = min(1, CGFloat(left))
            i += 1
        }
    }

    func addKill(killer: Fighter?, victim: Fighter, weapon: Int, time: Double) {
        let line = SKNode()
        var x: CGFloat = 0
        func add(_ n: SKSpriteNode) { n.anchorPoint = CGPoint(x: 1, y: 0.5); n.position = CGPoint(x: x, y: 0); line.addChild(n); x -= n.size.width + 6 }
        add(PixelFont.label(victim.name, scale: 2, color: victim.color.blended(withFraction: 0.3, of: .white) ?? victim.color))
        if let killer, killer !== victim {
            let t = Weapons.texture(weapon)
            add(SKSpriteNode(texture: t, size: CGSize(width: t.size().width, height: t.size().height)))
            add(PixelFont.label(killer.name, scale: 2, color: killer.color.blended(withFraction: 0.3, of: .white) ?? killer.color))
        } else {
            add(PixelFont.label("X", scale: 2, color: .red))
        }
        let bg = SKSpriteNode(texture: HUD.panelTexture(Int(-x / 2) + 6, 10))
        bg.anchorPoint = CGPoint(x: 1, y: 0.5); bg.size = CGSize(width: -x + 12, height: 20); bg.position = CGPoint(x: 6, y: 0); bg.zPosition = -1
        line.addChild(bg)
        root.addChild(line)
        feed.insert(FeedLine(node: line, until: time + 6), at: 0)
        if feed.count > 6 { feed.removeLast().node.removeFromParent() }
        for (k, f) in feed.enumerated() { f.node.position = CGPoint(x: size.width - 18, y: size.height - 26 - CGFloat(k) * 24) }
    }

    func clearFeed() { for f in feed { f.node.removeFromParent() }; feed.removeAll() }

    func showBanner(_ text: String?, color: SKColor = .white, sub: String? = nil) {
        guard let text else { banner.isHidden = true; bannerSub.isHidden = true; return }
        PixelFont.set(banner, text, scale: 10, color: color)
        banner.isHidden = false
        if let sub { PixelFont.set(bannerSub, sub, scale: 3, color: .white); bannerSub.isHidden = false } else { bannerSub.isHidden = true }
    }
}
