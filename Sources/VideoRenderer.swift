import AppKit
import AVFoundation

/// Looping video renderer. Audio is muted by default; `setVolume` is the single
/// control surface shared with web wallpapers.
final class VideoRenderer: WallpaperRendering {
    let view: NSView

    private let player = AVPlayer()
    private let playerLayer: AVPlayerLayer
    private var loopObserver: NSObjectProtocol?
    private var paused = false
    private var volume: Float = 0

    init(url: URL, volume: Float) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor

        let host = PlayerHostView(frame: .zero)
        host.wantsLayer = true
        host.layer = playerLayer
        view = host

        self.volume = min(max(volume, 0), 1)
        applyVolume()

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self, !self.paused else { return }
            self.player.seek(to: .zero) { [weak self] _ in self?.player.play() }
        }
        player.play()
    }

    deinit {
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        player.pause()
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        if paused { player.pause() } else { player.play() }
    }

    func setVolume(_ volume: Float) {
        self.volume = min(max(volume, 0), 1)
        applyVolume()
    }

    func setFPS(_ fps: Int) {}

    private func applyVolume() {
        player.isMuted = volume <= 0.001
        player.volume = volume
    }
}

private final class PlayerHostView: NSView {
    override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}
