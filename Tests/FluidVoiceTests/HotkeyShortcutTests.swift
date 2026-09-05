import AppKit
@testable import FluidVoice
import XCTest

@MainActor
final class HotkeyShortcutTests: XCTestCase {
    func testReplacingRightOptionWithLeftOptionRemovesOldBinding() {
        let rightOption = HotkeyShortcut(keyCode: 61, modifierFlags: [], modifierKeyCodes: [61])
        let leftOption = HotkeyShortcut(keyCode: 58, modifierFlags: [], modifierKeyCodes: [58])
        var shortcuts = HotkeyShortcutSet([rightOption])

        XCTAssertEqual(shortcuts.modifierOnlyShortcut(matching: [61]), rightOption)
        XCTAssertNil(shortcuts.modifierOnlyShortcut(matching: [58]))

        shortcuts.replace(with: [leftOption])

        XCTAssertNil(shortcuts.modifierOnlyShortcut(matching: [61]))
        XCTAssertEqual(shortcuts.modifierOnlyShortcut(matching: [58]), leftOption)
        XCTAssertEqual(shortcuts.shortcuts, [leftOption])
    }

    func testReplacingKeyboardChordRemovesOldChord() {
        let oldShortcut = HotkeyShortcut(keyCode: 15, modifierFlags: [.command])
        let newShortcut = HotkeyShortcut(keyCode: 49, modifierFlags: [.control, .option])
        var shortcuts = HotkeyShortcutSet([oldShortcut])

        XCTAssertNotNil(shortcuts.keyboardShortcut(keyCode: 15, modifiers: [.command]))

        shortcuts.replace(with: [newShortcut])

        XCTAssertNil(shortcuts.keyboardShortcut(keyCode: 15, modifiers: [.command]))
        XCTAssertEqual(
            shortcuts.keyboardShortcut(keyCode: 49, modifiers: [.control, .option]),
            newShortcut
        )
    }

    func testShortcutSetDeduplicatesEquivalentBindings() {
        let leftOption = HotkeyShortcut(keyCode: 58, modifierFlags: [], modifierKeyCodes: [58])
        let duplicate = HotkeyShortcut(keyCode: 58, modifierFlags: [], modifierKeyCodes: [58, 58])

        let shortcuts = HotkeyShortcutSet([leftOption, duplicate, leftOption])

        XCTAssertEqual(shortcuts.shortcuts, [leftOption])
    }

    func testSideSpecificModifierSurvivesPersistenceRoundTrip() throws {
        let original = HotkeyShortcut(keyCode: 61, modifierFlags: [], modifierKeyCodes: [61])

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyShortcut.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.normalizedModifierKeyCodes, [61])
        XCTAssertNotEqual(
            decoded,
            HotkeyShortcut(keyCode: 58, modifierFlags: [], modifierKeyCodes: [58])
        )
    }

    func testModifierPrefixConflictsAreRejected() {
        let leftOption = HotkeyShortcut(keyCode: 58, modifierFlags: [], modifierKeyCodes: [58])
        let leftAndRightOption = HotkeyShortcut(
            keyCode: 58,
            modifierFlags: [],
            modifierKeyCodes: [58, 61]
        )

        XCTAssertTrue(leftOption.conflictsWith(leftAndRightOption))
        XCTAssertTrue(leftAndRightOption.conflictsWith(leftOption))
    }

    func testMouseShortcutMatchingRequiresExactModifiers() {
        let shortcut = HotkeyShortcut(mouseButton: 3, modifierFlags: [.control])
        let shortcuts = HotkeyShortcutSet([shortcut])

        XCTAssertTrue(shortcuts.containsMouseShortcut(button: 3, modifiers: [.control]))
        XCTAssertFalse(shortcuts.containsMouseShortcut(button: 3, modifiers: []))
        XCTAssertFalse(shortcuts.containsMouseShortcut(button: 4, modifiers: [.control]))
    }
}
