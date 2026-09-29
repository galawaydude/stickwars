import AppKit
import ScreenCaptureKit

/// One on-screen window from CGWindowList, in global top-left point coordinates.
struct WindowInfo {
    var id: CGWindowID
    var pid: pid_t
    var owner: String
    var bounds: CGRect
    var layer: Int
}

enum ScreenCapture {
    /// True when the image is (nearly) one flat colour, e.g. a capture without permission in effect.
    static func isBlank(_ img: CGImage) -> Bool {
        let w = 64, h = 40
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.interpolationQuality = .low
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let p = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        var lo: UInt8 = 255, hi: UInt8 = 0
        for i in 0..<(w * h) { lo = min(lo, p[i]); hi = max(hi, p[i]) }
        return Int(hi) - Int(lo) < 10
    }

    private static var cachedFilter: SCContentFilter?

    /// Front-to-back list of visible windows not owned by us.
    static func windowList() -> [WindowInfo] {
        guard let arr = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = getpid()
        var out: [WindowInfo] = []
        for d in arr {
            guard let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let bd = d[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
            let alpha = d[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.05, b.width > 20, b.height > 20 else { continue }
            out.append(WindowInfo(id: d[kCGWindowNumber as String] as? CGWindowID ?? 0, pid: pid,
                                  owner: d[kCGWindowOwnerName as String] as? String ?? "",
                                  bounds: b, layer: d[kCGWindowLayer as String] as? Int ?? 0))
        }
        return out
    }

    /// Full-resolution sRGB screenshot of the main display, excluding this app, no cursor.
    static func capture() async throws -> CGImage {
        let filter: SCContentFilter
        if let f = cachedFilter, f.contentRect.size == NSScreen.screens[0].frame.size {
            filter = f
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let did = CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == did }) ?? content.displays.first else {
                throw NSError(domain: "STICKWARS", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display"])
            }
            let me = content.applications.filter { $0.processID == getpid() }
            filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            cachedFilter = filter
        }
        let cfg = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        cfg.width = Int(filter.contentRect.width * scale)
        cfg.height = Int(filter.contentRect.height * scale)
        cfg.showsCursor = false
        cfg.colorSpaceName = CGColorSpace.sRGB
        cfg.captureResolution = .best
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        } catch {
            cachedFilter = nil
            throw error
        }
    }
}
