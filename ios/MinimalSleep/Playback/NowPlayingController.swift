import Foundation

@MainActor
final class NowPlayingController {
    struct Metadata: Equatable {
        let title: String
        let attribution: String?
        let isPlaying: Bool
    }

    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var callbacksConfigured = false

    func configureRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void
    ) {
        guard !callbacksConfigured else { return }
        callbacksConfigured = true
        self.onPlay = onPlay
        self.onPause = onPause

        // TODO（需 Mac 编译）: Import MediaPlayer and register MPRemoteCommandCenter
        // handlers exactly once. The play handler must call onPlay, which refuses an
        // expired or stopped session; the pause handler must call onPause.
    }

    func publish(_ metadata: Metadata) {
        // TODO（需 Mac 编译）: Update MPNowPlayingInfoCenter. Do not publish a
        // misleading finite duration for a looping sleep sound.
    }

    func clear() {
        // TODO（需 Mac 编译）: Clear MPNowPlayingInfoCenter.default().nowPlayingInfo.
    }
}
