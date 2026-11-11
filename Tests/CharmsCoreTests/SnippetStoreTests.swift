import Darwin
import XCTest
@testable import CharmsCore

final class SnippetStoreTests: XCTestCase {
    private let fileManager = FileManager.default
    private var directory: URL!
    private var store: SnippetStore!

    override func setUp() {
        super.setUp()
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("SnippetStoreTests-\(UUID().uuidString)")
        store = SnippetStore(directory: directory)
    }

    override func tearDown() {
        // A test may have made the directory read-only; restore it so cleanup works.
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? fileManager.removeItem(at: directory)
        store = nil
        directory = nil
        super.tearDown()
    }

    private var fileURL: URL { directory.appendingPathComponent("snippets.json") }

    private func write(_ data: Data, to url: URL? = nil) throws {
        let destination = url ?? fileURL
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try data.write(to: destination)
    }

    private func snippet(shortcut: String, name: String = "Snippet", text: String = "text") throws -> TextSnippet {
        try TextSnippet(shortcut: shortcut, name: name, text: text)
    }

    private func posixPermissions(of url: URL) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func directoryNames() throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: directory.path)
    }

    // MARK: - Loading

    func testMissingFileReturnsNil() throws {
        XCTAssertFalse(fileManager.fileExists(atPath: directory.path))
        XCTAssertNil(try store.load())

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertNil(try store.load())
    }

    func testSaveThenLoadRoundTripsExactShrugBackslashAndUnicodeVariants() throws {
        let shrug = #"¯\_(ツ)_/¯"#
        let precomposed = "Caf\u{00E9}"
        let decomposed = "Cafe\u{0301}"
        let snippets = try [
            snippet(shortcut: "shrug", name: "Shrug", text: shrug),
            snippet(shortcut: "pre", name: "Precomposed", text: precomposed),
            snippet(shortcut: "de", name: "Decomposed", text: decomposed),
        ]
        let library = try SnippetLibrary(snippets: snippets)
        try store.save(library)

        let raw = try Data(contentsOf: fileURL)
        let rawText = String(decoding: raw, as: UTF8.self)
        // JSON escapes the backslash and slash, but the payload must come back exact.
        XCTAssertTrue(rawText.contains("¯\\\\_(ツ)_\\/¯"), "backslash and slash must stay escaped in JSON")
        XCTAssertTrue(rawText.contains(precomposed))
        XCTAssertTrue(rawText.contains(decomposed))

        let loaded = try XCTUnwrap(try store.load())
        XCTAssertEqual(loaded.snippets.count, 3)
        XCTAssertTrue(loaded.snippets[0].text.isExactly(shrug))
        XCTAssertTrue(loaded.snippets[1].text.isExactly(precomposed))
        XCTAssertTrue(loaded.snippets[2].text.isExactly(decomposed))
        XCTAssertFalse(loaded.snippets[1].text.isExactly(decomposed))
        XCTAssertFalse(loaded.snippets[2].text.isExactly(precomposed))

        // Saving the loaded library again is byte-stable.
        try store.save(loaded)
        XCTAssertEqual(try Data(contentsOf: fileURL), raw)
    }

    func testIntentionallyEmptyLibraryPersists() throws {
        try store.save(SnippetLibrary())
        XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path))
        let loaded = try XCTUnwrap(try store.load())
        XCTAssertTrue(loaded.snippets.isEmpty)
        XCTAssertEqual(try posixPermissions(of: fileURL), 0o600)
    }

    func testOverwriteExistingLibrary() throws {
        let first = try snippet(shortcut: "first", name: "First", text: "first text")
        try store.save(try SnippetLibrary(snippets: [first]))
        let second = try snippet(shortcut: "second", name: "Second", text: "second text")
        try store.save(try SnippetLibrary(snippets: [second]))

        let loaded = try XCTUnwrap(try store.load())
        XCTAssertEqual(loaded.snippets, [second])
        let raw = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        XCTAssertFalse(raw.contains("first text"))
        XCTAssertEqual(try posixPermissions(of: fileURL), 0o600)
        XCTAssertEqual(try directoryNames(), ["snippets.json"])
    }

    func testSaveCreatesDirectoryWith0700AndFileWith0600() throws {
        XCTAssertFalse(fileManager.fileExists(atPath: directory.path))
        try store.save(SnippetLibrary())
        XCTAssertEqual(try posixPermissions(of: directory), 0o700)
        XCTAssertEqual(try posixPermissions(of: fileURL), 0o600)
    }

    // MARK: - Strict loading

    func testMalformedJSONThrowsAndLeavesFileUntouched() throws {
        for bytes in [Data("{\"schemaVersion\": 1, \"snippets\": [".utf8), Data()] {
            try write(bytes)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
        }
    }

    func testFutureSchemaThrowsAndLeavesFileUntouched() throws {
        let bytes = Data(#"{"schemaVersion":2,"snippets":[]}"#.utf8)
        try write(bytes)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
    }

    func testInvalidAndDuplicateContentThrowsAndLeavesFileUntouched() throws {
        let longText = String(repeating: "a", count: 65)
        let cases: [Data] = [
            Data(#"{"schemaVersion":1,"snippets":[{"id":"00000000-0000-0000-0000-000000000001","shortcut":"1bad","name":"Bad","text":"ok"}]}"#.utf8),
            Data(#"{"schemaVersion":1,"snippets":[{"id":"00000000-0000-0000-0000-000000000001","shortcut":"bad","name":"Bad","text":"a\u0007b"}]}"#.utf8),
            Data(#"{"schemaVersion":1,"snippets":[{"id":"00000000-0000-0000-0000-000000000001","shortcut":"dup","name":"One","text":"a"},{"id":"00000000-0000-0000-0000-000000000002","shortcut":"DUP","name":"Two","text":"b"}]}"#.utf8),
            Data(#"{"schemaVersion":1,"snippets":[{"id":"00000000-0000-0000-0000-000000000001","shortcut":"one","name":"One","text":"a"},{"id":"00000000-0000-0000-0000-000000000001","shortcut":"two","name":"Two","text":"b"}]}"#.utf8),
            Data(#"{"schemaVersion":1,"snippets":[{"id":"00000000-0000-0000-0000-000000000001","shortcut":"long","name":"Bad","text":"\#(longText)"}]}"#.utf8),
        ]
        for bytes in cases {
            try write(bytes)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
        }

        let entries = (0..<(SnippetLibrary.maximumCount + 1)).map { index in
            #"{"id":"\#(UUID().uuidString)","shortcut":"item\#(index)","name":"Item","text":"ok"}"#
        }
        let tooMany = Data(#"{"schemaVersion":1,"snippets":["#.utf8
            + Data(entries.joined(separator: ",").utf8)
            + Data("]}".utf8))
        try write(tooMany)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: fileURL), tooMany)
    }

    func testFailureDiagnosticsDoNotIncludeFileContent() throws {
        let sentinel = "TOP_SECRET_SENTINEL_98765"
        let invalid = Data(#"{"schemaVersion":1,"snippets":[{"id":"00000000-0000-0000-0000-000000000001","shortcut":"bad shortcut","name":"\#(sentinel)","text":"\#(sentinel)"}]}"#.utf8)
        try write(invalid)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertFalse(String(describing: error).contains(sentinel))
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), invalid)

        let malformed = Data("SENTINEL \(sentinel) not json".utf8)
        try write(malformed)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertFalse(String(describing: error).contains(sentinel))
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), malformed)
    }

    func testOversizedInputIsRejectedBeforeParsingAndLeavesFileUntouched() throws {
        let limit = 1 << 20
        let valid = #"{"schemaVersion":1,"snippets":[]}"#
        let oversized = Data((valid + String(repeating: " ", count: limit - valid.utf8.count + 1)).utf8)
        XCTAssertEqual(oversized.count, limit + 1)
        try write(oversized)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: fileURL), oversized)

        // Exactly at the limit is still read and parsed; trailing whitespace is valid JSON.
        let exact = Data((valid + String(repeating: " ", count: limit - valid.utf8.count)).utf8)
        XCTAssertEqual(exact.count, limit)
        try write(exact)
        let loaded = try XCTUnwrap(try store.load())
        XCTAssertTrue(loaded.snippets.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), exact)
    }

    func testNonRegularFileThrowsAndLeavesItUntouched() throws {
        try fileManager.createDirectory(at: fileURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.load())
        var isDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testUnreadableParentDirectoryThrowsAndLeavesFileUntouched() throws {
        if geteuid() == 0 { throw XCTSkip("permission checks do not apply to root") }
        let bytes = Data(#"{"schemaVersion":1,"snippets":[]}"#.utf8)
        try write(bytes)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try store.load())
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
    }

    func testSymlinkAtFilePathThrowsAsNonRegular() throws {
        let payload = Data(#"{"schemaVersion":1,"snippets":[]}"#.utf8)
        let target = directory.appendingPathComponent("real.json")
        try write(payload, to: target)
        try fileManager.createSymbolicLink(at: fileURL, withDestinationURL: target)

        XCTAssertThrowsError(try store.load())

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(try Data(contentsOf: target), payload)
    }

    func testUnreadableFileThrowsAndLeavesFileUntouched() throws {
        if geteuid() == 0 { throw XCTSkip("permission checks do not apply to root") }
        let bytes = Data(#"{"schemaVersion":1,"snippets":[]}"#.utf8)
        try write(bytes)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        XCTAssertThrowsError(try store.load())
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
    }

    // MARK: - Saving failures

    func testDirectoryCreationFailureThrowsAndLeavesBlockerUntouched() throws {
        let blocker = directory!
        let original = Data("i am a file, not a directory".utf8)
        try original.write(to: blocker)
        XCTAssertThrowsError(try store.save(SnippetLibrary()))
        XCTAssertEqual(try Data(contentsOf: blocker), original)
    }

    func testFileWriteFailureLeavesPriorDataIntactAndCleansTemp() throws {
        if geteuid() == 0 { throw XCTSkip("permission checks do not apply to root") }
        let first = try snippet(shortcut: "first", name: "First", text: "first")
        try store.save(try SnippetLibrary(snippets: [first]))
        let prior = try Data(contentsOf: fileURL)

        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let second = try snippet(shortcut: "second", name: "Second", text: "second")
        XCTAssertThrowsError(try store.save(try SnippetLibrary(snippets: [second])))
        XCTAssertEqual(try Data(contentsOf: fileURL), prior)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        XCTAssertEqual(try directoryNames(), ["snippets.json"])
    }

    func testDestinationDirectoryWriteFailureThrowsAndCleansTemp() throws {
        try store.save(SnippetLibrary())
        try fileManager.removeItem(at: fileURL)
        try fileManager.createDirectory(at: fileURL, withIntermediateDirectories: false)

        let library = try SnippetLibrary(snippets: [try snippet(shortcut: "second", name: "Second", text: "second")])
        XCTAssertThrowsError(try store.save(library))
        let names = try directoryNames()
        XCTAssertTrue(names.allSatisfy { $0 == "snippets.json" }, "unexpected leftovers: \(names)")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testNoTemporaryFilesRemainAfterSaves() throws {
        try store.save(SnippetLibrary())
        try store.save(try SnippetLibrary(snippets: [try snippet(shortcut: "one", name: "One", text: "one")]))
        try store.save(try SnippetLibrary(snippets: [try snippet(shortcut: "two", name: "Two", text: "two")]))
        XCTAssertEqual(try directoryNames(), ["snippets.json"])
    }

    func testSavedJSONIsPrettyPrintedSortedAndStable() throws {
        let library = try SnippetLibrary(snippets: [
            try snippet(shortcut: "zeta", name: "Zeta", text: "z"),
            try snippet(shortcut: "alpha", name: "Alpha", text: "a"),
        ])
        try store.save(library)
        let first = try Data(contentsOf: fileURL)
        let text = String(decoding: first, as: UTF8.self)
        XCTAssertTrue(text.contains("\n"))
        guard let schema = text.range(of: "\"schemaVersion\""),
              let snippets = text.range(of: "\"snippets\""),
              let id = text.range(of: "\"id\""),
              let name = text.range(of: "\"name\""),
              let shortcut = text.range(of: "\"shortcut\""),
              let body = text.range(of: "\"text\"") else {
            return XCTFail("saved JSON is missing expected keys")
        }
        XCTAssertLessThan(schema.lowerBound, snippets.lowerBound)
        XCTAssertLessThan(id.lowerBound, name.lowerBound)
        XCTAssertLessThan(name.lowerBound, shortcut.lowerBound)
        XCTAssertLessThan(shortcut.lowerBound, body.lowerBound)
        try store.save(library)
        XCTAssertEqual(try Data(contentsOf: fileURL), first)
    }
}
