import XCTest
@testable import CharmsCore

final class GIFSearchTests: XCTestCase {
    private func request(_ provider: GIFProvider, rating: GIFRating = .pg) -> GIFSearchRequest {
        GIFSearchRequest(provider: provider, key: "test-key_1234", rating: rating, language: "de", region: "ch", clientID: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")
    }

    private func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testGIPHYSearchAndTrendingRequests() throws {
        let search = try request(.giphy).url(query: "  happy dance ", cursor: 48)
        XCTAssertEqual(search.scheme, "https")
        XCTAssertEqual(search.host, "api.giphy.com")
        XCTAssertEqual(search.path, "/v1/gifs/search")
        let items = query(search)
        XCTAssertEqual(items["q"], "happy dance")
        XCTAssertEqual(items["api_key"], "test-key_1234")
        XCTAssertEqual(items["offset"], "48")
        XCTAssertEqual(items["limit"], String(GIFSearchRequest.pageSize))
        XCTAssertEqual(items["rating"], "pg")
        XCTAssertEqual(items["lang"], "de")
        XCTAssertNil(items["customer_id"], "GIPHY gets no identifier")
        let trending = try request(.giphy, rating: .pg13).url(query: "", cursor: nil)
        XCTAssertEqual(trending.path, "/v1/gifs/trending")
        XCTAssertEqual(query(trending)["rating"], "pg-13")
        XCTAssertNil(query(trending)["q"])
    }

    func testKLIPYRequestsCarryTheKeyInThePath() throws {
        let search = try request(.klipy, rating: .g).url(query: "cat", cursor: 2)
        XCTAssertEqual(search.host, "api.klipy.com")
        XCTAssertEqual(search.path, "/api/v1/test-key_1234/gifs/search")
        let items = query(search)
        XCTAssertEqual(items["q"], "cat")
        XCTAssertEqual(items["page"], "2")
        XCTAssertEqual(items["content_filter"], "high")
        XCTAssertEqual(items["format_filter"], "gif")
        XCTAssertEqual(items["locale"], "CH")
        XCTAssertEqual(items["customer_id"], "6F9619FF-8B86-D011-B42D-00CF4FC964FF")
        XCTAssertEqual(try request(.klipy).url(query: "", cursor: nil).path, "/api/v1/test-key_1234/gifs/trending")
    }

    func testQueriesAreBoundedAndKeysChecked() throws {
        let long = try request(.giphy).url(query: String(repeating: "a", count: 500), cursor: nil)
        XCTAssertEqual(query(long)["q"]?.count, GIFSearchRequest.maximumQueryLength)
        for key in ["", "short", "has space key", "slash/../key", "ünïcode-key-1", String(repeating: "k", count: 200)] {
            let bad = GIFSearchRequest(provider: .klipy, key: key, rating: .pg, language: "en", region: nil, clientID: "x")
            XCTAssertThrowsError(try bad.url(query: "x", cursor: nil), key) { XCTAssertEqual($0 as? GIFSearchError, .missingKey) }
        }
        let odd = GIFSearchRequest(provider: .giphy, key: "test-key_1234", rating: .pg, language: "not a language", region: "X1", clientID: "x")
        XCTAssertEqual(odd.language, "en")
        XCTAssertNil(odd.region)
    }

    func testReadsGIPHYPages() throws {
        let body = #"""
        {"data":[
          {"type":"gif","id":"abc","title":"Happy Dancing GIF","alt_text":"","images":{
            "fixed_width_small":{"url":"https://media2.giphy.com/media/abc/100w.gif?cid=1&rid=100w.gif","width":"100","height":"80","size":"51234"},
            "fixed_width":{"url":"https://media2.giphy.com/media/abc/200w.gif?cid=1&rid=200w.gif","width":"200","height":"160","size":"312345"}}},
          {"type":"gif","id":"elsewhere","title":"Hosted elsewhere","images":{"fixed_width":{"url":"https://evil.example/x.gif","width":"200","height":"100"}}},
          {"type":"gif","id":"broken","title":"No sizes","images":{"fixed_width":{"url":"https://media.giphy.com/x.gif"}}}
        ],"pagination":{"offset":0,"count":3,"total_count":100},"meta":{"status":200,"msg":"OK"}}
        """#
        let page = try request(.giphy).page(from: Data(body.utf8), cursor: nil)
        XCTAssertEqual(page.items.count, 1)
        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.id, "abc")
        XCTAssertEqual(item.title, "Happy Dancing GIF")
        XCTAssertEqual(item.preview, GIFRendition(url: URL(string: "https://media2.giphy.com/media/abc/100w.gif?cid=1&rid=100w.gif")!, width: 100, height: 80, bytes: 51234))
        XCTAssertEqual(item.message.width, 200)
        XCTAssertEqual(item.message.url.query, "cid=1&rid=200w.gif", "service URLs keep their parameters")
        XCTAssertEqual(page.next, 3)
        let last = try request(.giphy).page(from: Data(#"{"data":[],"pagination":{"offset":96,"count":0,"total_count":96}}"#.utf8), cursor: 96)
        XCTAssertNil(last.next)
        let hostile = try request(.giphy).page(from: Data(#"{"data":[],"pagination":{"offset":24,"count":9223372036854775807,"total_count":9223372036854775807}}"#.utf8), cursor: 24)
        XCTAssertNil(hostile.next, "a malformed count neither overflows nor pages past GIPHY's last offset")
    }

    func testReadsKLIPYPagesWithoutAds() throws {
        let body = #"""
        {"result":true,"data":{"data":[
          {"id":8041071659142944,"slug":"hello-hi-662","title":"Hello\nthere","type":"gif","file":{
            "xs":{"gif":{"url":"https://static.klipy.com/ii/a/xs.gif","width":90,"height":90,"size":71468}},
            "sm":{"gif":{"url":"https://static.klipy.com/ii/a/sm.gif","width":220,"height":220,"size":171468}},
            "md":{"gif":{"url":"https://static2.klipy.com/ii/a/md.gif","width":320,"height":320,"size":871468}},
            "hd":{"gif":{"url":"https://static.klipy.com/ii/a/hd.gif","width":498,"height":498,"size":4001918}}}},
          {"id":1,"type":"ad","content":"<iframe src=\"https://ads.example\"></iframe>","width":300,"height":250}
        ],"current_page":1,"per_page":24,"has_next":true}}
        """#
        let page = try request(.klipy).page(from: Data(body.utf8), cursor: nil)
        XCTAssertEqual(page.items.map(\.id), ["8041071659142944"])
        XCTAssertEqual(page.items.first?.title, "Hello there")
        XCTAssertEqual(page.items.first?.preview.width, 220)
        XCTAssertEqual(page.items.first?.message.url.host, "static2.klipy.com")
        XCTAssertEqual(page.next, 2)
        XCTAssertThrowsError(try request(.klipy).page(from: Data("<html>".utf8), cursor: nil)) { XCTAssertEqual($0 as? GIFSearchError, .malformed) }
    }

    func testKLIPYStopsAtTheLastPageEvenWhenMoreAreAdvertised() throws {
        let search = request(.klipy)
        let body = Data(#"{"data":{"data":[],"has_next":true}}"#.utf8)
        let lastPage = GIFSearchRequest.maximumPage
        XCTAssertEqual(try search.page(from: body, cursor: lastPage - 1).next, lastPage)
        XCTAssertNil(try search.page(from: body, cursor: lastPage).next)
        XCTAssertEqual(try query(search.url(query: "hello", cursor: Int.max))["page"], String(lastPage))
    }

    func testErrorAnswersNameTheProblem() {
        XCTAssertEqual(request(.giphy).error(status: 401, body: Data()), .rejectedKey)
        XCTAssertEqual(request(.giphy).error(status: 429, body: Data()), .rateLimited)
        XCTAssertEqual(request(.giphy).error(status: 500, body: Data()), .unavailable)
        XCTAssertEqual(request(.klipy).error(status: 404, body: Data(#"{"result":false,"errors":{"message":["The provided API key is invalid."]}}"#.utf8)), .rejectedKey)
        XCTAssertEqual(request(.klipy).error(status: 404, body: Data("{}".utf8)), .unavailable)
    }

    func testClientSendsOnlyTheRequestAndRefusesRedirects() async throws {
        GIFStubProtocol.respond { request in
            if request.url?.path.hasSuffix("/trending") == true {
                return (302, ["Location": "https://evil.example/steal"], Data())
            }
            return (200, ["Content-Type": "application/json"], Data(#"{"data":[],"pagination":{"offset":0,"count":0,"total_count":0}}"#.utf8))
        }
        let client = GIFSearchClient(request: request(.giphy), protocolClasses: [GIFStubProtocol.self])
        let page = try await client.page(query: "cat", cursor: nil)
        XCTAssertTrue(page.items.isEmpty)
        let sent = try XCTUnwrap(GIFStubProtocol.recordedRequests().first)
        XCTAssertEqual(sent.url?.host, "api.giphy.com")
        XCTAssertNil(sent.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(sent.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(sent.value(forHTTPHeaderField: "User-Agent"), "Charms (macOS)")
        do { _ = try await client.page(query: "", cursor: nil); XCTFail("a redirect must not be followed") }
        catch { XCTAssertEqual(error as? GIFSearchError, .unavailable) }
        XCTAssertFalse(GIFStubProtocol.recordedRequests().contains { $0.url?.host == "evil.example" })
    }

    func testClientStopsReadingAnOversizedAnswer() async throws {
        // A valid page behind padding: only the cap can refuse it.
        let page = Data(#"{"data":[],"pagination":{"offset":0,"count":0,"total_count":0}}"#.utf8)
        let oversized = Data(repeating: 0x20, count: GIFSearchClient.maximumResponseBytes + 1 - page.count) + page
        for headers in [["Content-Type": "application/json"], ["Content-Type": "application/json", "Content-Length": String(oversized.count)]] {
            GIFStubProtocol.respond { _ in (200, headers, oversized) }
            let client = GIFSearchClient(request: request(.giphy), protocolClasses: [GIFStubProtocol.self])
            do { _ = try await client.page(query: "cat", cursor: nil); XCTFail("an answer over the cap is refused") }
            catch { XCTAssertEqual(error as? GIFSearchError, .malformed, "\(headers)") }
        }
    }
}

/// Answers every request from a handler and records it. Internal so the
/// media fetcher tests can use the same stub.
final class GIFStubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handler: @Sendable (URLRequest) -> (Int, [String: String], Data) = { _ in (500, [:], Data()) }
    private static var requests: [URLRequest] = []

    static func recordedRequests() -> [URLRequest] { lock.withLock { requests } }

    static func respond(_ handler: @escaping @Sendable (URLRequest) -> (Int, [String: String], Data)) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler; requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); let handler = Self.handler; Self.lock.unlock()
        let (status, headers, body) = handler(request)
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        if (300...399).contains(status), let location = headers["Location"], let target = URL(string: location) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
