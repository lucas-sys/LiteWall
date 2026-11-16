import AppKit
import WebKit

/// Hosts a Wallpaper Engine "web" wallpaper in WKWebView.
///
/// Injection order at document start is: seed → WEShim.js → author scripts.
/// This ordering is required: WE wallpapers assign `wallpaperPropertyListener`
/// as a global outside any DOM event, and expect the initial property snapshot
/// to be available immediately afterwards.
final class WebRenderer: NSObject, WallpaperRendering, WKNavigationDelegate, WKScriptMessageHandler {

    let view: NSView
    private let webView: WKWebView
    private let container: WebHostView
    private let userContentController: WKUserContentController
    private var paused: Bool
    private var volume: Float
    private var fps: Int
    private var ready = false
    private var pendingJavaScript: [String] = []

    private static let assetExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif", "svg", "bmp", "mp4", "webm", "mov", "m4v"
    ]

    init?(item: WallpaperItem, shimSource: String, volume: Float, fps: Int, paused: Bool) {
        guard let entry = item.entry, FileManager.default.fileExists(atPath: entry.path) else { return nil }

        self.paused = paused
        self.volume = min(max(volume, 0), 1)
        self.fps = fps

        let seed: [String: Any] = [
            "properties": item.properties,
            "general": ["fps": fps],
            "paused": paused,
            "muted": volume <= 0.001,
            "volume": volume,
            "assets": Self.assetNames(in: item.directory),
            "assetBase": entry.deletingLastPathComponent().absoluteString + "/"
        ]
        // `JSONSerialization` rejects non-property-list values defensively.
        guard let seedData = try? JSONSerialization.data(withJSONObject: seed, options: []),
              let seedJSON = String(data: seedData, encoding: .utf8) else { return nil }

        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: "window.__weSeed = " + seedJSON + ";",
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: shimSource,
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = ucc
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false
        config.websiteDataStore = .default()

        self.userContentController = ucc
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.container = WebHostView(frame: .zero)
        self.view = self.container
        super.init()

        ucc.add(WeakScriptMessageHandler(self), name: "litewall")
        webView.navigationDelegate = self
        container.webView = webView
        webView.autoresizingMask = [.width, .height]
        webView.frame = container.bounds
        // Hidden until the first navigation completes: avoids a white flash
        // while the author document has not painted its own background yet.
        webView.isHidden = true
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.addSubview(webView)

        webView.loadFileURL(entry, allowingReadAccessTo: item.directory)
    }

    deinit {
        userContentController.removeScriptMessageHandler(forName: "litewall")
        webView.stopLoading()
    }

    // MARK: - WallpaperRendering

    func setPaused(_ paused: Bool) {
        self.paused = paused
        run("window.__weBridge && window.__weBridge.setPaused(\(paused ? "true" : "false"))")
    }

    func setVolume(_ volume: Float) {
        self.volume = min(max(volume, 0), 1)
        run(String(format: "window.__weBridge && window.__weBridge.setVolume(%g)", Double(self.volume)))
    }

    func setFPS(_ fps: Int) {
        self.fps = max(1, min(120, fps))
        run("window.__weBridge && window.__weBridge.applyGeneral({fps: \(self.fps)})")
    }

    func applyProperties(_ properties: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: properties, options: []),
              let json = String(data: data, encoding: .utf8) else { return }
        run("window.__weBridge && window.__weBridge.applyProperties(" + json + ")")
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        markReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error.localizedDescription)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "litewall" { markReady() }
    }

    // MARK: - Internals

    private func markReady() {
        guard !ready else { return }
        ready = true
        webView.isHidden = false
        flushPending()
    }

    private func run(_ javaScript: String) {
        if ready {
            webView.evaluateJavaScript(javaScript, completionHandler: nil)
        } else {
            pendingJavaScript.append(javaScript)
        }
    }

    private func flushPending() {
        guard !pendingJavaScript.isEmpty else { return }
        let script = pendingJavaScript.joined(separator: ";\n")
        pendingJavaScript.removeAll()
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.ready = true
            self.webView.isHidden = true
            let label = NSTextField(labelWithString: "Wallpaper failed to load\n\n" + message)
            label.textColor = .white
            label.alignment = .center
            label.maximumNumberOfLines = 6
            label.font = .systemFont(ofSize: 14)
            label.frame = self.container.bounds.insetBy(dx: 60, dy: 60)
            label.autoresizingMask = [.width, .height]
            self.container.addSubview(label)
        }
    }

    private static func assetNames(in directory: URL) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { assetExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.lastPathComponent }
            .prefix(2000)
            .map { $0 }
    }
}

/// Guarantees the web view fills its host even when AppKit resizes the content
/// view after the renderer was created (e.g. on display reconfiguration).
private final class WebHostView: NSView {
    weak var webView: WKWebView?
    override func layout() {
        super.layout()
        webView?.frame = bounds
    }
}

/// WKUserContentController retains its message handler strongly. The proxy
/// breaks the retain cycle between the controller and the renderer.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
