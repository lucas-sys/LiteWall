import AppKit

/// Menu-bar-only control surface. The menu is rebuilt on every open so that
/// state (selection, pause, volume, login item) can never go stale.
final class StatusMenuController: NSObject, NSMenuDelegate {

    struct State {
        var currentID: String?
        var paused: Bool
        var volume: Float
        var fps: Int
        var pauseOnFullScreen: Bool
        var launchAtLogin: Bool
        var slideshowInterval: Int
        var supportsSlideshow: Bool
        var items: [WallpaperItem]
    }

    struct Actions {
        var select: (WallpaperItem) -> Void
        var pause: (Bool) -> Void
        var volume: (Float) -> Void
        var fps: (Int) -> Void
        var slideshowInterval: (Int) -> Void
        var fullScreenPause: (Bool) -> Void
        var launchAtLogin: (Bool) -> Void
        var rescan: () -> Void
    }

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let stateProvider: () -> State
    private let actions: Actions

    init(stateProvider: @escaping () -> State, actions: Actions) {
        self.stateProvider = stateProvider
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let image = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: "LiteWall") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "LW"
        }
        statusItem.button?.toolTip = "LiteWall · 轻壁纸"
        menu.delegate = self
        statusItem.menu = menu
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuild() }

    // MARK: - Menu construction

    private func rebuild() {
        menu.removeAllItems()
        let state = stateProvider()

        let header = NSMenuItem(title: "LiteWall · 轻壁纸", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let current = state.items.first { $0.id == state.currentID }
        let currentItem = NSMenuItem(title: "当前：" + (current?.title ?? "未选择"), action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        menu.addItem(.separator())

        addWallpaperSection(state)
        menu.addItem(.separator())

        addToggle(title: state.paused ? "恢复播放" : "暂停壁纸",
                  isOn: state.paused, key: "p", action: #selector(togglePause))
        addVolumeSection(state.volume)
        addFPSSection(state.fps)
        if state.supportsSlideshow {
            addSlideshowIntervalSection(state.slideshowInterval)
        }
        menu.addItem(.separator())

        addToggle(title: "全屏应用时自动暂停", isOn: state.pauseOnFullScreen,
                  key: "", action: #selector(toggleFullScreenPause))
        let login = make("开机自启", #selector(toggleLaunchAtLogin), key: "")
        login.state = state.launchAtLogin ? .on : .off
        login.toolTip = "登录项：~/Library/LaunchAgents/\(LaunchAtLogin.label).plist（下次登录生效）"
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(make("打开壁纸目录", #selector(openLibrary), key: ""))
        menu.addItem(make("重新扫描壁纸", #selector(rescan), key: "r"))
        menu.addItem(make("关于 LiteWall", #selector(showAbout), key: ""))
        menu.addItem(.separator())
        menu.addItem(make("退出 LiteWall", #selector(quit), key: "q"))
    }

    private func addWallpaperSection(_ state: State) {
        guard !state.items.isEmpty else {
            menu.addItem(make("壁纸库为空 — 点击打开壁纸目录", #selector(openLibrary), key: ""))
            return
        }
        let group = NSMenuItem(title: "选择壁纸", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for item in state.items {
            let entry = NSMenuItem(title: item.title, action: #selector(selectWallpaper(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.id
            entry.state = item.id == state.currentID ? .on : .off
            entry.toolTip = item.subtitle
            submenu.addItem(entry)
        }
        group.submenu = submenu
        menu.addItem(group)
    }

    private func addVolumeSection(_ volume: Float) {
        let group = NSMenuItem(title: "音量", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for level: Float in [0, 0.25, 0.5, 0.75, 1.0] {
            let label = level == 0 ? "静音" : "\(Int(level * 100))%"
            let entry = NSMenuItem(title: label, action: #selector(setVolume(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = level
            entry.state = abs(volume - level) < 0.001 ? .on : .off
            submenu.addItem(entry)
        }
        group.submenu = submenu
        menu.addItem(group)
    }

    private func addFPSSection(_ fps: Int) {
        let group = NSMenuItem(title: "网页壁纸帧率上限", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in [15, 24, 30, 60] {
            let entry = NSMenuItem(title: "\(value) FPS", action: #selector(setFPS(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = value
            entry.state = fps == value ? .on : .off
            submenu.addItem(entry)
        }
        group.submenu = submenu
        menu.addItem(group)
    }

    private func addSlideshowIntervalSection(_ current: Int) {
        let group = NSMenuItem(title: "壁纸切换间隔", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for seconds in [5, 10, 15, 20, 30, 60, 120] {
            let entry = NSMenuItem(title: "\(seconds) 秒",
                                   action: #selector(setSlideshowInterval(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = seconds
            entry.state = current == seconds ? .on : .off
            submenu.addItem(entry)
        }
        group.submenu = submenu
        group.toolTip = "实时生效，无需重新选择壁纸"
        menu.addItem(group)
    }

    private func addToggle(title: String, isOn: Bool, key: String, action: Selector) {
        let entry = make(title, action, key: key)
        entry.state = isOn ? .on : .off
        menu.addItem(entry)
    }

    private func make(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // MARK: - Actions

    @objc private func selectWallpaper(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = stateProvider().items.first(where: { $0.id == id }) else { return }
        actions.select(item)
    }

    @objc private func togglePause() { actions.pause(!stateProvider().paused) }

    @objc private func setVolume(_ sender: NSMenuItem) {
        guard let level = (sender.representedObject as? NSNumber)?.floatValue else { return }
        actions.volume(level)
    }

    @objc private func setFPS(_ sender: NSMenuItem) {
        guard let value = (sender.representedObject as? NSNumber)?.intValue else { return }
        actions.fps(value)
    }

    @objc private func setSlideshowInterval(_ sender: NSMenuItem) {
        guard let value = (sender.representedObject as? NSNumber)?.intValue else { return }
        actions.slideshowInterval(value)
    }

    @objc private func toggleFullScreenPause() {
        actions.fullScreenPause(!stateProvider().pauseOnFullScreen)
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !stateProvider().launchAtLogin
        do {
            try LaunchAtLogin.setEnabled(enable)
            actions.launchAtLogin(enable)
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机自启"
            alert.informativeText = """
            \(error.localizedDescription)

            登录项目标路径：\(LaunchAtLogin.plistURL.path)
            也可以手动在「系统设置 → 通用 → 登录项与扩展」中添加 LiteWall。
            """
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func openLibrary() {
        AppPaths.ensureDirectories()
        NSWorkspace.shared.open(AppPaths.wallpaperDir)
    }

    @objc private func rescan() { actions.rescan() }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "LiteWall · 轻壁纸 1.0"
        alert.informativeText = """
        面向 macOS 的轻量化动态壁纸宿主。

        • Web / Canvas 壁纸：兼容 Wallpaper Engine 的 project.json 与 10 项 window.wallpaper* 作者 API
        • 视频壁纸：AVPlayer 无缝循环
        • 静态图、多显示器、全屏/睡眠自动暂停

        壁纸格式契约由 REA 静态分析验证，详见 docs/REA-FINDINGS.md。
        Scene（scene.pkg）格式未实现。
        """
        alert.alertStyle = .informational
        alert.runModal()
    }
}
