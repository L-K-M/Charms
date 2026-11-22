import Foundation

/// GIF answers are small and quick, so their deadlines are short.
enum GIFSession {
    static func make(protocolClasses: [AnyClass]? = nil) -> URLSession {
        ProviderSession.make(requestTimeout: 8, resourceTimeout: 20, protocolClasses: protocolClasses)
    }
}

/// Searches one GIF service.
public protocol GIFSearching: Sendable {
    var provider: GIFProvider { get }
    /// Trending GIFs for an empty query. `cursor` is a previous page's `next`.
    func page(query: String, cursor: Int?) async throws -> GIFPage
}

/// Talks to the service's API host only. The request carries the service
/// key and the query; never anything else.
public final class GIFSearchClient: GIFSearching {
    public static let maximumResponseBytes = 2 * 1024 * 1024
    static let userAgent = "Charms (macOS)"
    public let request: GIFSearchRequest
    public var provider: GIFProvider { request.provider }
    private let session: URLSession

    public init(request: GIFSearchRequest) {
        self.request = request
        self.session = GIFSession.make()
    }

    /// Tests route requests through a stub `URLProtocol`.
    init(request: GIFSearchRequest, protocolClasses: [AnyClass]) {
        self.request = request
        self.session = GIFSession.make(protocolClasses: protocolClasses)
    }

    deinit { session.invalidateAndCancel() }

    public func page(query: String, cursor: Int?) async throws -> GIFPage {
        let url = try request.url(query: query, cursor: cursor)
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        var data = Data(), response: URLResponse
        do {
            // Read as it arrives, so an oversized answer stops at the cap.
            let (bytes, head) = try await session.bytes(for: urlRequest)
            response = head
            guard head.expectedContentLength <= Int64(Self.maximumResponseBytes) else { bytes.task.cancel(); throw GIFSearchError.malformed }
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maximumResponseBytes { bytes.task.cancel(); throw GIFSearchError.malformed }
            }
        }
        catch let error as GIFSearchError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw GIFSearchError.unavailable }
        guard let http = response as? HTTPURLResponse, http.url?.host == url.host else { throw GIFSearchError.unavailable }
        guard (200...299).contains(http.statusCode) else { throw request.error(status: http.statusCode, body: data) }
        return try request.page(from: data, cursor: cursor)
    }
}
