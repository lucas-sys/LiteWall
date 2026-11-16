// Verifies that LiteWall's windows are actually at the desktop level.
//
// Usage: window-probe [owner-name]     (default: 轻壁纸)
// Run this while LiteWall.app is running. Exits non-zero when no desktop-level
// window is found, or when a window sits at an unexpected layer.

import CoreGraphics
import Foundation

let ownerName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "轻壁纸"
let expectedLayer = Int32(CGWindowLevelForKey(.desktopWindow)) + 1

let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
    as? [[String: Any]]) ?? []
let mine = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == ownerName }

print("kCGDesktopWindowLevel = \(CGWindowLevelForKey(.desktopWindow))")
print("expected window layer = \(expectedLayer)")
print("matching on-screen windows = \(mine.count)")

var desktopCount = 0
for info in mine {
    let layer = (info[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? Int32.min
    let bounds = info[kCGWindowBounds as String] ?? "?"
    let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
    print("  layer=\(layer) windowID=\(number) bounds=\(bounds)")
    if layer == expectedLayer { desktopCount += 1 }
}

guard desktopCount > 0 else {
    FileHandle.standardError.write(Data("[window-probe] no desktop-level window found\n".utf8))
    exit(1)
}
print("OK: \(desktopCount) desktop-level window(s)")
