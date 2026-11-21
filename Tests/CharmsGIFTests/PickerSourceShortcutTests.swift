import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Charms

final class PickerSourceShortcutTests: XCTestCase {
    func testCommandNumberUsesTheLayoutWhenEventTextIsMissingOrDifferent() throws {
        let cases: [(String, String, String, PickerSource?)] = [
            ("1", "", "", .characters),
            ("2", "2", "@", .local),
            ("2", "c", "c", nil),
            ("4", "4", "4", .memes),
            ("1", "3", "3", .online)
        ]
        for (digit, text, unmodified, source) in cases {
            let code = try XCTUnwrap(KeyLayout.keyCode(producing: digit, carbonModifiers: UInt32(cmdKey)))
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: unmodified,
                isARepeat: false, keyCode: code
            ))
            XCTAssertEqual(PickerSource.commandShortcut(for: event), source)
        }
    }
}
