import XCTest
@testable import MinimalSleep

final class AppVersionTests: XCTestCase {
    func testBundleDeclaresVersionBuildMicrophoneAndBackgroundAudio() {
        let bundle = Bundle.main
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, "0.5.0")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, "2")
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String,
            "极简睡眠只在你主动开始夜间记录后使用麦克风，并仅在本机保存声音触发片段。"
        )
        XCTAssertTrue((bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("audio") == true)
    }
}
