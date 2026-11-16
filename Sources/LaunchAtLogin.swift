import Foundation

/// Per-user login item backed by a LaunchAgent plist.
///
/// `SMAppService.mainApp.register()` requires a properly signed app in a
/// standard location; this project ships ad-hoc signed, so it can fail with an
/// opaque error. A `~/Library/LaunchAgents` plist works with ad-hoc signatures,
/// is inspectable by the user, and needs no admin rights or system extension.
///
/// The agent points at `Bundle.main.bundlePath`, i.e. whichever copy is
/// currently running. Installing into ~/Applications and toggling from the
/// menu therefore stay consistent.
enum LaunchAtLogin {
    static let label = "dev.litewall.LiteWall"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(label + ".plist")
    }

    /// The plist on disk is the single source of truth for the menu checkbox.
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let fm = FileManager.default
        if enabled {
            try fm.createDirectory(at: plistURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            let bundlePath = Bundle.main.bundlePath
            guard bundlePath.hasSuffix(".app") else {
                throw LaunchAtLoginError.notAnAppBundle(bundlePath)
            }
            let job: [String: Any] = [
                "Label": label,
                // `open` is required: launching the Mach-O directly makes
                // Bundle.main resolve to Contents/MacOS, so WEShim.js and the
                // bundled wallpapers would not be found.
                "ProgramArguments": ["/usr/bin/open", bundlePath],
                "RunAtLoad": true,
                "KeepAlive": false,
                "LimitLoadToSessionType": "Aqua",
                "ProcessType": "Interactive"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: job,
                                                          format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } else {
            if fm.fileExists(atPath: plistURL.path) {
                try fm.removeItem(at: plistURL)
            }
            // Best effort: unload an already-bootstrapped job in this session.
            // A missing job is expected and is not an error.
            launchctl(["bootout", "gui/\(getuid())/\(label)"])
        }
    }

    /// Non-throwing, best-effort launchctl invocation. Output is discarded by
    /// design: this is a convenience cleanup, not a state-changing operation
    /// the user needs to reason about.
    @discardableResult
    static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case notAnAppBundle(String)

    var errorDescription: String? {
        switch self {
        case .notAnAppBundle(let path):
            return "当前进程不是 .app bundle（\(path)）。请用 open 启动 LiteWall.app，不要直接运行内嵌可执行文件。"
        }
    }
}
