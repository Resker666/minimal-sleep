import AVFoundation
import XCTest
@testable import MinimalSleep

final class MicrophoneCaptureEngineTests: XCTestCase {
    func testConverterEmits1024SampleFramesAndFlushesTail() async throws {
        let sourceFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
            channels: 1, interleaved: false
        ))
        let targetFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000,
            channels: 1, interleaved: true
        ))
        let converter = try XCTUnwrap(AVAudioConverter(from: sourceFormat, to: targetFormat))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4_800))
        input.frameLength = 4_800
        let source = try XCTUnwrap(input.floatChannelData?.pointee)
        for index in 0..<4_800 { source[index] = 0.25 }

        var continuation: AsyncThrowingStream<[Int16], Error>.Continuation!
        let stream = AsyncThrowingStream<[Int16], Error> { continuation = $0 }
        let state = ConversionState(
            converter: converter, outputFormat: targetFormat, continuation: continuation
        )
        state.consume(input)
        state.finish()

        var frames: [[Int16]] = []
        for try await frame in stream { frames.append(frame) }
        XCTAssertEqual(frames.first?.count, 1_024)
        XCTAssertEqual(frames.reduce(0) { $0 + $1.count }, 1_600)
        XCTAssertTrue(frames.flatMap { $0 }.contains { $0 > 7_000 })
    }
}
