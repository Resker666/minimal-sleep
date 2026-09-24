import AVFoundation
import Foundation

enum AudioSafetyEvent: Equatable, Sendable {
    case interruptionBegan
    case oldDeviceUnavailable
}

@MainActor
protocol AudioSessionControlling: AnyObject {
    var onSafetyEvent: ((AudioSafetyEvent) -> Void)? { get set }
    func setPlaybackActive(_ active: Bool) throws
    func setRecordingActive(_ active: Bool) throws
}

@MainActor
protocol SystemAudioSessionApplying: AnyObject {
    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

@MainActor
final class AVSystemAudioSession: SystemAudioSessionApplying {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        try session.setCategory(category, mode: mode, options: options)
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try session.setActive(active, options: options)
    }
}

@MainActor
final class AudioSessionController: NSObject, AudioSessionControlling {
    var onSafetyEvent: ((AudioSafetyEvent) -> Void)?

    private let system: SystemAudioSessionApplying
    private var playbackActive = false
    private var recordingActive = false
    private var configuredCategory: AVAudioSession.Category?
    private var sessionIsActive = false

    init(system: SystemAudioSessionApplying? = nil, observeNotifications: Bool = true) {
        self.system = system ?? AVSystemAudioSession()
        super.init()
        if observeNotifications {
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(handleInterruptionNotification(_:)),
                name: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance()
            )
            center.addObserver(
                self,
                selector: #selector(handleRouteChangeNotification(_:)),
                name: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance()
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setPlaybackActive(_ active: Bool) throws {
        guard playbackActive != active else { return }
        let previous = playbackActive
        playbackActive = active
        do {
            try reconcile()
        } catch {
            playbackActive = previous
            try? reconcile()
            throw error
        }
    }

    func setRecordingActive(_ active: Bool) throws {
        guard recordingActive != active else { return }
        let previous = recordingActive
        recordingActive = active
        do {
            try reconcile()
        } catch {
            recordingActive = previous
            try? reconcile()
            throw error
        }
    }

    private func reconcile() throws {
        guard playbackActive || recordingActive else {
            if sessionIsActive {
                try system.setActive(false, options: .notifyOthersOnDeactivation)
                sessionIsActive = false
            }
            return
        }

        let category: AVAudioSession.Category = recordingActive ? .playAndRecord : .playback
        let options: AVAudioSession.CategoryOptions = recordingActive ? [.defaultToSpeaker] : []
        if configuredCategory != category {
            try system.setCategory(category, mode: .default, options: options)
            configuredCategory = category
        }
        if !sessionIsActive {
            try system.setActive(true, options: [])
            sessionIsActive = true
        }
    }

    @objc
    nonisolated private func handleInterruptionNotification(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
        Task { @MainActor [weak self] in
            self?.onSafetyEvent?(.interruptionBegan)
        }
    }

    @objc
    nonisolated private func handleRouteChangeNotification(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else { return }
        Task { @MainActor [weak self] in
            self?.onSafetyEvent?(.oldDeviceUnavailable)
        }
    }
}

@MainActor
enum AudioSafetyBridge {
    static func connect(
        session: AudioSessionControlling,
        playback: AudioCoordinator,
        recording: NightRecordingCoordinator
    ) {
        session.onSafetyEvent = { [weak playback, weak recording] event in
            playback?.handleInterruptionOrUnsafeRouteChange()
            Task { @MainActor in
                await recording?.handleSafetyEvent(event)
            }
        }
    }
}
