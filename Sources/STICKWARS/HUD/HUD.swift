import SpriteKit

/// Pixel HUD. Scoreboard across the top centre, the player's card (weapon, ammo, HP, jet,
/// grenades) bottom-left with the weapon strip above it, kill feed top-right, plus crosshair
/// with hit markers, damage vignette, kill callouts, respawn countdown and the win banner.
final class HUD {
    let root = SKNode()
    private let size: CGSize
    /// Top of the scoreboard: below the notch (camera housing) on MacBooks that have one.
    private let scoreTop: CGFloat
    // top
    private let appLabel = SKSpriteNode()
    private let scorePanel = SKSpriteNode(), scoreSub = SKSpriteNode()
    private var scoreHeads: [SKSpriteNode] = [], scoreNums: [SKSpriteNode] = []
    private let scoreMark = SKSpriteNode(texture: Tex.white)
    // player card
    private let card = SKSpriteNode()
    private let weaponIcon = SKSpriteNode(), weaponName = SKSpriteNode(), ammoLabel = SKSpriteNode()
    private let heatBack = SKSpriteNode(texture: Tex.white), heatFill = SKSpriteNode(texture: Tex.white)
    private let hpLabel = SKSpriteNode()
    private let hpBack = SKSpriteNode(texture: Tex.white), hpFill = SKSpriteNode(texture: Tex.white), hpGhost = SKSpriteNode(texture: Tex.white)
    private let jetBack = SKSpriteNode(texture: Tex.white), jetFill = SKSpriteNode(texture: Tex.white)
    private let armorBack = SKSpriteNode(texture: Tex.white), armorFill = SKSpriteNode(texture: Tex.white)
    private var grenadeIcons: [SKSpriteNode] = []
    private var slots: [SKSpriteNode] = [], slotIcons: [SKSpriteNode] = []
    private let selector = SKSpriteNode()
    // centre
    let crosshair = SKSpriteNode(texture: Art.crosshair)
    private let hitMarker = SKSpriteNode(), crossAmmo = SKSpriteNode()
    private var hitT: CGFloat = 0, killMarkT: CGFloat = 0
    private let vignette = SKSpriteNode()
    private var hurtT: CGFloat = 0
    private let calloutLabel = SKSpriteNode()
    private var calloutT: CGFloat = 9
    private let respawnLabel = SKSpriteNode()
    private let hintLabel = SKSpriteNode()
    private var hintT: CGFloat = 9
    private let banner = SKSpriteNode(), bannerSub = SKSpriteNode()
    private struct FeedLine { let node: SKNode; let until: Double }
    private var feed: [FeedLine] = []
    private var clock: CGFloat = 0
    /// Demo reels: hide all chrome except the kill feed, callouts and banner.
    var cinematic = false {
        didSet {
            let keep: [SKNode] = [calloutLabel, banner, bannerSub]
            for n in root.children where !keep.contains(where: { $0 === n }) && !feed.contains(where: { $0.node === n }) { n.isHidden = cinematic }
        }
    }
    private var ghostHP: CGFloat = 100
    // cached shown values (strings are only rebuilt on change)
    private var shown = (app: "", hp: -1, weapon: -1, ammo: -1, grenades: -1, scores: -1, respawn: -1, crossAmmo: -1)

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

    private static var vignetteTexture: SKTexture {
        Tex.drawn("vignette", 128, 80) { c in
            let g = CGGradient(colorsSpace: sRGB, colors: [CGColor(srgbRed: 0.9, green: 0, blue: 0, alpha: 0), CGColor(srgbRed: 0.9, green: 0.02, blue: 0.02, alpha: 0.8)] as CFArray, locations: [0.78, 1])!
            c.scaleBy(x: 1, y: 80.0 / 128.0)
            c.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 84, options: .drawsAfterEndLocation)
        }
    }

    private func bar(_ b: SKSpriteNode, _ f: SKSpriteNode, at p: CGPoint, w: CGFloat, h: CGFloat, color: SKColor) {
        b.anchorPoint = CGPoint(x: 0, y: 0.5); f.anchorPoint = CGPoint(x: 0, y: 0.5)
        b.size = CGSize(width: w + 4, height: h + 4); f.size = CGSize(width: w, height: h)
        b.position = p; f.position = p + CGPoint(x: 2, y: 0)
        b.color = SKColor(srgbRed: 0.04, green: 0.04, blue: 0.06, alpha: 1); b.colorBlendFactor = 1
        f.color = color; f.colorBlendFactor = 1
        b.zPosition = 1; f.zPosition = 3
        root.addChild(b); root.addChild(f)
    }

    init(size: CGSize) {
        self.size = size
        let W = size.width, H = size.height
        let notch = NSScreen.screens.first?.safeAreaInsets.top ?? 0
        scoreTop = H - max(10, notch + 6)

        appLabel.anchorPoint = CGPoint(x: 0, y: 1); appLabel.position = CGPoint(x: 16, y: H - 12); appLabel.alpha = 0.85
        root.addChild(appLabel)
        scorePanel.anchorPoint = CGPoint(x: 0.5, y: 1); scorePanel.position = CGPoint(x: W / 2, y: scoreTop)
        root.addChild(scorePanel)
        PixelFont.set(scoreSub, "FIRST TO \(GameScene.scoreLimit)", scale: 2, color: SKColor(white: 0.85, alpha: 1))
        scoreSub.anchorPoint = CGPoint(x: 1, y: 0.5); scoreSub.zPosition = 2
        root.addChild(scoreSub)
        scoreMark.color = SKColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1); scoreMark.colorBlendFactor = 1
        scoreMark.size = CGSize(width: 34, height: 3); scoreMark.zPosition = 3
        root.addChild(scoreMark)

        // player card, bottom-left
        let cardW: CGFloat = 330, cardH: CGFloat = 96, x0: CGFloat = 16, y0: CGFloat = 16
        card.texture = HUD.panelTexture(Int(cardW / 2), Int(cardH / 2), border: SKColor(white: 0.55, alpha: 1), fill: 0.55, inner: 0.1)
        card.size = CGSize(width: cardW, height: cardH); card.anchorPoint = .zero; card.position = CGPoint(x: x0, y: y0)
        root.addChild(card)
        weaponIcon.anchorPoint = CGPoint(x: 0, y: 0.5); weaponIcon.position = CGPoint(x: x0 + 14, y: y0 + 68); weaponIcon.zPosition = 2
        weaponName.anchorPoint = CGPoint(x: 0, y: 0.5); weaponName.position = CGPoint(x: x0 + 82, y: y0 + 74); weaponName.zPosition = 2
        ammoLabel.anchorPoint = CGPoint(x: 1, y: 0.5); ammoLabel.position = CGPoint(x: x0 + cardW - 14, y: y0 + 70); ammoLabel.zPosition = 2
        for n in [weaponIcon, weaponName, ammoLabel] { root.addChild(n) }
        bar(heatBack, heatFill, at: CGPoint(x: x0 + 82, y: y0 + 60), w: 110, h: 4, color: .orange)
        hpLabel.anchorPoint = CGPoint(x: 0, y: 0.5); hpLabel.position = CGPoint(x: x0 + 14, y: y0 + 36); hpLabel.zPosition = 2
        root.addChild(hpLabel)
        bar(hpBack, hpFill, at: CGPoint(x: x0 + 70, y: y0 + 36), w: 244, h: 14, color: .green)
        hpGhost.anchorPoint = CGPoint(x: 0, y: 0.5); hpGhost.size = CGSize(width: 244, height: 14); hpGhost.position = hpFill.position
        hpGhost.color = SKColor(white: 1, alpha: 0.9); hpGhost.colorBlendFactor = 1; hpGhost.zPosition = 2
        root.addChild(hpGhost)
        bar(armorBack, armorFill, at: CGPoint(x: x0 + 70, y: y0 + 49), w: 244, h: 4, color: SKColor(srgbRed: 0.35, green: 0.65, blue: 1, alpha: 1))
        bar(jetBack, jetFill, at: CGPoint(x: x0 + 70, y: y0 + 16), w: 150, h: 5, color: SKColor(srgbRed: 0.35, green: 0.9, blue: 1, alpha: 1))
        let jl = PixelFont.label("JET", scale: 2, color: SKColor(srgbRed: 0.35, green: 0.9, blue: 1, alpha: 1))
        jl.anchorPoint = CGPoint(x: 0, y: 0.5); jl.position = CGPoint(x: x0 + 14, y: y0 + 16); jl.zPosition = 2
        root.addChild(jl)
        for i in 0..<Weapons.grenadeMax {
            let g = SKSpriteNode(texture: Art.grenade, size: CGSize(width: 12, height: 14))
            g.position = CGPoint(x: x0 + 250 + CGFloat(i) * 20, y: y0 + 16); g.zPosition = 2
            root.addChild(g); grenadeIcons.append(g)
        }

        // weapon strip above the card
        let sw: CGFloat = 44, gap: CGFloat = 3
        for i in 0..<Weapons.all.count {
            let s = SKSpriteNode(texture: HUD.panelTexture(22, 16, border: SKColor(white: 0.4, alpha: 1), fill: 0.6, inner: 0.12))
            s.size = CGSize(width: sw, height: 32); s.anchorPoint = .zero
            s.position = CGPoint(x: x0 + CGFloat(i) * (sw + gap), y: y0 + cardH + 6)
            root.addChild(s); slots.append(s)
            let t = Weapons.texture(i), sz = Weapons.all[i].art.svg.size
            let k = min(1, (sw - 8) / sz.width)
            let ic = SKSpriteNode(texture: t, size: CGSize(width: sz.width * k, height: sz.height * k))
            ic.position = s.position + CGPoint(x: sw / 2 + 2, y: 13); ic.zPosition = 2
            root.addChild(ic); slotIcons.append(ic)
            let num = PixelFont.label("\((i + 1) % 10)", scale: 2, color: SKColor(white: 0.85, alpha: 1))
            num.anchorPoint = CGPoint(x: 0, y: 1); num.position = s.position + CGPoint(x: 4, y: 29); num.zPosition = 3
            root.addChild(num)
        }
        // knife: always on F
        let ks = SKSpriteNode(texture: HUD.panelTexture(22, 16, border: SKColor(white: 0.4, alpha: 1), fill: 0.6, inner: 0.12))
        ks.size = CGSize(width: sw, height: 32); ks.anchorPoint = .zero
        ks.position = CGPoint(x: x0 + CGFloat(Weapons.all.count) * (sw + gap) + 8, y: y0 + cardH + 6)
        root.addChild(ks)
        let kn = SKSpriteNode(texture: Weapons.knifeTexture, size: CGSize(width: GunArts.knife.svg.size.width, height: GunArts.knife.svg.size.height))
        kn.position = ks.position + CGPoint(x: sw / 2 + 2, y: 12); kn.zPosition = 2
        root.addChild(kn)
        let kf = PixelFont.label("F", scale: 2, color: SKColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1))
        kf.anchorPoint = CGPoint(x: 0, y: 1); kf.position = ks.position + CGPoint(x: 4, y: 29); kf.zPosition = 3
        root.addChild(kf)
        selector.texture = HUD.panelTexture(24, 18, border: SKColor(srgbRed: 0.35, green: 0.95, blue: 1, alpha: 1), fill: 0.7, inner: 0.25)
        selector.size = CGSize(width: sw + 4, height: 36); selector.anchorPoint = .zero; selector.zPosition = 1
        root.addChild(selector)

        // centre elements
        crosshair.size = CGSize(width: 33, height: 33); crosshair.zPosition = 50
        root.addChild(crosshair)
        hitMarker.texture = Tex.pixels("hitmark", ["w.......w", ".w.....w.", "..w...w..", ".........", ".........", ".........",
                                                   "..w...w..", ".w.....w.", "w.......w"])
        hitMarker.size = CGSize(width: 36, height: 36); hitMarker.zPosition = 51; hitMarker.alpha = 0; hitMarker.colorBlendFactor = 1
        root.addChild(hitMarker)
        crossAmmo.anchorPoint = CGPoint(x: 0.5, y: 1); crossAmmo.zPosition = 51
        root.addChild(crossAmmo)
        vignette.texture = HUD.vignetteTexture; vignette.size = CGSize(width: W, height: H); vignette.anchorPoint = .zero
        vignette.zPosition = -3; vignette.alpha = 0
        root.addChild(vignette)
        calloutLabel.position = CGPoint(x: W / 2, y: H * 0.72); calloutLabel.zPosition = 20; calloutLabel.isHidden = true
        respawnLabel.position = CGPoint(x: W / 2, y: H / 2 + 60); respawnLabel.zPosition = 20; respawnLabel.isHidden = true
        banner.position = CGPoint(x: W / 2, y: H / 2 + 40); banner.zPosition = 20; banner.isHidden = true
        bannerSub.position = CGPoint(x: W / 2, y: H / 2 - 30); bannerSub.zPosition = 20; bannerSub.isHidden = true
        hintLabel.position = CGPoint(x: W / 2, y: 150); hintLabel.zPosition = 20; hintLabel.isHidden = true
        for n in [calloutLabel, respawnLabel, banner, bannerSub, hintLabel] { root.addChild(n) }
    }

    // MARK: per frame

    func update(_ s: GameScene, realDt: CGFloat, crosshairAt cp: CGPoint) {
        clock += realDt
        if cinematic { updateFeedAndCallout(s, realDt); return }
        let p = s.player!
        if s.appName != shown.app {
            shown.app = s.appName
            PixelFont.set(appLabel, "> " + String(s.appName.prefix(20)).uppercased(), scale: 2, color: .white)
        }

        // scoreboard
        var key = s.fighters.count
        for f in s.fighters { key = key &* 31 &+ f.kills }
        if key != shown.scores {
            shown.scores = key
            while scoreHeads.count < s.fighters.count {
                let h = SKSpriteNode(texture: Tex.circle, size: CGSize(width: 14, height: 14)); h.colorBlendFactor = 1; h.zPosition = 2
                let n = SKSpriteNode(); n.anchorPoint = CGPoint(x: 0, y: 0.5); n.zPosition = 2
                root.addChild(h); root.addChild(n); scoreHeads.append(h); scoreNums.append(n)
            }
            let entry: CGFloat = 70, count = CGFloat(s.fighters.count)
            let w = entry * count + 16 + 110
            scorePanel.texture = HUD.panelTexture(Int(w / 2), 22, border: SKColor(white: 0.5, alpha: 1), fill: 0.55, inner: 0.1)
            scorePanel.size = CGSize(width: w, height: 44)
            scoreSub.position = CGPoint(x: size.width / 2 + w / 2 - 14, y: scoreTop - 22)
            let best = s.fighters.map(\.kills).max() ?? 0
            for (i, h) in scoreHeads.enumerated() {
                let vis = i < s.fighters.count
                h.isHidden = !vis; scoreNums[i].isHidden = !vis
                guard vis else { continue }
                let f = s.fighters[i]
                let x = size.width / 2 - w / 2 + 8 + entry * CGFloat(i) + 16
                h.position = CGPoint(x: x, y: scoreTop - 22); h.color = f.color
                PixelFont.set(scoreNums[i], "\(f.kills)", scale: 3, color: f.kills == best && best > 0 ? SKColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1) : .white)
                scoreNums[i].position = CGPoint(x: x + 14, y: scoreTop - 22)
                if f.isPlayer { scoreMark.position = CGPoint(x: x + 12, y: scoreTop - 36) }
            }
        }

        // weapon, ammo, heat
        let w = p.weapons.current
        let st = p.weapons.slots[w], def = p.weapons.def
        if w != shown.weapon {
            shown.weapon = w
            let sz = Weapons.all[w].art.svg.size, k = min(1.3, 64 / sz.width)
            weaponIcon.texture = Weapons.texture(w); weaponIcon.size = CGSize(width: sz.width * k, height: sz.height * k)
            PixelFont.set(weaponName, def.name, scale: 2, color: SKColor(srgbRed: 0.6, green: 0.95, blue: 1, alpha: 1))
            selector.position = slots[w].position - CGPoint(x: 2, y: 2)
            for (i, ic) in slotIcons.enumerated() { ic.alpha = i == w ? 1 : 0.5 }
            heatBack.isHidden = def.heat == 0; heatFill.isHidden = def.heat == 0
        }
        let akey = w | st.ammo << 4 | (st.reloadLeft > 0 ? 1 : 0) << 12 | (st.overheated ? 1 : 0) << 13 | (st.charging ? 1 : 0) << 14 | Int(st.charge * 20) << 15
        if akey != shown.ammo {
            shown.ammo = akey
            let text: String
            if st.reloadLeft > 0 { text = "RELOAD" }
            else if def.mag > 0 { text = "\(st.ammo)/\(def.mag)" }
            else if st.overheated { text = "HOT!" }
            else if st.charging { text = "\(Int(st.charge * 100))%" }
            else { text = "OK" }
            let low = def.mag > 0 && st.ammo * 4 <= def.mag
            PixelFont.set(ammoLabel, text, scale: 3, color: st.reloadLeft > 0 || st.overheated || low ? .orange : .white)
        }
        if def.heat > 0 {
            heatFill.xScale = max(0.001, min(1, st.heat))
            heatFill.color = st.overheated ? .red : .orange
        }

        // HP with a white "ghost" bar that drains after hits
        let hp = max(0, p.hp)
        if Int(hp) != shown.hp {
            shown.hp = Int(hp)
            PixelFont.set(hpLabel, "\(Int(hp.rounded()))", scale: 3, color: .white)
            hpFill.xScale = max(0.001, hp / 100)
            hpFill.color = hp > 60 ? SKColor(srgbRed: 0.3, green: 0.9, blue: 0.4, alpha: 1) : hp > 30 ? SKColor(srgbRed: 1, green: 0.8, blue: 0.2, alpha: 1) : SKColor(srgbRed: 1, green: 0.25, blue: 0.2, alpha: 1)
            if hp > ghostHP { ghostHP = hp }
        }
        ghostHP = max(hp, ghostHP - realDt * 60)
        hpGhost.xScale = max(0.001, ghostHP / 100)
        jetFill.xScale = max(0.001, p.jetFuel)
        armorBack.isHidden = p.armor <= 0; armorFill.isHidden = p.armor <= 0
        if p.armor > 0 { armorFill.xScale = max(0.001, p.armor / 100) }
        if p.weapons.grenades != shown.grenades {
            shown.grenades = p.weapons.grenades
            for (i, g) in grenadeIcons.enumerated() { g.alpha = i < p.weapons.grenades ? 1 : 0.2 }
        }

        // crosshair, hit marker, low-ammo hint
        crosshair.position = CGPoint(x: cp.x.rounded(), y: cp.y.rounded())
        hitT = max(0, hitT - realDt * 5); killMarkT = max(0, killMarkT - realDt * 2.5)
        hitMarker.position = crosshair.position
        hitMarker.alpha = max(hitT, killMarkT)
        hitMarker.color = killMarkT > 0 ? SKColor(srgbRed: 1, green: 0.25, blue: 0.2, alpha: 1) : .white
        hitMarker.setScale(1 + max(hitT, killMarkT) * 0.3)
        let lowAmmo = st.reloadLeft > 0 ? 1 : (def.mag > 0 && st.ammo * 4 <= def.mag ? 2 : st.overheated ? 3 : 0)
        let ckey = lowAmmo << 8 | st.ammo
        if ckey != shown.crossAmmo {
            shown.crossAmmo = ckey
            crossAmmo.isHidden = lowAmmo == 0
            if lowAmmo != 0 {
                PixelFont.set(crossAmmo, lowAmmo == 1 ? "RELOADING" : lowAmmo == 3 ? "OVERHEAT" : "\(st.ammo)", scale: 2, color: .orange)
            }
        }
        crossAmmo.position = crosshair.position - CGPoint(x: 0, y: 22)

        // damage vignette + low HP pulse
        hurtT = max(0, hurtT - realDt * 2.5)
        // edges only, and never more than a tint: the screen underneath must stay readable
        let low: CGFloat = p.alive && hp < 35 ? 0.22 + 0.12 * sin(clock * 6) : 0
        vignette.alpha = max(hurtT * 0.55, low)

        // respawn countdown
        let left = p.alive || s.matchOver ? -1 : max(0, Int((p.respawnAt - s.simTime).rounded(.up)))
        if left != shown.respawn {
            shown.respawn = left
            respawnLabel.isHidden = left < 0
            if left >= 0 { PixelFont.set(respawnLabel, left > 0 ? "RESPAWN IN \(left)" : "GO!", scale: 5, color: .white) }
        }

        // start-of-round hint
        hintT += realDt
        hintLabel.isHidden = hintT > 3.5
        if !hintLabel.isHidden { hintLabel.alpha = hintT > 2.8 ? (3.5 - hintT) / 0.7 : 1 }

        updateFeedAndCallout(s, realDt)
    }

    private func updateFeedAndCallout(_ s: GameScene, _ realDt: CGFloat) {
        // callout pop
        calloutT += realDt
        if calloutT < 1.3 {
            calloutLabel.isHidden = false
            calloutLabel.setScale(calloutT < 0.12 ? 1.7 - calloutT / 0.12 * 0.7 : 1)
            calloutLabel.alpha = calloutT > 1.0 ? (1.3 - calloutT) / 0.3 : 1
        } else { calloutLabel.isHidden = true }

        // kill feed fade
        var i = 0
        while i < feed.count {
            let l = feed[i].until - s.simTime
            if l <= 0 { feed[i].node.removeFromParent(); feed.remove(at: i); continue }
            feed[i].node.alpha = min(1, CGFloat(l))
            i += 1
        }
    }

    // MARK: events

    func markHit() { hitT = 1 }
    func showHint(_ text: String) { PixelFont.set(hintLabel, text, scale: 3, color: .white); hintT = 0 }
    func markKill() { killMarkT = 1 }
    func hurt() { hurtT = 1 }

    func callout(_ text: String, color: SKColor) {
        PixelFont.set(calloutLabel, text, scale: 6, color: color.blended(withFraction: 0.25, of: .white) ?? color)
        calloutT = 0
    }

    func addKill(killer: Fighter?, victim: Fighter, weapon: Int, time: Double) {
        let line = SKNode()
        var x: CGFloat = 0
        func add(_ n: SKSpriteNode) { n.anchorPoint = CGPoint(x: 1, y: 0.5); n.position = CGPoint(x: x, y: 0); line.addChild(n); x -= n.size.width + 6 }
        add(PixelFont.label(victim.name, scale: 2, color: victim.color.blended(withFraction: 0.3, of: .white) ?? victim.color))
        if let killer, killer !== victim {
            let sz = Weapons.all[weapon].art.svg.size
            add(SKSpriteNode(texture: Weapons.texture(weapon), size: CGSize(width: sz.width * 0.6, height: sz.height * 0.6)))
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
        guard let text, !cinematic else { banner.isHidden = true; bannerSub.isHidden = true; return }
        PixelFont.set(banner, text, scale: 10, color: color)
        banner.isHidden = false
        if let sub { PixelFont.set(bannerSub, sub, scale: 3, color: .white); bannerSub.isHidden = false } else { bannerSub.isHidden = true }
    }
}
