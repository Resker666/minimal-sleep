import Foundation
import XCTest
@testable import MinimalSleep

final class ImportedAudioValidatorTests: XCTestCase {
    func testBundledWAVIsAcceptedAndInvalidBytesAreRejected() throws {
        let validator = AVFoundationImportedAudioValidator()
        let validURL = try XCTUnwrap(
            Bundle.main.url(forResource: "white_noise", withExtension: "wav")
        )
        let valid = StagedImportedFile(
            token: "valid.wav",
            fileURL: validURL,
            byteCount: Int64((try Data(contentsOf: validURL)).count)
        )
        XCTAssertNoThrow(try validator.validateAudio(stagedFile: valid))

        let invalidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data("not audio".utf8).write(to: invalidURL)
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        let invalid = StagedImportedFile(
            token: "invalid.wav",
            fileURL: invalidURL,
            byteCount: 9
        )

        XCTAssertThrowsError(try validator.validateAudio(stagedFile: invalid)) { error in
            XCTAssertEqual(error as? ImportedAudioValidationError, .undecodable)
        }
    }
}
