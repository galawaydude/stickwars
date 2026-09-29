import Foundation

/// Tiny runnable self-check for pure logic: `STICKTOP --selfcheck`.
enum SelfCheck {
    static func run() -> Bool {
        var ok = true
        func check(_ c: Bool, _ msg: String) { print((c ? "ok   " : "FAIL ") + msg); if !c { ok = false } }
        check(clamp(5, 0, 3) == 3, "clamp")
        print(ok ? "selfcheck passed" : "selfcheck FAILED")
        return ok
    }
}
