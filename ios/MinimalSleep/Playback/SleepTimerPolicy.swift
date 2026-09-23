import Foundation

enum SleepDuration: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case sixtyMinutes = 60
    case ninetyMinutes = 90
    case allNight = 0

    var id: Int { rawValue }

    var minutes: Int? {
        self == .allNight ? nil : rawValue
    }

    var title: String {
        minutes.map { "\($0) 分钟" } ?? "整晚"
    }
}

struct SleepTimerSnapshot: Equatable, Sendable {
    let isArmed: Bool
    let remaining: TimeInterval?
    let fadeGain: Double
    let isExpired: Bool
}

struct SleepTimerPolicy {
    static let fadeDuration: TimeInterval = 10

    private let monotonicNow: () -> TimeInterval
    private(set) var selectedDuration: SleepDuration
    private(set) var isArmed = false
    private var deadline: TimeInterval?

    init(
        selectedDuration: SleepDuration = .thirtyMinutes,
        monotonicNow: @escaping () -> TimeInterval = SleepTimerPolicy.makeContinuousClock()
    ) {
        self.selectedDuration = selectedDuration
        self.monotonicNow = monotonicNow
    }

    mutating func start() {
        isArmed = true
        deadline = selectedDuration.minutes.map {
            monotonicNow() + TimeInterval($0 * 60)
        }
    }

    mutating func pause() {
        // Intentionally does not change the deadline. Pausing audio does not pause sleep time.
    }

    mutating func stop() {
        isArmed = false
        deadline = nil
    }

    mutating func select(_ duration: SleepDuration, whileSessionIsActive: Bool) {
        selectedDuration = duration
        guard whileSessionIsActive else {
            deadline = nil
            isArmed = false
            return
        }
        start()
    }

    func snapshot() -> SleepTimerSnapshot {
        let remaining = deadline.map { max(0, $0 - monotonicNow()) }
        let expired = isArmed && deadline != nil && remaining == 0
        let fadeGain = remaining.map {
            min(1, max(0, $0 / Self.fadeDuration))
        } ?? 1
        return SleepTimerSnapshot(
            isArmed: isArmed,
            remaining: remaining,
            fadeGain: fadeGain,
            isExpired: expired
        )
    }

    private static func makeContinuousClock() -> () -> TimeInterval {
        let clock = ContinuousClock()
        let origin = clock.now
        return {
            let components = origin.duration(to: clock.now).components
            return TimeInterval(components.seconds)
                + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        }
    }
}
