import XCTest
@testable import CharmsCore

final class SnippetTests: XCTestCase {
    private let shrug = #"¯\_(ツ)_/¯"#

    func testSnippetPreservesExactReplacement() throws {
        let snippet = try TextSnippet(shortcut: "Shrug", name: "Shrug", text: shrug)
        XCTAssertEqual(snippet.shortcut, "shrug")
        XCTAssertTrue(snippet.text.isExactly(shrug))
        let decoded = try JSONDecoder().decode(TextSnippet.self, from: JSONEncoder().encode(snippet))
        XCTAssertEqual(decoded, snippet)
    }

    func testReplacementDoesNotNormalizeOrTrim() throws {
        let original = " \u{212B}\u{0301} "
        let snippet = try TextSnippet(shortcut: "exact", name: "Exact", text: original)
        XCTAssertTrue(snippet.text.isExactly(original))
        XCTAssertFalse(snippet.text.isExactly(" \u{00C5}\u{0301} "))
    }

    func testShortcutsAreValidated() {
        for shortcut in ["", "::shrug", "two words", "café", "-shrug", String(repeating: "a", count: 33)] {
            XCTAssertThrowsError(try TextSnippet(shortcut: shortcut, name: "Test", text: "ok"), shortcut)
        }
        XCTAssertNoThrow(try TextSnippet(shortcut: "my-text2", name: "Test", text: "ok"))
    }

    func testRejectsEmptyMultilineControlAndBidiText() {
        for text in ["", "   ", "\n", "one\ntwo", "a\tb", "a\r", "\u{0000}", "\u{2028}", "x\u{202E}y", "\u{200D}"] {
            XCTAssertThrowsError(try TextSnippet(shortcut: "test", name: "Test", text: text), text.debugDescription)
        }
    }

    func testUTF16LimitKeepsOneEventAndCompleteEmoji() throws {
        XCTAssertNoThrow(try TextSnippet(shortcut: "limit", name: "Limit", text: String(repeating: "a", count: 64)))
        XCTAssertThrowsError(try TextSnippet(shortcut: "limit", name: "Limit", text: String(repeating: "a", count: 65)))
        let family = "👩🏽‍💻"
        let snippet = try TextSnippet(shortcut: "coder", name: "Coder", text: family)
        XCTAssertTrue(snippet.text.isExactly(family))
        XCTAssertEqual(InsertionPolicy.eventPayloads(for: snippet.text), [Array(family.utf16)])
        XCTAssertThrowsError(try TextSnippet(shortcut: "limit", name: "Limit", text: String(repeating: "😀", count: 33)))
    }

    func testNamesAreRequiredBoundedAndSingleLine() {
        for name in ["", "   ", "one\ntwo", "x\u{2066}y", String(repeating: "n", count: 81)] {
            XCTAssertThrowsError(try TextSnippet(shortcut: "test", name: name, text: "ok"))
        }
    }

    func testDecodingUsesTheSameValidationAsEditing() {
        let invalid = #"{"id":"00000000-0000-0000-0000-000000000001","shortcut":"bad shortcut","name":"Test","text":"ok"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(TextSnippet.self, from: Data(invalid.utf8)))
    }

    func testLibraryEditsRejectDuplicateShortcutsWithoutChangingData() throws {
        let first = try TextSnippet(shortcut: "shrug", name: "Shrug", text: shrug)
        var library = try SnippetLibrary(snippets: [first])
        XCTAssertThrowsError(try library.upsert(TextSnippet(shortcut: "SHRUG", name: "Duplicate", text: "other")))
        XCTAssertEqual(library.snippets, [first])
        let edited = try TextSnippet(id: first.id, shortcut: "whatever", name: "Whatever", text: "new")
        try library.upsert(edited)
        XCTAssertEqual(library.snippets, [edited])
        library.remove(id: first.id)
        XCTAssertTrue(library.snippets.isEmpty)
    }

    func testLibraryRejectsDuplicateIDsAndFutureSchemas() throws {
        let first = try TextSnippet(shortcut: "one", name: "One", text: "one")
        let sameID = try TextSnippet(id: first.id, shortcut: "two", name: "Two", text: "two")
        XCTAssertThrowsError(try SnippetLibrary(snippets: [first, sameID]))
        XCTAssertThrowsError(try JSONDecoder().decode(SnippetLibrary.self, from: Data(#"{"schemaVersion":2,"snippets":[]}"#.utf8)))
    }

    func testLibraryRoundTripIncludesAnIntentionallyEmptyList() throws {
        let library = SnippetLibrary()
        let decoded = try JSONDecoder().decode(SnippetLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded, library)
        XCTAssertTrue(decoded.snippets.isEmpty)
    }

    func testStarterSetIsBoundedUniqueExactAndFitsOneEvent() {
        let starters = DefaultSnippets.library.snippets
        XCTAssertEqual(starters.count, 20)
        XCTAssertEqual(Set(starters.map(\.id)).count, starters.count)
        XCTAssertEqual(Set(starters.map(\.shortcut)).count, starters.count)
        XCTAssertTrue(starters.first { $0.shortcut == "shrug" }!.text.isExactly(shrug))
        for snippet in starters {
            XCTAssertLessThanOrEqual(snippet.text.utf16.count, TextSnippet.maximumTextUnits)
            XCTAssertEqual(InsertionPolicy.eventPayloads(for: snippet.text), [Array(snippet.text.utf16)])
            XCTAssertNoThrow(try TextSnippet(id: snippet.id, shortcut: snippet.shortcut, name: snippet.name, text: snippet.text))
        }
    }

    func testAddingMissingStartersPreservesEditsAndClaimedShortcuts() throws {
        let original = DefaultSnippets.library.snippets[0]
        let renamed = try TextSnippet(id: original.id, shortcut: "whatever", name: "Mine", text: "custom")
        let claimed = try TextSnippet(shortcut: "tableflip", name: "My table", text: "mine")
        var library = try SnippetLibrary(snippets: [renamed, claimed])
        try library.addMissingStarters()
        XCTAssertEqual(library.snippets.count, 20)
        XCTAssertEqual(library.snippets.first { $0.id == original.id }, renamed)
        XCTAssertEqual(library.snippets.first { $0.shortcut == "tableflip" }, claimed)
        let before = library
        try library.addMissingStarters()
        XCTAssertEqual(library, before)
    }

    func testTooManyEntriesRejectWithoutPartialMutation() throws {
        let snippets = try (0..<SnippetLibrary.maximumCount).map { index in
            try TextSnippet(shortcut: "item\(index)", name: "Item", text: "text")
        }
        var library = try SnippetLibrary(snippets: snippets)
        XCTAssertThrowsError(try library.upsert(TextSnippet(shortcut: "extra", name: "Extra", text: "text")))
        XCTAssertEqual(library.snippets, snippets)
        XCTAssertThrowsError(try library.addMissingStarters())
        XCTAssertEqual(library.snippets, snippets)
    }

    func testUnicodeLookalikeIsNotAnExactShortcut() throws {
        let snippet = try TextSnippet(shortcut: "k", name: "Test", text: "other")
        XCTAssertTrue(snippet.matchesShortcut("K"))
        XCTAssertFalse(snippet.matchesShortcut("\u{212A}"))
    }

    func testEqualityUsesExactTextForTheSameIdentifier() throws {
        let first = try TextSnippet(shortcut: "exact", name: "Exact", text: "\u{212B}")
        let second = try TextSnippet(id: first.id, shortcut: "exact", name: "Exact", text: "\u{00C5}")
        XCTAssertNotEqual(first, second)
    }

    func testSearchFindsShortcutNameAndExactPayloadWithoutFoldingPayload() throws {
        let first = try TextSnippet(shortcut: "tableflip", name: "Flip the table", text: "(╯°□°)╯︵ ┻━┻")
        let second = try TextSnippet(shortcut: "shrug", name: "Shrug", text: shrug)
        let angstrom = try TextSnippet(shortcut: "ring", name: "Exact", text: "\u{212B}")
        let library = try SnippetLibrary(snippets: [first, second, angstrom])
        XCTAssertEqual(library.matches(query: "SHRUG").map(\.id), [second.id])
        XCTAssertEqual(library.matches(query: "table flip").map(\.id), [first.id])
        XCTAssertEqual(library.matches(query: "shr").map(\.id), [second.id])
        XCTAssertEqual(library.matches(query: shrug).first?.id, second.id)
        XCTAssertTrue(library.matches(query: "\u{00C5}").isEmpty)
        XCTAssertTrue(library.matches(query: "  ").isEmpty)
        XCTAssertTrue(library.matches(query: "no-such-snippet").isEmpty)
    }
}
