import CharmsCore
import Combine
import XCTest
@testable import Charms

@MainActor
final class MemeArtworkTests: XCTestCase {
    private func settle(_ draft: MemeDraft) async {
        let idle = expectation(description: "artwork settled")
        let observation = draft.$activity.filter { $0 == .idle }.first().sink { _ in idle.fulfill() }
        await fulfillment(of: [idle], timeout: 5)
        observation.cancel()
    }

    private func load(_ draft: MemeDraft, _ image: CGImage, suggest: @escaping MemeDraft.Suggest = { _, _ in "Suggested." }) async {
        draft.loadArtwork(.importing, prompt: "", suggest: suggest) { image }
        await settle(draft)
    }

    func testNewArtworkKeepsACaptionTheUserWrote() async throws {
        let draft = MemeDraft()
        await load(draft, try MemeTestImages.image())
        draft.editCaption("My own words.")

        var askedAgain = false
        await load(draft, try MemeTestImages.image(width: 600, height: 300)) { _, _ in
            askedAgain = true
            return "Replacement"
        }
        await Task.yield()
        XCTAssertEqual(draft.caption, "My own words.")
        XCTAssertFalse(askedAgain)
        XCTAssertEqual(draft.preview?.width, 600)
        XCTAssertGreaterThan(draft.preview?.height ?? 0, 300, "the caption is drawn on the new artwork")
        XCTAssertTrue(draft.canCopy)
    }

    func testNewArtworkReplacesASuggestedCaption() async throws {
        let draft = MemeDraft()
        for wanted in ["First suggestion.", "Second suggestion."] {
            let suggested = expectation(description: wanted)
            let observation = draft.$caption.filter { $0 == wanted }.first().sink { _ in suggested.fulfill() }
            await load(draft, try MemeTestImages.image()) { _, _ in wanted }
            await fulfillment(of: [suggested], timeout: 5)
            observation.cancel()
        }
    }

    func testAFailureKeepsTheArtworkAndCaption() async throws {
        let draft = MemeDraft()
        await load(draft, try MemeTestImages.image())
        draft.editCaption("Still here.")
        let before = draft.preview

        draft.loadArtwork(.generating, prompt: "cat") { throw VeniceImageError.paymentRequired }
        await settle(draft)
        XCTAssertTrue(draft.preview === before)
        XCTAssertEqual(draft.caption, "Still here.")
        XCTAssertEqual(draft.notice, VeniceImageError.paymentRequired.errorDescription)
        XCTAssertTrue(draft.canCopy)
    }

    func testASecondOperationCannotStartWhileOneRuns() async throws {
        let draft = MemeDraft()
        let image = try MemeTestImages.image()
        var resume: CheckedContinuation<CGImage, Never>?
        let started = expectation(description: "first started")
        draft.loadArtwork(.generating, prompt: "cat", suggest: { _, _ in "Cat." }) {
            await withCheckedContinuation { continuation in
                resume = continuation
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 5)

        var secondRan = false
        draft.loadArtwork(.importing, prompt: "") {
            secondRan = true
            return image
        }
        XCTAssertEqual(draft.activity, .generating)
        XCTAssertFalse(draft.canCopy, "closing after a copy would abandon a paid request")
        resume?.resume(returning: image)
        await settle(draft)
        XCTAssertFalse(secondRan)
        XCTAssertTrue(draft.hasArtwork)
    }

    func testStoppedGenerationIgnoresALateImage() async throws {
        let draft = MemeDraft()
        let image = try MemeTestImages.image()
        var resume: CheckedContinuation<CGImage, Never>?
        let started = expectation(description: "generation started")
        draft.loadArtwork(.generating, prompt: "cat") {
            await withCheckedContinuation { continuation in
                resume = continuation
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 5)
        draft.stopLoading()
        resume?.resume(returning: image)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(draft.hasArtwork)
        XCTAssertEqual(draft.activity, .idle)
        XCTAssertNotNil(draft.notice, "a stopped request may still be billed")
    }

    func testAnUnchangedCaptionReportDoesNotStopASuggestion() async throws {
        let draft = MemeDraft()
        var resume: CheckedContinuation<String, Never>?
        let started = expectation(description: "suggestion started")
        draft.loadArtwork(.importing, prompt: "", suggest: { _, _ in
            await withCheckedContinuation { continuation in
                resume = continuation
                started.fulfill()
            }
        }, load: { try MemeTestImages.image() })
        await fulfillment(of: [started], timeout: 5)
        draft.editCaption("")
        XCTAssertTrue(draft.isSuggesting)
        resume?.resume(returning: "Suggested.")
    }
}
