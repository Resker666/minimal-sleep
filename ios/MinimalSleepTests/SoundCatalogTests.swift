import XCTest
@testable import MinimalSleep

final class SoundCatalogTests: XCTestCase {
    func testCatalogContainsTheFiveAndroidSoundsInProductOrder() {
        XCTAssertEqual(
            SoundCatalog.builtIn.map(\.id),
            [
                "recorded-rain-heavy",
                "recorded-rain-thunder",
                "procedural-heavy-rain",
                "procedural-ocean-waves",
                "white-noise",
            ]
        )
    }

    func testRecordedRainAttributionAndProceduralLabelsAreExplicit() {
        XCTAssertEqual(SoundCatalog.builtIn[0].attribution, "Resker666 / CC BY 4.0")
        XCTAssertEqual(SoundCatalog.builtIn[1].attribution, "Resker666 / CC BY 4.0")
        XCTAssertTrue(SoundCatalog.builtIn[2].isProceduralApproximation)
        XCTAssertTrue(SoundCatalog.builtIn[3].isProceduralApproximation)
        XCTAssertFalse(SoundCatalog.builtIn[4].isProceduralApproximation)
    }
}
