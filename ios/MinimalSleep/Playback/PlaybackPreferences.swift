import Foundation

@MainActor
protocol PlaybackPreferencesStoring: AnyObject {
    var selectedDuration: SleepDuration? { get set }
    var baseVolume: Float? { get set }
}

@MainActor
final class UserDefaultsPlaybackPreferences: PlaybackPreferencesStoring {
    private enum Key {
        static let selectedDuration = "playback.selectedDurationMinutes"
        static let baseVolume = "playback.baseVolume"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedDuration: SleepDuration? {
        get {
            guard defaults.object(forKey: Key.selectedDuration) != nil else { return nil }
            return SleepDuration(rawValue: defaults.integer(forKey: Key.selectedDuration))
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: Key.selectedDuration)
            } else {
                defaults.removeObject(forKey: Key.selectedDuration)
            }
        }
    }

    var baseVolume: Float? {
        get {
            guard defaults.object(forKey: Key.baseVolume) != nil else { return nil }
            return defaults.float(forKey: Key.baseVolume)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.baseVolume)
            } else {
                defaults.removeObject(forKey: Key.baseVolume)
            }
        }
    }
}
