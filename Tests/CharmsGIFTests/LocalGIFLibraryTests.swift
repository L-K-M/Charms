import Foundation
import XCTest
@testable import Charms

@MainActor
final class LocalGIFLibraryTests: XCTestCase {
    private func waitFor(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while !condition(), clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition())
    }

    func testUnavailableInferenceKeepsFilenameAndUserTags() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("collection", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("GIF89a".utf8).write(to: folder.appendingPathComponent("hello.gif"))
        let library = LocalGIFLibrary(supportDirectory: root) { _ in
            throw GIFAnalyzer.Failure.analysisFailed("inference-unavailable")
        }
        library.setFolder(folder)
        try await waitFor { library.status?.contains("filename") == true }
        let entry = try XCTUnwrap(library.entries.first)
        XCTAssertEqual(entry.url.lastPathComponent, "hello.gif")
        XCTAssertNil(entry.method)
        library.setTags(["greeting"], for: entry.url)
        XCTAssertEqual(library.entries.first?.tags, ["greeting"])
    }

    func testWatchedChangesKeepEditedTagsAndOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("collection", isDirectory: true)
        let support = root.appendingPathComponent("settings")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = LocalGIFLibrary(supportDirectory: support) { _ in .init(tags: ["generated"], method: .multimodal) }
        library.setFolder(folder)
        let url = folder.appendingPathComponent("reaction.GIF")
        let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAP8AAAAA/yH5BAAKAAAALAAAAAABAAEAAAICRAEAIfkEAAoAAAAsAAAAAAEAAQAAAgJMAQA7")!
        try gif.write(to: url)
        try await waitFor { library.entries.first?.tags == ["generated"] }
        let original = try XCTUnwrap(library.entries.first)
        let copied = try await original.revision.data(at: url)
        XCTAssertEqual(copied, gif)
        library.setTags(["Slow clap"], for: original.url)
        try (gif + Data([0])).write(to: url, options: .atomic)
        try await waitFor { library.entries.first?.revision != original.revision && library.entries.first?.generatedTags == ["generated"] }
        XCTAssertEqual(library.entries.first?.tags, ["Slow clap"])
        XCTAssertThrowsError(try original.revision.read(url))
        let reopened = LocalGIFLibrary(supportDirectory: support) { _ in XCTFail("Unchanged file was analyzed again"); return .init(tags: [], method: .multimodal) }
        try await waitFor { reopened.entries.first?.tags == ["Slow clap"] }
        try FileManager.default.removeItem(at: url)
        try await waitFor { library.entries.isEmpty && reopened.entries.isEmpty }
    }
}
