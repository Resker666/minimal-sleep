import AVFoundation
import XCTest
@testable import MinimalSleep

@MainActor
final class AudioSessionControllerTests: XCTestCase {
    func testPausingPlaybackDoesNotDeactivateAnActiveRecordingSession() throws {
        let system = FakeSystemAudioSession()
        let controller = AudioSessionController(system: system, observeNotifications: false)
        try controller.setRecordingActive(true)
        try controller.setPlaybackActive(true)
        try controller.setPlaybackActive(false)

        XCTAssertEqual(system.lastCategory, .playAndRecord)
        XCTAssertTrue(system.isActive)
        XCTAssertTrue(system.lastOptions.contains(.defaultToSpeaker))
        XCTAssertEqual(system.deactivationCount, 0)
    }

    func testPlaybackOnlyUsesPlaybackCategoryAndStoppingDeactivates() throws {
        let system = FakeSystemAudioSession()
        let controller = AudioSessionController(system: system, observeNotifications: false)
        try controller.setPlaybackActive(true)
        XCTAssertEqual(system.lastCategory, .playback)
        XCTAssertTrue(system.isActive)

        try controller.setPlaybackActive(false)
        XCTAssertFalse(system.isActive)
        XCTAssertEqual(system.deactivationCount, 1)
    }

    func testRecordingOnlyUsesSpeakerAndEndingRecordingReturnsToPlayback() throws {
        let system = FakeSystemAudioSession()
        let controller = AudioSessionController(system: system, observeNotifications: false)
        try controller.setPlaybackActive(true)
        try controller.setRecordingActive(true)
        XCTAssertEqual(system.lastCategory, .playAndRecord)
        XCTAssertTrue(system.lastOptions.contains(.defaultToSpeaker))

        try controller.setRecordingActive(false)
        XCTAssertEqual(system.lastCategory, .playback)
        XCTAssertTrue(system.isActive)
        XCTAssertEqual(system.deactivationCount, 0)
    }

    func testRepeatedStateDoesNotReconfigureSystemSession() throws {
        let system = FakeSystemAudioSession()
        let controller = AudioSessionController(system: system, observeNotifications: false)
        try controller.setRecordingActive(true)
        let categoryCount = system.categoryCount
        let activationCount = system.activationCount

        try controller.setRecordingActive(true)

        XCTAssertEqual(system.categoryCount, categoryCount)
        XCTAssertEqual(system.activationCount, activationCount)
    }
}

@MainActor
private final class FakeSystemAudioSession: SystemAudioSessionApplying {
    private(set) var lastCategory: AVAudioSession.Category?
    private(set) var lastOptions: AVAudioSession.CategoryOptions = []
    private(set) var isActive = false
    private(set) var categoryCount = 0
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        lastCategory = category
        lastOptions = options
        categoryCount += 1
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        isActive = active
        if active { activationCount += 1 } else { deactivationCount += 1 }
    }
}
