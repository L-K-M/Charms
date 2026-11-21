import AppKit
import Combine
import XCTest
@testable import Charms

@MainActor
final class MemeDraftTests: XCTestCase {
    private func imageURL() throws -> URL {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80,
                                                    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    func testEditedCaptionWinsOverLateSuggestion() async throws {
        let url = try imageURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let draft = MemeDraft()
        let started = expectation(description: "Caption model started")
        var resume: CheckedContinuation<String, Never>?
        draft.accept(url, prompt: "a robot librarian") { _, _ in
            await withCheckedContinuation { continuation in
                resume = continuation
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 2)
        draft.editCaption("Shelf control.")
        resume?.resume(returning: "An older suggestion")
        await Task.yield()
        XCTAssertEqual(draft.caption, "Shelf control.")
        XCTAssertTrue(draft.canCopy)
    }

    func testArtworkCanBeCaptionedWhenModelIsUnavailable() async throws {
        let draft = MemeDraft()
        let url = try imageURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let unavailable = expectation(description: "Manual caption offered")
        let observation = draft.$notice.compactMap { $0 }.first().sink { _ in unavailable.fulfill() }
        draft.accept(url, prompt: "books") { _, _ in throw CocoaError(.featureUnsupported) }
        await fulfillment(of: [unavailable], timeout: 2)
        observation.cancel()
        XCTAssertFalse(draft.canCopy)
        XCTAssertNotNil(draft.preview)
        XCTAssertNotNil(draft.notice)
        draft.editCaption("Reading between the lines.")
        XCTAssertTrue(draft.canCopy)
        XCTAssertNil(draft.notice)
    }
}
