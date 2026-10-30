import XCTest
@testable import OrbitCore

final class KeyboardShortcutTests: XCTestCase {
    func testDefaultIsCommandShift5() {
        let s = KeyboardShortcut.default
        XCTAssertEqual(s.keyCode, 23)
        XCTAssertEqual(s.modifiers, [.command, .shift])
        XCTAssertTrue(s.isMacOSScreenshotShortcut)
        XCTAssertEqual(s.displayString, "⇧⌘5") // macOS orders modifiers ⌃⌥⇧⌘
    }

    func testDisplayStringOrdersModifiersLikeMacOS() {
        let s = KeyboardShortcut(keyCode: 15, modifiers: [.shift, .command, .option, .control]) // R
        XCTAssertEqual(s.displayString, "⌃⌥⇧⌘R")
    }

    func testNamedKeysDisplayAsSymbols() {
        XCTAssertEqual(KeyboardShortcut(keyCode: 49, modifiers: [.command]).displayString, "⌘Space")
        XCTAssertEqual(KeyboardShortcut(keyCode: 36, modifiers: [.control]).displayString, "⌃↩")
        XCTAssertEqual(KeyboardShortcut(keyCode: 96, modifiers: []).displayString, "F5")
    }

    func testValidationRequiresAModifierExceptForFunctionKeys() {
        XCTAssertEqual(KeyboardShortcut(keyCode: 23, modifiers: []).validationProblem, .needsModifier)
        XCTAssertEqual(KeyboardShortcut(keyCode: 23, modifiers: [.shift]).validationProblem, .needsModifier) // shift alone types "%"
        XCTAssertNil(KeyboardShortcut(keyCode: 23, modifiers: [.command]).validationProblem)
        XCTAssertNil(KeyboardShortcut(keyCode: 96, modifiers: []).validationProblem) // F5 alone is fine
    }

    func testValidationRejectsUnknownKeys() {
        XCTAssertEqual(KeyboardShortcut(keyCode: 999, modifiers: [.command]).validationProblem, .unknownKey)
    }

    func testCarbonModifierFlags() {
        let s = KeyboardShortcut(keyCode: 23, modifiers: [.command, .shift])
        XCTAssertEqual(s.carbonModifiers, 256 | 512) // cmdKey | shiftKey
    }

    func testRoundTripsThroughCodable() throws {
        let s = KeyboardShortcut(keyCode: 15, modifiers: [.command, .option])
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcut.self, from: data), s)
    }
}
