import AppKit

/// Every renderer owns exactly one view that fills a desktop-level window.
protocol WallpaperRendering: AnyObject {
    var view: NSView { get }
    func setPaused(_ paused: Bool)
    func setVolume(_ volume: Float)
    func setFPS(_ fps: Int)
    /// Push Wallpaper Engine user properties into an already-running wallpaper
    /// without rebuilding the renderer (used by the interval menu).
    func applyProperties(_ properties: [String: Any])
}

extension WallpaperRendering {
    func applyProperties(_ properties: [String: Any]) {}
}
