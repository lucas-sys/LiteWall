import AppKit

/// NSApplication.delegate is weak; keep the delegate alive for the process
/// lifetime. No storyboard / nib is used, so this is the whole app bootstrap.
private var retainedDelegate: AppDelegate?

@main
struct LiteWallApp {
    static func main() {
        let delegate = AppDelegate()
        retainedDelegate = delegate
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: Settings = .defaults
    private var library: WallpaperLibrary!
    private var menuController: StatusMenuController!
    private var fullScreenTimer: Timer?
    private var sleepPaused = false
    private var manualPaused = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A LaunchAgent login launch can overlap a manual launch. Two instances
        // would each create a desktop window set and decode the wallpaper twice.
        guard !anotherInstanceIsRunning() else {
            NSApp.terminate(nil)
            return
        }

        AppPaths.ensureDirectories()
        AppPaths.seedBundledWallpapers()

        settings = Settings.load()
        library = WallpaperLibrary(settings: settings)
        library.scan()

        WallpaperEngine.shared.shimSource = loadShim()
        setupMenu()
        installObservers()
        // Store the saved interval before the first renderer is created, so
        // apply(_:volume:fps:) replays it instead of the project.json default.
        WallpaperEngine.shared.setSlideshowInterval(settings.slideshowInterval)

        let selected = library.item(withID: settings.selectedWallpaperID) ?? library.items.first
        if let selected {
            // Self-heal a stale or missing selection: persist the wallpaper
            // that is actually being shown so the next launch stays identical.
            if settings.selectedWallpaperID != selected.id {
                settings.selectedWallpaperID = selected.id
                settings.save()
            }
            WallpaperEngine.shared.apply(selected, volume: settings.volume, fps: settings.fps)
        }
        WallpaperEngine.shared.setManualPaused(manualPaused)
        startAutoPauseTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fullScreenTimer?.invalidate()
        WallpaperEngine.shared.shutDown()
        // Preferences are saved at the moment they change. Re-writing them here
        // would let a stale in-memory snapshot overwrite an externally edited
        // config (and silently drop optional keys such as selectedWallpaperID).
    }

    // MARK: - Setup

    private func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID
                && $0.processIdentifier != ownPID
                && !$0.isTerminated
        }
    }

    private func loadShim() -> String {
        guard let url = Bundle.main.url(forResource: "WEShim", withExtension: "js") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func setupMenu() {
        let stateProvider: () -> StatusMenuController.State = { [weak self] in
            guard let self else {
                return StatusMenuController.State(currentID: nil, paused: false, volume: 0,
                                                  fps: 30, pauseOnFullScreen: true,
                                                  launchAtLogin: false, slideshowInterval: 12,
                                                  supportsSlideshow: false, items: [])
            }
            return StatusMenuController.State(
                currentID: self.settings.selectedWallpaperID,
                paused: self.manualPaused,
                volume: self.settings.volume,
                fps: self.settings.fps,
                pauseOnFullScreen: self.settings.pauseOnFullScreen,
                launchAtLogin: LaunchAtLogin.isEnabled,
                slideshowInterval: self.settings.slideshowInterval,
                supportsSlideshow: self.library.item(withID: self.settings.selectedWallpaperID)?.properties["interval"] != nil,
                items: self.library.items
            )
        }

        menuController = StatusMenuController(
            stateProvider: stateProvider,
            actions: StatusMenuController.Actions(
                select: { [weak self] item in self?.select(item) },
                pause: { [weak self] value in
                    self?.manualPaused = value
                    WallpaperEngine.shared.setManualPaused(value)
                },
                volume: { [weak self] value in
                    self?.settings.volume = value
                    self?.settings.save()
                    WallpaperEngine.shared.setVolume(value)
                },
                fps: { [weak self] value in
                    self?.settings.fps = value
                    self?.settings.save()
                    WallpaperEngine.shared.setFPS(value)
                },
                slideshowInterval: { [weak self] value in
                    self?.settings.slideshowInterval = value
                    self?.settings.save()
                    WallpaperEngine.shared.setSlideshowInterval(value)
                },
                fullScreenPause: { [weak self] value in
                    self?.settings.pauseOnFullScreen = value
                    self?.settings.save()
                    self?.evaluateAutoPause()
                },
                launchAtLogin: { [weak self] value in
                    self?.settings.launchAtLogin = value
                    self?.settings.save()
                },
                rescan: { [weak self] in self?.rescan() }
            )
        )
    }

    private func installObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func startAutoPauseTimer() {
        fullScreenTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.evaluateAutoPause()
        }
        fullScreenTimer?.tolerance = 1.0
    }

    // MARK: - Actions

    private func select(_ item: WallpaperItem) {
        settings.selectedWallpaperID = item.id
        settings.save()
        WallpaperEngine.shared.apply(item, volume: settings.volume, fps: settings.fps)
    }

    private func rescan() {
        library.scan()
        if library.item(withID: settings.selectedWallpaperID) == nil {
            settings.selectedWallpaperID = library.items.first?.id
            if let first = library.items.first {
                WallpaperEngine.shared.apply(first, volume: settings.volume, fps: settings.fps)
            }
        }
        settings.save()
    }

    private func evaluateAutoPause() {
        let covered = settings.pauseOnFullScreen && FullScreenDetector.hasFullScreenApp()
        WallpaperEngine.shared.setAutomaticPaused(sleepPaused || covered)
    }

    @objc private func screenParametersDidChange() {
        WallpaperEngine.shared.screensDidChange()
    }

    @objc private func screensDidSleep() {
        sleepPaused = true
        evaluateAutoPause()
    }

    @objc private func screensDidWake() {
        sleepPaused = false
        evaluateAutoPause()
    }
}
