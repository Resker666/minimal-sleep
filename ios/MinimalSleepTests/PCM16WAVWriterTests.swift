import Foundation
import XCTest
@testable import MinimalSleep

final class PCM16WAVWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MinimalSleepWAVTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testWritesCanonicalMonoPCM16HeaderAndSamples() throws {
        let temporary = directory.appendingPathComponent("event.wav.part")
        let final = directory.appendingPathComponent("event.wav")
        try PCM16WAVWriter().write(
            samples: [-32_768, -1, 0, 1, 32_767],
            sampleRate: 16_000,
            temporaryURL: temporary,
            finalURL: final
        )
        let data = try Data(contentsOf: final)
        XCTAssertEqual(data.count, 54)
        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(data.littleEndianUInt32(at: 4), 46)
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: data[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(data.littleEndianUInt16(at: 20), 1)
        XCTAssertEqual(data.littleEndianUInt16(at: 22), 1)
        XCTAssertEqual(data.littleEndianUInt32(at: 24), 16_000)
        XCTAssertEqual(data.littleEndianUInt32(at: 28), 32_000)
        XCTAssertEqual(data.littleEndianUInt16(at: 34), 16)
        XCTAssertEqual(data.littleEndianUInt32(at: 40), 10)
        XCTAssertEqual(Array(data[44..<54]), [0, 128, 255, 255, 0, 0, 1, 0, 255, 127])
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testExistingFinalIsNeverOverwritten() throws {
        let temporary = directory.appendingPathComponent("event.wav.part")
        let final = directory.appendingPathComponent("event.wav")
        try Data("existing".utf8).write(to: final)

        XCTAssertThrowsError(try PCM16WAVWriter().write(
            samples: [1], sampleRate: 16_000, temporaryURL: temporary, finalURL: final
        ))
        XCTAssertEqual(try Data(contentsOf: final), Data("existing".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testEmptySamplesAreRejectedWithoutCreatingFiles() {
        let temporary = directory.appendingPathComponent("event.wav.part")
        let final = directory.appendingPathComponent("event.wav")
        XCTAssertThrowsError(try PCM16WAVWriter().write(
            samples: [], sampleRate: 16_000, temporaryURL: temporary, finalURL: final
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: final.path))
    }

    func testExistingTemporaryDirectoryIsNotRemovedOnFailure() throws {
        let temporary = directory.appendingPathComponent("event.wav.part", isDirectory: true)
        let final = directory.appendingPathComponent("event.wav")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)

        XCTAssertThrowsError(try PCM16WAVWriter().write(
            samples: [1], sampleRate: 16_000, temporaryURL: temporary, finalURL: final
        ))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: final.path))
    }
}

private extension Data {
    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }
}
