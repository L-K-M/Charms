import Foundation

/// One ephemeral session for GIF traffic: HTTPS, no cookies, no cache, no
/// credentials, redirects refused, answers capped.
enum GIFSession {
    static func make(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
    }
}

final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
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
