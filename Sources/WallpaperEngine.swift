import AppKit
import CoreGraphics

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns one borderless, desktop-level window per physical display.
///
/// The window sits one level above `kCGDesktopWindowLevel` and below the desktop
/// icon layer, so Finder icons and the menu bar stay usable. Click-through is
/// unconditional: this app is a renderer, never an input target.
final class WallpaperEngine {
    static let shared = WallpaperEngine()

    /// WEShim.js source, loaded from the app bundle at launch.
    var shimSource: String = ""

    private struct ScreenState {
        let window: DesktopWindow
        var renderer: WallpaperRendering?
        var itemID: String?
    }

    private var states: [CGDirectDisplayID: ScreenState] = [:]
    private var currentItem: WallpaperItem?
    private var volume: Float = 0
    private var fps: Int = 30
    private var slideshowInterval: Int = 12
    private var manualPause = false
    private var automaticPause = false
    private var isPaused: Bool { manualPause || automaticPause }

    private init() {}

    // MARK: - Wallpaper selection

    func apply(_ item: WallpaperItem, volume: Float, fps: Int) {
        currentItem = item
        self.volume = min(max(volume, 0), 1)
        self.fps = max(1, min(120, fps))
        syncScreens(forceRenderer: true)
        // A freshly created renderer reads project.json defaults; re-apply the
        // user's saved interval so switching wallpapers never resets it.
        pushProperty("interval", value: slideshowInterval)
    }

    /// Called on display configuration changes (plug/unplug, resolution, Spaces).
    func screensDidChange() {
        syncScreens(forceRenderer: false)
    }

    // MARK: - Playback controls

    func setManualPaused(_ value: Bool) {
        manualPause = value
        applyPlaybackState()
    }

    /// Sleep / full-screen suspension is tracked separately from the user's
    /// explicit pause so that resuming a display never overrides a manual pause.
    func setAutomaticPaused(_ value: Bool) {
        guard automaticPause != value else { return }
        automaticPause = value
        applyPlaybackState()
    }

    func setVolume(_ value: Float) {
        volume = min(max(value, 0), 1)
        for id in states.keys { states[id]?.renderer?.setVolume(volume) }
    }

    func setFPS(_ value: Int) {
        fps = max(1, min(120, value))
        for id in states.keys { states[id]?.renderer?.setFPS(fps) }
    }

    /// Applies immediately to any running web wallpaper and is remembered for
    /// future wallpaper switches. Non-web renderers ignore it.
    func setSlideshowInterval(_ seconds: Int) {
        slideshowInterval = max(2, min(300, seconds))
        pushProperty("interval", value: slideshowInterval)
    }

    private func pushProperty(_ key: String, value: Any) {
        let payload: [String: Any] = [key: ["value": value]]
        for id in states.keys { states[id]?.renderer?.applyProperties(payload) }
    }

    func shutDown() {
        for id in states.keys { states[id]?.window.orderOut(nil) }
        states.removeAll()
    }

    // MARK: - Window management

    private func syncScreens(forceRenderer: Bool) {
        let screens = NSScreen.screens
        let activeIDs = Set(screens.map(\.displayID))

        for id in Array(states.keys) where !activeIDs.contains(id) {
            states[id]?.window.orderOut(nil)
            states.removeValue(forKey: id)
        }

        for screen in screens {
            let id = screen.displayID
            if states[id] == nil {
                states[id] = ScreenState(window: makeWindow(for: screen), renderer: nil, itemID: nil)
            } else {
                states[id]?.window.setFrame(screen.frame, display: true)
            }

            guard let item = currentItem else { continue }
            let needsRenderer = forceRenderer || states[id]?.itemID != item.id
            guard needsRenderer, var state = states[id] else { continue }

            let renderer = makeRenderer(for: item)
            let content = renderer.view
            content.frame = state.window.contentView?.bounds ?? screen.frame
            content.autoresizingMask = [.width, .height]
            state.window.contentView = content
            state.renderer = renderer
            state.itemID = item.id
            states[id] = state

            renderer.setPaused(isPaused)
            renderer.setVolume(volume)
            renderer.setFPS(fps)
        }
    }

    private func makeWindow(for screen: NSScreen) -> DesktopWindow {
        let window = DesktopWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // kCGDesktopWindowLevel + 1 places the wallpaper above the desktop
        // picture but below desktop icons (kCGDesktopIconWindowLevel).
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }

    private func makeRenderer(for item: WallpaperItem) -> WallpaperRendering {
        switch item.kind {
        case .web:
            if let renderer = WebRenderer(item: item, shimSource: shimSource,
                                          volume: volume, fps: fps, paused: isPaused) {
                return renderer
            }
            return PlaceholderRenderer(message: "Web wallpaper could not be created.\nCheck project.json and the HTML entry file.")
        case .video:
            guard let url = item.entry else {
                return PlaceholderRenderer(message: "Video wallpaper has no playable file.")
            }
            return VideoRenderer(url: url, volume: volume)
        case .image:
            guard let url = item.entry else {
                return PlaceholderRenderer(message: "Image wallpaper has no readable file.")
            }
            return ImageRenderer(url: url)
        case .scene:
            return PlaceholderRenderer(message: "Wallpaper Engine scene wallpapers (scene.pkg) use a proprietary Windows renderer and are not supported.")
        case .unsupported:
            return PlaceholderRenderer(message: "No supported content found in this wallpaper directory.")
        }
    }

    private func applyPlaybackState() {
        for id in states.keys { states[id]?.renderer?.setPaused(isPaused) }
    }
}

/// Visible, low-cost fallback instead of a black screen when a wallpaper
/// cannot be mounted (e.g. a Wallpaper Engine scene package).
private final class PlaceholderRenderer: WallpaperRendering {
    let view: NSView

    init(message: String) {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1).cgColor
        let label = NSTextField(labelWithString: message)
        label.textColor = NSColor(white: 0.75, alpha: 1)
        label.alignment = .center
        label.maximumNumberOfLines = 5
        label.font = .systemFont(ofSize: 15)
        label.frame = container.bounds.insetBy(dx: 80, dy: 80)
        label.autoresizingMask = [.width, .height]
        container.addSubview(label)
        view = container
    }

    func setPaused(_ paused: Bool) {}
    func setVolume(_ volume: Float) {}
    func setFPS(_ fps: Int) {}
}
