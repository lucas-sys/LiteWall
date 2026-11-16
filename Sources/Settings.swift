import Foundation

/// Persisted user preferences. Unknown / missing keys fall back to defaults so
/// that a config written by an older build never prevents the app from starting.
struct Settings: Codable {
    var selectedWallpaperID: String?
    var volume: Float
    var fps: Int
    var pauseOnFullScreen: Bool
    var launchAtLogin: Bool
    var slideshowInterval: Int
    var extraLibraryPaths: [String]

    static let defaults = Settings(
        selectedWallpaperID: nil,
        volume: 0,
        fps: 30,
        pauseOnFullScreen: true,
        launchAtLogin: false,
        slideshowInterval: 12,
        extraLibraryPaths: []
    )

    private enum CodingKeys: String, CodingKey {
        case selectedWallpaperID, volume, fps, pauseOnFullScreen, launchAtLogin,
             slideshowInterval, extraLibraryPaths
    }

    init(selectedWallpaperID: String?, volume: Float, fps: Int,
         pauseOnFullScreen: Bool, launchAtLogin: Bool, slideshowInterval: Int,
         extraLibraryPaths: [String]) {
        self.selectedWallpaperID = selectedWallpaperID
        self.volume = volume
        self.fps = fps
        self.pauseOnFullScreen = pauseOnFullScreen
        self.launchAtLogin = launchAtLogin
        self.slideshowInterval = slideshowInterval
        self.extraLibraryPaths = extraLibraryPaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.defaults
        selectedWallpaperID = try c.decodeIfPresent(String.self, forKey: .selectedWallpaperID)
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? d.volume
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? d.fps
        pauseOnFullScreen = try c.decodeIfPresent(Bool.self, forKey: .pauseOnFullScreen) ?? d.pauseOnFullScreen
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        slideshowInterval = try c.decodeIfPresent(Int.self, forKey: .slideshowInterval) ?? d.slideshowInterval
        extraLibraryPaths = try c.decodeIfPresent([String].self, forKey: .extraLibraryPaths) ?? d.extraLibraryPaths
    }
}

enum AppPaths {
    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LiteWall", isDirectory: true)
    }()

    static let wallpaperDir: URL = supportDir.appendingPathComponent("Wallpapers", isDirectory: true)
    static let configURL: URL = supportDir.appendingPathComponent("config.json")

    static func ensureDirectories() {
        try? FileManager.default.createDirectory(at: wallpaperDir, withIntermediateDirectories: true)
    }

    /// Keep the bundled wallpapers in sync with the installed app.
    ///
    /// `project.json` is user-editable (wallpaper properties), so it is seeded
    /// once and never overwritten. Everything else is app-owned code/assets and
    /// is refreshed from the bundle on every launch — otherwise a wallpaper
    /// fix shipped in a new build would never reach an existing library.
    /// Generated asset directories (images/) are only copied when missing, so
    /// startup does not re-copy tens of megabytes each time.
    static func seedBundledWallpapers() {
        guard let bundled = Bundle.main.url(forResource: "Wallpapers", withExtension: nil) else { return }
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: bundled.path)) ?? []
        for name in names where !name.hasPrefix(".") {
            let srcDir = bundled.appendingPathComponent(name)
            let dstDir = wallpaperDir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: srcDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)

            let files = (try? fm.contentsOfDirectory(
                at: srcDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for file in files {
                let target = dstDir.appendingPathComponent(file.lastPathComponent)
                if file.lastPathComponent == "project.json" {
                    if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: file, to: target) }
                } else if file.hasDirectoryPath {
                    if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: file, to: target) }
                } else {
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try? fm.copyItem(at: file, to: target)
                }
            }
        }
    }
}

extension Settings {
    static func load() -> Settings {
        guard let data = try? Data(contentsOf: AppPaths.configURL),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .defaults
        }
        return decoded
    }

    func save() {
        AppPaths.ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: AppPaths.configURL, options: .atomic)
    }
}
