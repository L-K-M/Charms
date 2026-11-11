import Darwin
import XCTest
@testable import CharmsCore

final class SnippetStoreAccessTests: XCTestCase {
    func testInaccessibleDirectoryIsNotMistakenForFirstRun() throws {
        if geteuid() == 0 { throw XCTSkip("root bypasses directory permissions") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = SnippetStore(directory: directory)
        let original = try SnippetLibrary(snippets: [TextSnippet(shortcut: "mine", name: "Mine", text: "custom")])
        try store.save(original)
        let file = directory.appendingPathComponent("snippets.json")
        let bytes = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.path)
        // fileExists returns false for an inaccessible parent. Treating that
        // as first run would seed defaults and risk overwriting saved edits.
        XCTAssertThrowsError(try store.load())
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try store.load(), original)
    }
}
