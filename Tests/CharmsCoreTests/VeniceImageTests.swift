import XCTest
@testable import CharmsCore

/// The expected fields, limits and statuses come from Venice's published
/// `POST /image/generate` contract and `GET /models?type=image`, read on
/// 22 November 2026.
final class VeniceImageTests: XCTestCase {
    private let key = "venice-test-key-0123456789"
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private func body(_ request: VeniceImageRequest) throws -> NSDictionary {
        let data = try XCTUnwrap(request.urlRequest(key: key).httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    func testZImageRequestSendsOnlyTheDescriptionAndFixedOptions() throws {
        // A Flare-only quality must not leak into a model that has none.
        let request = try VeniceImageRequest(description: "  a robot librarian\n", model: .zImageTurbo, quality: .high)
        XCTAssertEqual(try body(request), [
            "model": "z-image-turbo", "prompt": "a robot librarian", "format": "png",
            "return_binary": true, "safe_mode": true, "hide_watermark": true,
            "embed_exif_metadata": false, "width": 1024, "height": 1024
        ])
    }

    func testFlareAlwaysNamesQualityAndResolution() throws {
        for quality in VeniceImageQuality.allCases {
            let request = try VeniceImageRequest(description: "a cat", model: .gptImageFlare, quality: quality)
            XCTAssertEqual(try body(request), [
                "model": "gpt-image-2-6-flare", "prompt": "a cat", "format": "png",
                "return_binary": true, "safe_mode": true, "hide_watermark": true,
                "embed_exif_metadata": false, "aspect_ratio": "1:1", "resolution": "1K",
                "quality": quality.rawValue
            ])
        }
    }

    func testRequestGoesToVeniceWithTheKeyOnlyInAuthorization() throws {
        let request = try VeniceImageRequest(description: "a cat", model: .standard, quality: .standard).urlRequest(key: key)
        XCTAssertEqual(request.url?.absoluteString, "https://api.venice.ai/api/v1/image/generate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.allHTTPHeaderFields, [
            "Authorization": "Bearer \(key)", "Content-Type": "application/json", "Accept": "image/png",
            "Accept-Language": "en", "User-Agent": "Charms (macOS)"
        ])
        XCTAssertFalse(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains(key))
    }

    func testDescriptionKeepsItsExactScalars() throws {
        let text = "\u{212B} cafe\u{301} 👩🏽‍💻"
        let request = try VeniceImageRequest(description: text, model: .standard, quality: .standard)
        let sent = try XCTUnwrap(body(request)["prompt"] as? String)
        XCTAssertTrue(sent.isExactly(text))
    }

    func testDescriptionsAreRefusedRatherThanTruncated() throws {
        for empty in ["", " \n\t "] {
            XCTAssertThrowsError(try VeniceImageRequest(description: empty, model: .standard, quality: .standard)) {
                XCTAssertEqual($0 as? VeniceImageError, .emptyDescription)
            }
        }
        XCTAssertNoThrow(try VeniceImageRequest(description: String(repeating: "a", count: 7500), model: .standard, quality: .standard))
        // 3,751 emoji are 7,502 UTF-16 units, the unit the service counts in.
        for long in [String(repeating: "a", count: 7501), String(repeating: "😀", count: 3751)] {
            XCTAssertThrowsError(try VeniceImageRequest(description: long, model: .standard, quality: .standard)) {
                XCTAssertEqual($0 as? VeniceImageError, .descriptionTooLong)
            }
        }
    }

    func testDefaultsAreTheCheapPrivateChoiceAndPricesMatchTheList() {
        XCTAssertEqual(VeniceImageModel.standard, .zImageTurbo)
        XCTAssertEqual(VeniceImageQuality.standard, .low)
        XCTAssertEqual(VeniceImageQuality.allCases.map { VeniceImageModel.zImageTurbo.priceInCents(quality: $0) }, [1, 1, 1])
        XCTAssertEqual(VeniceImageQuality.allCases.map { VeniceImageModel.gptImageFlare.priceInCents(quality: $0) }, [5, 7, 9])
    }

    // MARK: Client

    private func generate(maximumBytes: Int = 1024) async throws -> Data {
        let client = VeniceImageClient(protocolClasses: [VeniceStubProtocol.self], maximumBytes: maximumBytes)
        let request = try VeniceImageRequest(description: "a cat", model: .standard, quality: .standard)
        return try await client.image(for: request, key: key)
    }

    private func assertFailure(_ expected: VeniceImageError, maximumBytes: Int = 1024, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await generate(maximumBytes: maximumBytes)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? VeniceImageError, expected, file: file, line: line)
        }
        XCTAssertEqual(VeniceStubProtocol.requestCount, 1, "a paid request is never retried", file: file, line: line)
    }

    func testReturnsTheImageBytesFromOneRequest() async throws {
        VeniceStubProtocol.answer(.response(200, ["Content-Type": "image/png"], png))
        let data = try await generate()
        XCTAssertEqual(data, png)
        XCTAssertEqual(VeniceStubProtocol.requestCount, 1)
    }

    func testStatusesMapToWhatTheUserCanDo() async {
        let expected: [Int: VeniceImageError] = [
            400: .invalidRequest, 401: .rejectedKey, 402: .paymentRequired, 403: .forbidden,
            404: .modelUnavailable, 410: .modelUnavailable, 408: .timedOut, 422: .refused,
            429: .busy, 500: .unavailable, 502: .unavailable, 503: .busy, 504: .timedOut
        ]
        for (status, error) in expected {
            VeniceStubProtocol.answer(.response(status, ["Content-Type": "application/json"], Data(#"{"error":"secret prompt echo"}"#.utf8)))
            await assertFailure(error)
            XCTAssertFalse(error.localizedDescription.contains("secret prompt echo"))
        }
    }

    func testModeratedImagesAreNotUsedEvenWithStatus200() async {
        let cases: [(String, VeniceImageError)] = [("x-venice-is-content-violation", .refused), ("x-venice-is-blurred", .blurred)]
        for (header, error) in cases {
            VeniceStubProtocol.answer(.response(200, ["Content-Type": "image/png", header: "true"], png))
            await assertFailure(error)
        }
    }

    func testFalseModerationHeadersDoNotBlockAnImage() async throws {
        let headers = ["Content-Type": "image/png", "x-venice-is-content-violation": "false", "x-venice-is-blurred": "false"]
        VeniceStubProtocol.answer(.response(200, headers, png))
        let data = try await generate()
        XCTAssertEqual(data, png)
    }

    func testOnlyABoundedNonemptyImageIsAccepted() async {
        VeniceStubProtocol.answer(.response(200, ["Content-Type": "application/json"], Data(#"{"images":[]}"#.utf8)))
        await assertFailure(.unexpectedResponse)
        VeniceStubProtocol.answer(.response(200, ["Content-Type": "image/png"], Data()))
        await assertFailure(.unexpectedResponse)
        VeniceStubProtocol.answer(.response(200, ["Content-Type": "image/png", "Content-Length": "4096"], png))
        await assertFailure(.unexpectedResponse)
        VeniceStubProtocol.answer(.response(200, ["Content-Type": "image/png"], Data(repeating: 1, count: 1025)))
        await assertFailure(.unexpectedResponse)
    }

    func testARedirectNeverCarriesTheKeyElsewhere() async {
        VeniceStubProtocol.answer(.redirect(URL(string: "https://elsewhere.example/steal")!))
        do {
            _ = try await generate()
            XCTFail("a redirect is not an image")
        } catch {
            XCTAssertTrue(error is VeniceImageError)
        }
        XCTAssertEqual(VeniceStubProtocol.hosts, ["api.venice.ai"])
    }

    func testTransportFailuresMapWithoutRetrying() async {
        let expected: [(URLError.Code, VeniceImageError)] = [
            (.timedOut, .timedOut), (.notConnectedToInternet, .offline), (.networkConnectionLost, .connectionFailed)
        ]
        for (code, error) in expected {
            VeniceStubProtocol.answer(.failure(URLError(code)))
            await assertFailure(error)
        }
    }

    func testCancellationIsNotReportedAsAFailure() async throws {
        let started = expectation(description: "request started")
        VeniceStubProtocol.answer(.hang { started.fulfill() })
        let task = Task { try await generate() }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    func testSessionKeepsNoStateAndWaitsLongEnoughForAnImage() {
        let session = ProviderSession.make(requestTimeout: 120, resourceTimeout: 180)
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertNil(session.configuration.urlCredentialStorage)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 120)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 180)
        let gifs = GIFSession.make()
        defer { gifs.invalidateAndCancel() }
        XCTAssertEqual(gifs.configuration.timeoutIntervalForRequest, 8)
        XCTAssertEqual(gifs.configuration.timeoutIntervalForResource, 20)
    }
}

private final class VeniceStubProtocol: URLProtocol, @unchecked Sendable {
    enum Answer {
        case response(Int, [String: String], Data)
        case redirect(URL)
        case failure(URLError)
        case hang(() -> Void)
    }

    private static let lock = NSLock()
    private static var current = Answer.response(500, [:], Data())
    private static var seen: [URLRequest] = []

    static var requestCount: Int { lock.withLock { seen.count } }
    static var hosts: [String] { lock.withLock { seen.compactMap { $0.url?.host } } }

    static func answer(_ answer: Answer) {
        lock.withLock {
            current = answer
            seen = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let answer = Self.lock.withLock {
            Self.seen.append(request)
            return Self.current
        }
        guard let url = request.url else { return }
        switch answer {
        case .response(let status, let headers, let data):
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let target):
            guard let response = HTTPURLResponse(url: url, statusCode: 307, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString]) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .hang(let started):
            started()
        }
    }
}
