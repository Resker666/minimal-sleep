import XCTest
@testable import MinimalSleep

final class EnergyDetectorTests: XCTestCase {
    func testQuietFramesDoNotTriggerButLoudFramesDo() {
        var detector = EnergyDetector()
        for _ in 0..<20 {
            XCTAssertFalse(detector.isCandidate(Array(repeating: 100, count: 1_024)))
        }
        XCTAssertTrue(detector.isCandidate(Array(repeating: 8_000, count: 1_024)))
    }

    func testSustainedLoudInputEventuallyAdaptsInsteadOfStayingTriggeredForever() {
        var detector = EnergyDetector()
        let results = (0..<220).map { _ in
            detector.isCandidate(Array(repeating: 8_000, count: 1_024))
        }
        XCTAssertTrue(results.prefix(160).contains(true))
        XCTAssertTrue(results.suffix(40).allSatisfy { !$0 })
    }
}
