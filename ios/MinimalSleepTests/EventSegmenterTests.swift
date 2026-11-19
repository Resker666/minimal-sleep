import XCTest
@testable import MinimalSleep

final class EventSegmenterTests: XCTestCase {
    func testIncludesThreeSecondsBeforeAndAfterCandidate() {
        var segmenter = EventSegmenter(sampleRate: 10, preSeconds: 3, postSeconds: 3, maxSeconds: 60)
        XCTAssertTrue(segmenter.push(samples: Array(0..<30).map(Int16.init), isCandidate: false).isEmpty)
        XCTAssertTrue(segmenter.push(samples: Array(repeating: 1_000, count: 10), isCandidate: true).isEmpty)
        let result = segmenter.push(samples: Array(repeating: 0, count: 30), isCandidate: false)
        XCTAssertEqual(result.single?.startSample, 0)
        XCTAssertEqual(result.single?.samples.count, 70)
    }

    func testSixtySecondSplitPreservesAllSamplesAndGroupID() {
        var segmenter = EventSegmenter(sampleRate: 10, preSeconds: 3, postSeconds: 3, maxSeconds: 60)
        let output = segmenter.push(samples: Array(repeating: 2_000, count: 1_250), isCandidate: true)
            + segmenter.finish()
        XCTAssertEqual(output.reduce(0) { $0 + $1.samples.count }, 1_250)
        XCTAssertGreaterThan(output.count, 1)
        XCTAssertEqual(Set(output.map(\.groupID)).count, 1)
        XCTAssertEqual(output.map(\.startSample), [0, 600, 1_200])
    }

    func testQuietInputDoesNotSaveAnEvent() {
        var segmenter = EventSegmenter(sampleRate: 10, preSeconds: 3, postSeconds: 3, maxSeconds: 60)
        XCTAssertTrue(segmenter.push(samples: Array(repeating: 0, count: 100), isCandidate: false).isEmpty)
        XCTAssertTrue(segmenter.finish().isEmpty)
    }

    func testStopFlushesAnActiveEvent() {
        var segmenter = EventSegmenter(sampleRate: 10, preSeconds: 3, postSeconds: 3, maxSeconds: 60)
        XCTAssertTrue(segmenter.push(samples: Array(repeating: 1_000, count: 10), isCandidate: true).isEmpty)
        let result = segmenter.finish()
        XCTAssertEqual(result.single?.samples.count, 10)
        XCTAssertEqual(result.single?.startSample, 0)
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
