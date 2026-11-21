import XCTest
@testable import CharmsCore

final class GIFMediaFetcherTests: XCTestCase {
    private func makeFetcher() -> GIFMediaFetcher {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GIFStubProtocol.self]
        return GIFMediaFetcher(session: URLSession(configuration: configuration))
    }

    func testFetchesAPreviewFromAServiceHost() async throws {
        let gif = Data("GIF89a".utf8) + Data(repeating: 0, count: 16)
        GIFStubProtocol.respond { _ in (200, ["Content-Type": "image/gif"], gif) }
        let data = await makeFetcher().data(for: URL(string: "https://media.giphy.com/media/a/100w.gif")!, provider: .giphy)
        XCTAssertEqual(data, gif)
    }

    func testRefusesAnythingThatIsNotServiceMedia() async {
        GIFStubProtocol.respond { _ in (200, ["Content-Type": "image/gif"], Data("GIF89a".utf8)) }
        let data = await makeFetcher().data(for: URL(string: "https://tracker.example/p.gif")!, provider: .giphy)
        XCTAssertNil(data)
        XCTAssertTrue(GIFStubProtocol.recordedRequests().isEmpty, "no request may leave for a non-service address")
    }

    func testSearchDoesNotFetchFromAnotherProvider() async {
        GIFStubProtocol.respond { _ in (200, [:], Data("GIF89a".utf8)) }
        let url = URL(string: "https://static.klipy.com/a/b.gif")!
        let data = await makeFetcher().data(for: url, provider: .giphy)
        XCTAssertNil(data)
        XCTAssertTrue(GIFStubProtocol.recordedRequests().isEmpty)
    }

    func testStopsAtThePreviewCap() async {
        let oversized = Data(repeating: 0x47, count: GIFMediaFetcher.maximumBytes + 1)
        GIFStubProtocol.respond { _ in (200, ["Content-Type": "image/gif", "Content-Length": String(oversized.count)], oversized) }
        let data = await makeFetcher().data(for: URL(string: "https://static.klipy.com/a/b.gif")!, provider: .klipy)
        XCTAssertNil(data, "an answer over the preview cap is refused")
    }
}
