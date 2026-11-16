import AppKit

/// Aspect-fill static image renderer. No animation, effectively zero CPU once drawn.
final class ImageRenderer: WallpaperRendering {
    let view: NSView

    init(url: URL) {
        let image = NSImage(contentsOf: url)
        view = AspectFillImageView(image: image)
    }

    func setPaused(_ paused: Bool) {}
    func setVolume(_ volume: Float) {}
    func setFPS(_ fps: Int) {}
}

private final class AspectFillImageView: NSView {
    private let image: NSImage?

    init(image: NSImage?) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
        guard let image else { return }
        let target = bounds.size
        let source = image.size
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else { return }
        let scale = max(target.width / source.width, target.height / source.height)
        let w = source.width * scale
        let h = source.height * scale
        let rect = NSRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
