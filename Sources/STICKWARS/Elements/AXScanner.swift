import AppKit
import ApplicationServices

enum AXRoleKind { case text, control, image, textArea }

/// An accessibility element frame in global top-left points.
struct AXItem {
    var rect: CGRect
    var kind: AXRoleKind
}

/// Walks the accessibility trees of visible windows under a hard budget, collecting frames of
/// leaf-ish elements that are actually visible on screen.
enum AXScanner {
    private static let roles: [String: AXRoleKind] = [
        "AXStaticText": .text, "AXHeading": .text, "AXLink": .text, "AXCell": .text, "AXTab": .text,
        "AXButton": .control, "AXTextField": .control, "AXCheckBox": .control, "AXPopUpButton": .control,
        "AXMenuButton": .control, "AXRadioButton": .control, "AXImage": .image, "AXTextArea": .textArea,
    ]
    /// Roles whose children we don't need to visit.
    private static let terminal: Set<String> = ["AXStaticText", "AXButton", "AXImage", "AXTextField", "AXCheckBox",
                                                "AXPopUpButton", "AXMenuButton", "AXRadioButton"]
    private static let chromium: Set<String> = ["com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser",
                                                "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
                                                "com.operasoftware.Opera", "org.chromium.Chromium"]

    static func scan(windows: [WindowInfo], screen: CGSize, budget: Double = 0.040, maxNodes: Int = 3000) -> [AXItem] {
        guard AXIsProcessTrusted() else { return [] }
        let deadline = now() + budget
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.010)
        let screenRect = CGRect(origin: .zero, size: screen)
        var out: [AXItem] = []
        var nodes = 0
        var seenPids = Set<pid_t>()
        let normal = windows.filter { $0.layer == 0 }

        for w in normal where !seenPids.contains(w.pid) {
            seenPids.insert(w.pid)
            if now() > deadline || nodes >= maxNodes { break }
            let app = AXUIElementCreateApplication(w.pid)
            AXUIElementSetMessagingTimeout(app, 0.010)

            // Chromium / Electron expose web content only with these flags set.
            var restore: [(CFString, Bool)] = []
            if let ra = NSRunningApplication(processIdentifier: w.pid) {
                let bid = ra.bundleIdentifier ?? ""
                let electron = ra.bundleURL.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) } ?? false
                if chromium.contains(bid) { restore.append(("AXEnhancedUserInterface" as CFString, flag(app, "AXEnhancedUserInterface"))) }
                if electron { restore.append(("AXManualAccessibility" as CFString, flag(app, "AXManualAccessibility"))) }
                for (attr, _) in restore { AXUIElementSetAttributeValue(app, attr, kCFBooleanTrue) }
            }
            defer { for (attr, was) in restore where !was { AXUIElementSetAttributeValue(app, attr, kCFBooleanFalse) } }

            var winsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &winsRef) == .success,
                  let axWins = winsRef as? [AXUIElement] else { continue }
            for axw in axWins {
                guard let wf = frame(axw), wf.width > 20 else { continue }
                // Match to a CG window of this pid to know which windows are in front of it.
                guard let wi = windows.firstIndex(where: { $0.pid == w.pid && abs($0.bounds.minX - wf.minX) < 4 && abs($0.bounds.minY - wf.minY) < 30 && abs($0.bounds.width - wf.width) < 8 }) else { continue }
                let front = windows[..<wi].map(\.bounds)
                let visible = wf.intersection(screenRect)
                let winArea = wf.width * wf.height
                var stack: [(AXUIElement, Int)] = [(axw, 0)]
                while let (el, depth) = stack.popLast() {
                    if nodes >= maxNodes || now() > deadline { break }
                    nodes += 1
                    guard let (role, rect, kids) = info(el) else { continue }
                    if let r = rect {
                        if r.width > 0, r.height > 0, !r.intersects(visible) { continue } // off-screen subtree
                        if let kind = roles[role], r.width >= 4, r.height >= 4, r.width * r.height <= winArea * 0.6 {
                            let onScreen = r.intersection(visible)
                            if onScreen.width * onScreen.height >= r.width * r.height * 0.5,
                               !front.contains(where: { let o = $0.intersection(r); return o.width * o.height > r.width * r.height * 0.3 }) {
                                out.append(AXItem(rect: r, kind: kind))
                            }
                        }
                    }
                    if terminal.contains(role) || depth >= 40 { continue }
                    for k in kids.reversed() { stack.append((k, depth + 1)) }
                }
            }
        }
        // Drop containers: items that fully contain another item.
        var keep = [Bool](repeating: true, count: out.count)
        for i in out.indices where keep[i] {
            for j in out.indices where i != j && keep[j] {
                guard out[i].rect.width * out[i].rect.height > out[j].rect.width * out[j].rect.height * 1.5,
                      out[i].rect.insetBy(dx: -1, dy: -1).contains(out[j].rect) else { continue }
                // a button keeps its label; any other container gives way to its children
                if out[i].kind == .control && out[j].kind == .text { keep[j] = false } else { keep[i] = false; break }
            }
        }
        return out.indices.filter { keep[$0] }.map { out[$0] }
    }

    private static func flag(_ el: AXUIElement, _ attr: String) -> Bool {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success && (v as? Bool ?? false)
    }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    /// Role, frame and children in one IPC round-trip.
    private static func info(_ el: AXUIElement) -> (String, CGRect?, [AXUIElement])? {
        let attrs = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute] as CFArray
        var vals: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(el, attrs, AXCopyMultipleAttributeOptions(rawValue: 0), &vals) == .success,
              let arr = vals as? [AnyObject], arr.count == 4 else { return nil }
        let role = arr[0] as? String ?? ""
        var rect: CGRect?
        if CFGetTypeID(arr[1]) == AXValueGetTypeID(), CFGetTypeID(arr[2]) == AXValueGetTypeID() {
            var pt = CGPoint.zero, sz = CGSize.zero
            let pv = arr[1] as! AXValue, sv = arr[2] as! AXValue
            if AXValueGetType(pv) == .cgPoint, AXValueGetType(sv) == .cgSize {
                AXValueGetValue(pv, .cgPoint, &pt); AXValueGetValue(sv, .cgSize, &sz)
                rect = CGRect(origin: pt, size: sz)
            }
        }
        let kids = arr[3] as? [AXUIElement] ?? []
        return (role, rect, kids)
    }
}
