import Foundation
import MediaPlayer

struct NowPlayingMetadata: Equatable {
    let title: String
    let attribution: String?
    let isPlaying: Bool
}

@MainActor
protocol NowPlayingControlling: AnyObject {
    func configureRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void
    )
    func publish(_ metadata: NowPlayingMetadata)
    func clear()
}

@MainActor
final class NowPlayingController: NowPlayingControlling {
    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var callbacksConfigured = false
    private var commandTargets: [Any] = []

    deinit {
        guard commandTargets.count == 2 else { return }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.removeTarget(commandTargets[0])
        commands.pauseCommand.removeTarget(commandTargets[1])
    }

    func configureRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void
    ) {
        guard !callbacksConfigured else { return }
        callbacksConfigured = true
        self.onPlay = onPlay
        self.onPause = onPause

        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true

        let playTarget = commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlay?() }
            return .success
        }
        let pauseTarget = commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPause?() }
            return .success
        }
        commandTargets = [playTarget, pauseTarget]
    }

    func publish(_ metadata: NowPlayingMetadata) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: metadata.isPlaying ? 1.0 : 0.0,
        ]
        if let attribution = metadata.attribution {
            info[MPMediaItemPropertyArtist] = attribution
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = metadata.isPlaying ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
