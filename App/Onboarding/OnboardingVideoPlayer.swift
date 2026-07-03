import AVKit
import SwiftUI

/// Looping, muted, control-free video used as an onboarding illustration.
/// Shows `placeholder` when the named .mp4 isn't in the bundle, so steps
/// whose recording doesn't exist yet keep their schematic mock.
struct OnboardingVideo<Placeholder: View>: View {
    let resourceName: String
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") {
            LoopingPlayerView(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                )
                .allowsHitTesting(false)
        } else {
            placeholder()
        }
    }
}

/// AVPlayerLayer host: aspect-fill, muted, seamless loop via AVPlayerLooper.
private struct LoopingPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerLayerHostView {
        PlayerLayerHostView(url: url)
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {}
}

@MainActor
final class PlayerLayerHostView: NSView {
    private let player: AVQueuePlayer
    private let looper: AVPlayerLooper

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        self.player = player
        self.looper = AVPlayerLooper(player: player, templateItem: item)
        super.init(frame: .zero)

        wantsLayer = true
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
        player.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}
