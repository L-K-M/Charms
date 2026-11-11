import XCTest
@testable import CharmsCore

final class SnippetPickerTests: XCTestCase {
    private let shrug = #"¯\_(ツ)_/¯"#
    private var content: PickerContent {
        let header = CatalogFormat.Header(unicodeVersion: "18.0.0", emojiVersion: "18.0", cldrVersion: "49")
        let entries = [
            CatalogEntry(string: "🤷", kind: .emoji, rank: 0, age: UnicodeAge(major: 9, minor: 0), group: "People", name: "person shrugging", keywords: [], aliases: [CatalogAlias(text: "shrug", rank: 0)]),
            CatalogEntry(string: "→", kind: .symbol, rank: 0, age: UnicodeAge(major: 1, minor: 1), group: "Arrows", name: "rightwards arrow", keywords: [], aliases: [CatalogAlias(text: "arrow", rank: 0)])
        ]
        let catalog = Catalog(contents: CatalogFormat.Contents(header: header, entries: entries, ranges: []))
        return PickerContent(catalog: catalog, index: SearchIndex(catalog: catalog))
    }

    private func results(_ query: String, snippets: SnippetLibrary, library: UserLibrary = UserLibrary()) -> [PickerItem] {
        content.sections(query: query, library: library, skinTone: .medium, columns: 8,
                         snippets: snippets, isSupported: { _ in true }).first?.items ?? []
    }

    func testExactShortcutOutranksEmojiButKeepsItDiscoverable() throws {
        let snippets = try SnippetLibrary(snippets: [TextSnippet(shortcut: "shrug", name: "Shrug", text: shrug)])
        let items = results("shrug", snippets: snippets)
        XCTAssertEqual(items.map(\.string), [shrug, "🤷"])
        XCTAssertEqual(items.first?.snippetShortcut, "shrug")
        XCTAssertFalse(items[0].isEmoji)
        XCTAssertNil(items[0].variantBaseIndex)
        XCTAssertTrue(items[0].preview.isExactly(shrug))
    }

    func testExplicitCodePointQueryStillFindsTheCharacter() throws {
        let snippets = try SnippetLibrary(snippets: [TextSnippet(shortcut: "arrow", name: "Arrow", text: "other")])
        XCTAssertEqual(results("arrow", snippets: snippets).first?.string, "other")
        XCTAssertEqual(results("U+2192", snippets: snippets).first?.string, "→")
        XCTAssertEqual(results("→", snippets: snippets).first?.string, "→")
    }

    func testMetadataSearchNeverReplacesThePayload() {
        let items = results("put table", snippets: DefaultSnippets.library)
        XCTAssertEqual(items.first?.snippetShortcut, "unflip")
        XCTAssertTrue(items[0].string.isExactly("┬─┬ノ( º _ ºノ)"))
    }

    func testDuplicatePayloadsAreShownOnce() throws {
        let snippets = try SnippetLibrary(snippets: [
            TextSnippet(shortcut: "arrow", name: "Arrow", text: "→"),
            TextSnippet(shortcut: "arrow-two", name: "Arrow", text: "→")
        ])
        XCTAssertEqual(results("arrow", snippets: snippets).map(\.string), ["→"])
    }

    func testCanonicallyEquivalentSnippetPayloadsRemainDistinct() throws {
        let snippets = try SnippetLibrary(snippets: [
            TextSnippet(shortcut: "unit-one", name: "Exact", text: "\u{212B}"),
            TextSnippet(shortcut: "unit-two", name: "Exact", text: "\u{00C5}")
        ])
        XCTAssertEqual(Set(results("unit", snippets: snippets).map { ExactString($0.string) }),
                       Set([ExactString("\u{212B}"), ExactString("\u{00C5}")]))
    }

    func testSavedSnippetStaysTextAfterEditingOrDeletion() throws {
        let old = try TextSnippet(shortcut: "shrug", name: "Original", text: shrug)
        var library = UserLibrary()
        library.seedIfNeeded([LibraryItem(string: old.text, name: old.name, snippetShortcut: old.shortcut)])
        let edited = try TextSnippet(id: old.id, shortcut: "shrug", name: "Changed", text: "different")
        for snippets in [SnippetLibrary(), try SnippetLibrary(snippets: [edited])] {
            let item = content.sections(query: "", library: library, skinTone: .none, columns: 8,
                                        snippets: snippets, isSupported: { _ in true })[0].items[0]
            XCTAssertTrue(item.string.isExactly(shrug))
            XCTAssertEqual(item.name, "Original")
            XCTAssertEqual(item.snippetShortcut, "shrug")
        }
    }

    func testSavedMetadataRoundTripAndLegacyItems() throws {
        let item = LibraryItem(string: shrug, name: "Shrug", snippetShortcut: "shrug")
        XCTAssertEqual(try JSONDecoder().decode(LibraryItem.self, from: JSONEncoder().encode(item)), item)
        let legacy = try JSONDecoder().decode(LibraryItem.self, from: Data(#"{"string":"→","name":"Arrow"}"#.utf8))
        XCTAssertNil(legacy.snippetShortcut)
    }

    func testEmptyQueryDoesNotFloodFavouritesWithStarters() {
        let shown = content.sections(query: "", library: UserLibrary(), skinTone: .none, columns: 8,
                                     snippets: DefaultSnippets.library, isSupported: { _ in true })
        XCTAssertEqual(shown.map(\.kind), [.favourites, .recents])
        XCTAssertTrue(shown.allSatisfy { $0.items.isEmpty })
    }
}
