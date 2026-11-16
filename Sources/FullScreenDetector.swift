import AppKit
import CoreGraphics

/// Heuristic full-screen detection used to suspend rendering while another app
/// covers a display. Based on the public window list, not Accessibility access.
///
/// Known limitation (documented): a merely maximised window of near-screen size
/// is indistinguishable from a true native full-screen Space using this API, so
/// it may produce a false positive. It never produces a false "resume" that
/// keeps rendering behind an opaque full-screen app.
enum FullScreenDetector {
    static func hasFullScreenApp() -> Bool {
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let screenSizes = NSScreen.screens.map { $0.frame.size }
        guard !screenSizes.isEmpty else { return false }

        for info in infos {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID != ownPID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  width > 0, height > 0 else { continue }

            for size in screenSizes {
                if width >= Double(size.width) * 0.98 && height >= Double(size.height) * 0.98 {
                    return true
                }
            }
        }
        return false
    }
}
