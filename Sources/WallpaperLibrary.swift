import Foundation

/// Minimal JSON value type: `project.json` property values may be strings,
/// numbers, booleans, objects or arrays.
indirect enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    /// Foundation representation, suitable for `JSONSerialization`.
    var raw: Any {
        switch self {
        case .string(let v): return v
        case .number(let v): return v
        case .bool(let v): return v
        case .object(let v): return v.mapValues { $0.raw }
        case .array(let v): return v.map { $0.raw }
        case .null: return NSNull()
        }
    }
}

enum WallpaperKind: String {
    case web, video, image
    /// Wallpaper Engine "scene" (scene.pkg / scene.json) uses a proprietary
    /// binary format and a Windows renderer. It is deliberately not mounted.
    case scene
    case unsupported
}

struct WallpaperItem: Identifiable {
    let id: String
    let title: String
    let directory: URL
    let kind: WallpaperKind
    let entry: URL?
    /// `general.properties`, keyed by property name, restricted to `{value: ...}`.
    /// This is the exact shape `applyUserProperties` receives in Wallpaper Engine.
    let properties: [String: Any]
    let declaredType: String?
    let kindReason: String
    let mismatch: Bool
    let preview: URL?

    var subtitle: String {
        switch kind {
        case .web: return "Web / Canvas · \(kindReason)"
        case .video: return "Video · \(entry?.lastPathComponent ?? "—")"
        case .image: return "Image · \(entry?.lastPathComponent ?? "—")"
        case .scene: return "WE scene (not supported on macOS)"
        case .unsupported: return "Unsupported · \(kindReason)"
        }
    }
}

private struct ProjectFile: Decodable {
    let title: String?
    let type: String?
    let file: String?
    let preview: String?
    let general: General?

    struct General: Decodable {
        let type: String?
        let file: String?
        let properties: [String: Property]?
    }

    struct Property: Decodable {
        let value: JSONValue?
    }
}

final class WallpaperLibrary {
    private(set) var items: [WallpaperItem] = []
    private let settings: Settings
    private static let videoExtensions: Set<String> = ["mp4", "webm", "mov", "m4v", "mkv"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff"]
    private static let htmlNames = ["index.html", "index.htm", "index.xhtml"]

    init(settings: Settings) { self.settings = settings }

    func scan() {
        var roots = [AppPaths.wallpaperDir]
        roots += settings.extraLibraryPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        var found: [WallpaperItem] = []
        for root in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for url in entries where (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if let item = Self.parse(url) { found.append(item) }
            }
            // A single loose media file in the library root is also a wallpaper.
            for url in entries where (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
                guard let item = Self.parseLooseMedia(url) else { continue }
                found.append(item)
            }
        }
        items = found.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func item(withID id: String?) -> WallpaperItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    // MARK: - Classification

    /// Content takes precedence over the declaration in `project.json`; the
    /// declared type is retained only as a diagnostic. This mirrors the
    /// detection order documented in docs/REA-FINDINGS.md.
    static func parse(_ dir: URL) -> WallpaperItem? {
        let fm = FileManager.default
        let projectURL = dir.appendingPathComponent("project.json")
        let project: ProjectFile? = {
            guard let data = try? Data(contentsOf: projectURL) else { return nil }
            return try? JSONDecoder().decode(ProjectFile.self, from: data)
        }()

        let declaredType = (project?.type ?? project?.general?.type)?.lowercased()
        let declaredFile = project?.file ?? project?.general?.file
        let title = project?.title ?? dir.lastPathComponent

        var properties: [String: Any] = [:]
        if let p = project?.general?.properties {
            for (key, prop) in p {
                properties[key] = ["value": prop.value?.raw ?? NSNull()]
            }
        }

        let files = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []

        func file(named: String) -> URL? {
            files.first { $0.lastPathComponent.caseInsensitiveCompare(named) == .orderedSame }
        }
        func matching(extension ext: String) -> [URL] {
            files.filter { $0.pathExtension.lowercased() == ext && !$0.hasDirectoryPath }
        }
        let videos = Self.videoExtensions.flatMap { matching(extension: $0) }
        let images = Self.imageExtensions.flatMap { matching(extension: $0) }
        let htmls = files.filter { ["html", "htm", "xhtml"].contains($0.pathExtension.lowercased()) }
        let scenes = files.filter {
            let n = $0.lastPathComponent.lowercased()
            return n == "scene.pkg" || n == "scene.json" || $0.pathExtension.lowercased() == "pkg"
                || $0.pathExtension.lowercased() == "mpkg"
        }
        let largest = { (urls: [URL]) -> URL? in
            urls.max { a, b in
                let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let sb = (try? b.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return sa < sb
            }
        }

        // 1. Executable wallpapers are never mounted.
        if let t = declaredType, ["application", "exe", "app"].contains(t) {
            return make(dir: dir, title: title, kind: .unsupported, entry: nil,
                        properties: properties, declared: declaredType,
                        reason: "excluded-application", mismatch: false, preview: previewURL(project, dir, file))
        }
        // 2. Scene containers win over HTML entries.
        if !scenes.isEmpty {
            return make(dir: dir, title: title, kind: .scene, entry: scenes.first,
                        properties: properties, declared: declaredType,
                        reason: "scene-container", mismatch: declaredType != "scene",
                        preview: previewURL(project, dir, file))
        }
        // 3. A declared video wallpaper with a real video file.
        if declaredType == "video", let v = largest(videos) {
            return make(dir: dir, title: title, kind: .video, entry: v,
                        properties: properties, declared: declaredType,
                        reason: "declared-video", mismatch: false, preview: previewURL(project, dir, file))
        }
        // 4. HTML entry priority: declared file > index.* > shallowest html.
        var htmlEntry: URL? = nil
        var htmlReason = ""
        if let f = declaredFile, f.lowercased().hasSuffix(".html") || f.lowercased().hasSuffix(".htm"), let u = file(named: f) {
            htmlEntry = u; htmlReason = "declared-html"
        } else if let u = Self.htmlNames.compactMap({ file(named: $0) }).first {
            htmlEntry = u; htmlReason = "html-entry"
        } else if let u = htmls.min(by: { $0.path.count < $1.path.count }) {
            htmlEntry = u; htmlReason = "html-entry"
        }
        // 5. html + mp4 without a video declaration resolves to web.
        if let u = htmlEntry, declaredType != "video" {
            return make(dir: dir, title: title, kind: .web, entry: u,
                        properties: properties, declared: declaredType,
                        reason: htmlReason, mismatch: declaredType != nil && declaredType != "web",
                        preview: previewURL(project, dir, file))
        }
        // 6. Bare video / image directory.
        if let v = largest(videos) {
            return make(dir: dir, title: title, kind: .video, entry: v,
                        properties: properties, declared: declaredType,
                        reason: "video-file", mismatch: declaredType == "web",
                        preview: previewURL(project, dir, file))
        }
        if let i = largest(images) {
            return make(dir: dir, title: title, kind: .image, entry: i,
                        properties: properties, declared: declaredType,
                        reason: "image-file", mismatch: declaredType == "web",
                        preview: previewURL(project, dir, file))
        }
        return make(dir: dir, title: title, kind: .unsupported, entry: nil,
                    properties: properties, declared: declaredType,
                    reason: files.isEmpty ? "no-files" : "declared-unmatched",
                    mismatch: declaredType != nil, preview: previewURL(project, dir, file))
    }

    private static func parseLooseMedia(_ url: URL) -> WallpaperItem? {
        let ext = url.pathExtension.lowercased()
        let kind: WallpaperKind
        if Self.videoExtensions.contains(ext) { kind = .video }
        else if Self.imageExtensions.contains(ext) { kind = .image }
        else { return nil }
        return make(dir: url.deletingLastPathComponent(), title: url.deletingPathExtension().lastPathComponent,
                    kind: kind, entry: url, properties: [:], declared: nil,
                    reason: "loose-media", mismatch: false, preview: nil)
    }

    private static func previewURL(_ project: ProjectFile?, _ dir: URL,
                                   _ file: (String) -> URL?) -> URL? {
        guard let name = project?.preview, let u = file(name) else { return nil }
        return u
    }

    private static func make(dir: URL, title: String, kind: WallpaperKind, entry: URL?,
                             properties: [String: Any], declared: String?, reason: String,
                             mismatch: Bool, preview: URL?) -> WallpaperItem {
        WallpaperItem(
            id: dir.lastPathComponent + "#" + (entry?.lastPathComponent ?? kind.rawValue),
            title: title, directory: dir, kind: kind, entry: entry,
            properties: properties, declaredType: declared, kindReason: reason,
            mismatch: mismatch, preview: preview
        )
    }
}
