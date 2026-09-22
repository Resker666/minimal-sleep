import XCTest
@testable import MinimalSleep

final class SleepTimerPolicyTests: XCTestCase {
    func testAllNightHasNoDeadline() {
        var now: TimeInterval = 100
        var policy = SleepTimerPolicy(selectedDuration: .allNight, monotonicNow: { now })

        policy.start()
        now += 8 * 60 * 60

        XCTAssertTrue(policy.snapshot().isArmed)
        XCTAssertNil(policy.snapshot().remaining)
        XCTAssertEqual(policy.snapshot().fadeGain, 1, accuracy: 0.0001)
        XCTAssertFalse(policy.snapshot().isExpired)
    }

    func testFifteenMinutesExpiresFromMonotonicDeadline() {
        var now: TimeInterval = 42
        var policy = SleepTimerPolicy(selectedDuration: .fifteenMinutes, monotonicNow: { now })

        policy.start()
        XCTAssertEqual(policy.snapshot().remaining, 900)

        now += 900
        XCTAssertEqual(policy.snapshot().remaining, 0)
        XCTAssertTrue(policy.snapshot().isExpired)
    }

    func testEveryOfferedFiniteDurationHasAnExactDeadline() {
        var now: TimeInterval = 0
        var policy = SleepTimerPolicy(monotonicNow: { now })

        for duration in [
            SleepDuration.fifteenMinutes,
            .thirtyMinutes,
            .sixtyMinutes,
            .ninetyMinutes,
        ] {
            policy.select(duration, whileSessionIsActive: true)
            XCTAssertEqual(
                policy.snapshot().remaining,
                TimeInterval(duration.rawValue * 60)
            )
            now += 1
        }
    }

    func testLastTenSecondsFadeAtTenFiveAndZero() {
        var now: TimeInterval = 0
        var policy = SleepTimerPolicy(selectedDuration: .fifteenMinutes, monotonicNow: { now })
        policy.start()

        now = 890
        XCTAssertEqual(policy.snapshot().fadeGain, 1, accuracy: 0.0001)
        now = 895
        XCTAssertEqual(policy.snapshot().fadeGain, 0.5, accuracy: 0.0001)
        now = 900
        XCTAssertEqual(policy.snapshot().fadeGain, 0, accuracy: 0.0001)
    }

    func testLongGapWithoutUITicksStillUsesCurrentClock() {
        var now: TimeInterval = 1_000
        var policy = SleepTimerPolicy(selectedDuration: .thirtyMinutes, monotonicNow: { now })
        policy.start()

        now += 1_795

        XCTAssertEqual(policy.snapshot().remaining, 5)
        XCTAssertEqual(policy.snapshot().fadeGain, 0.5, accuracy: 0.0001)
    }

    func testPauseDoesNotExtendDeadline() {
        var now: TimeInterval = 0
        var policy = SleepTimerPolicy(selectedDuration: .fifteenMinutes, monotonicNow: { now })
        policy.start()

        now = 300
        policy.pause()
        now = 900

        XCTAssertTrue(policy.snapshot().isExpired)
    }

    func testChangingDurationRestartsFromOperationTimeAndStopClearsTimer() {
        var now: TimeInterval = 0
        var policy = SleepTimerPolicy(selectedDuration: .fifteenMinutes, monotonicNow: { now })
        policy.start()

        now = 30
        policy.select(.sixtyMinutes, whileSessionIsActive: true)
        XCTAssertEqual(policy.snapshot().remaining, 3_600)

        policy.stop()
        XCTAssertFalse(policy.snapshot().isArmed)
        XCTAssertNil(policy.snapshot().remaining)
    }
}
