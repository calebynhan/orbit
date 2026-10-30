import XCTest
@testable import OrbitCore

final class ScreenshotShortcutTests: XCTestCase {
    private let macOSDefault: [String: Any] = [
        "184": [
            "enabled": true,
            "value": ["parameters": [53, 23, 1_179_648], "type": "standard"],
        ] as [String: Any],
        "28": ["enabled": true] as [String: Any], // ⌘⇧3, must be left alone
    ]

    func testMissingEntryMeansMacOSDefaultIsOn() {
        XCTAssertTrue(ScreenshotShortcut.isEnabled(in: [:]))
        XCTAssertTrue(ScreenshotShortcut.isEnabled(in: nil))
    }

    func testReadsEnabledFlag() {
        XCTAssertTrue(ScreenshotShortcut.isEnabled(in: macOSDefault))
        let off = ScreenshotShortcut.setting(enabled: false, in: macOSDefault)
        XCTAssertFalse(ScreenshotShortcut.isEnabled(in: off))
    }

    func testAcceptsNumericEnabledFlag() {
        // `defaults` stores booleans as 0/1 integers in this domain.
        XCTAssertFalse(ScreenshotShortcut.isEnabled(in: ["184": ["enabled": 0]]))
        XCTAssertTrue(ScreenshotShortcut.isEnabled(in: ["184": ["enabled": 1]]))
    }

    func testDisablingKeepsKeyComboAndOtherShortcuts() throws {
        let off = ScreenshotShortcut.setting(enabled: false, in: macOSDefault)
        let entry = try XCTUnwrap(off["184"] as? [String: Any])
        let value = try XCTUnwrap(entry["value"] as? [String: Any])
        XCTAssertEqual(value["parameters"] as? [Int], [53, 23, 1_179_648])
        XCTAssertEqual((off["28"] as? [String: Any])?["enabled"] as? Bool, true)
    }

    func testDoesNotMutateInput() {
        _ = ScreenshotShortcut.setting(enabled: false, in: macOSDefault)
        XCTAssertTrue(ScreenshotShortcut.isEnabled(in: macOSDefault))
    }

    func testCreatesEntryWithMacOSDefaultComboWhenMissing() throws {
        let off = ScreenshotShortcut.setting(enabled: false, in: [:])
        let entry = try XCTUnwrap(off["184"] as? [String: Any])
        XCTAssertEqual(entry["enabled"] as? Bool, false)
        let value = try XCTUnwrap(entry["value"] as? [String: Any])
        XCTAssertEqual(value["parameters"] as? [Int], [53, 23, 1_179_648])
        XCTAssertEqual(value["type"] as? String, "standard")
    }

    func testRestoringTurnsItBackOn() {
        let off = ScreenshotShortcut.setting(enabled: false, in: macOSDefault)
        XCTAssertTrue(ScreenshotShortcut.isEnabled(in: ScreenshotShortcut.setting(enabled: true, in: off)))
    }
}
