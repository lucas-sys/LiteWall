// Runtime contract probe for WEShim.js.
//
// Usage: shim-probe <wallpaper-directory> <WEShim.js-path> [snapshot.png]
// Loads a Wallpaper Engine "web" wallpaper in a real WKWebView with the same
// injection order as the app, then reports whether the author script received
// the property snapshot and whether all 10 host APIs are present.
// An optional third argument writes a PNG snapshot of the rendered wallpaper.
//
// This is a probe, not a unit-test framework: it exits non-zero on load or
// evaluation failure and prints a single JSON line on success.

import AppKit
import WebKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("[shim-probe] " + message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count >= 3 else {
    fail("usage: shim-probe <wallpaper-directory> <WEShim.js-path>")
}
let wallpaperDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let shimURL = URL(fileURLWithPath: CommandLine.arguments[2])
let snapshotPath: String? = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : nil

final class Probe: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var hostWindow: NSWindow?

    func start() throws {
        let shim = try String(contentsOf: shimURL, encoding: .utf8)
        let projectData = try Data(contentsOf: wallpaperDir.appendingPathComponent("project.json"))
        guard let project = try JSONSerialization.jsonObject(with: projectData) as? [String: Any] else {
            fail("project.json is not an object")
        }
        let raw = ((project["general"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
        var shaped: [String: Any] = [:]
        for (key, value) in raw {
            shaped[key] = ["value": (value as? [String: Any])?["value"] ?? NSNull()]
        }

        let seed: [String: Any] = [
            "properties": shaped,
            "general": ["fps": 30],
            "paused": false,
            "muted": true,
            "volume": 0,
            "assets": [],
            "assetBase": wallpaperDir.absoluteString
        ]
        let seedJSON = String(data: try JSONSerialization.data(withJSONObject: seed), encoding: .utf8)!

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: "window.__weSeed = \(seedJSON);",
                                             injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: shim,
                                             injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 600), configuration: config)
        webView.navigationDelegate = self

        // CSS transitions/animations need a visible rendering host. Without a
        // window the compositor clock never advances and opacity stays at 0,
        // which would make the probe report a false "blank wallpaper".
        let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 900, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .floating
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()
        hostWindow = window

        let entryName = project["file"] as? String ?? "index.html"
        webView.loadFileURL(wallpaperDir.appendingPathComponent(entryName),
                            allowingReadAccessTo: wallpaperDir)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.check() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("provisional navigation failed: \(error.localizedDescription)")
    }

    private func check() {
        let javascript = """
        JSON.stringify({
          bridge: typeof window.__weBridge,
          propertyKeys: Object.keys((window.__weSeed || {}).properties || {}),
          listener: typeof window.wallpaperPropertyListener,
          listenerApply: typeof (window.wallpaperPropertyListener || {}).applyUserProperties,
          mediaPlaying: (window.wallpaperMediaIntegration || {}).PLAYBACK_PLAYING,
          audioReg: typeof window.wallpaperRegisterAudioListener,
          mediaPropertiesReg: typeof window.wallpaperRegisterMediaPropertiesListener,
          mediaThumbnailReg: typeof window.wallpaperRegisterMediaThumbnailListener,
          mediaPlaybackReg: typeof window.wallpaperRegisterMediaPlaybackListener,
          mediaTimelineReg: typeof window.wallpaperRegisterMediaTimelineListener,
          mediaStatusReg: typeof window.wallpaperRegisterMediaStatusListener,
          randomFile: typeof window.wallpaperRequestRandomFileForProperty,
          plugin: typeof (window.wallpaperPluginListener || {}).onPluginLoaded,
          state: window.__weBridge ? window.__weBridge.state() : null,
          canvasWidth: (document.getElementById('stage') || {}).width || 0,
          slideshowFrames: (window.__FM_IMAGES || []).length,
          slideshowFirstName: (window.__FM_IMAGES && window.__FM_IMAGES[0]) ? window.__FM_IMAGES[0].name : null,
          caption: (document.getElementById('name') || {}).textContent || null,
          intervalProbe: (function () {
            if (!window.__FM_IMAGES || !window.__weBridge) return null;
            var before = (window.__weBridge.state().properties.interval || {}).value;
            window.__weBridge.applyProperties({ interval: { value: 7 } });
            var after = (window.__weBridge.state().properties.interval || {}).value;
            return { before: before === undefined ? null : before,
                     after: after === undefined ? null : after };
          })(),
          render: (function () {
            var slide = document.getElementById('slide-a');
            if (!slide) return null;
            var el = slide.querySelector('img');
            var nm = document.getElementById('name');
            return {
              bodyClass: document.body.className,
              slideClass: slide.className,
              slideOpacity: getComputedStyle(slide).opacity,
              imgSrc: el ? el.getAttribute('src') : null,
              imgComplete: el ? el.complete : null,
              imgNatural: el ? (el.naturalWidth + 'x' + el.naturalHeight) : null,
              nameOpacity: nm ? getComputedStyle(nm).opacity : null,
              backdrop: getComputedStyle(document.getElementById('backdrop-a')).backgroundImage.slice(0, 110)
            };
          })()
        })
        """
        webView.evaluateJavaScript(javascript) { result, error in
            if let error { fail("evaluateJavaScript failed: \(error.localizedDescription)") }
            print(result ?? "null")

            guard let snapshotPath else { exit(0) }
            self.webView.takeSnapshot(with: nil) { image, snapshotError in
                guard let image,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    fail("snapshot failed: \(snapshotError?.localizedDescription ?? "no image")")
                }
                do {
                    try png.write(to: URL(fileURLWithPath: snapshotPath))
                    print("snapshot: \(snapshotPath)")
                    exit(0)
                } catch {
                    fail("snapshot write failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

let probe = Probe()
do { try probe.start() } catch { fail("setup failed: \(error.localizedDescription)") }
NSApplication.shared.run()
