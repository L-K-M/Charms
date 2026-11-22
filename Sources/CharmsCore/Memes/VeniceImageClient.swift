import Foundation

public protocol VeniceImageGenerating: Sendable {
    func image(for request: VeniceImageRequest, key: String) async throws -> Data
}

/// Sends one request to Venice's image endpoint. Nothing is retried, because
/// each request can be billed.
public final class VeniceImageClient: VeniceImageGenerating {
    static let maximumResponseBytes = 24 * 1024 * 1024
    private static let requestTimeout: TimeInterval = 120
    private static let resourceTimeout: TimeInterval = 180

    private let session: URLSession
    private let maximumBytes: Int

    public init() {
        session = ProviderSession.make(requestTimeout: Self.requestTimeout, resourceTimeout: Self.resourceTimeout)
        maximumBytes = Self.maximumResponseBytes
    }

    /// Tests route requests through a stub `URLProtocol`.
    init(protocolClasses: [AnyClass], maximumBytes: Int = VeniceImageClient.maximumResponseBytes) {
        session = ProviderSession.make(requestTimeout: Self.requestTimeout, resourceTimeout: Self.resourceTimeout, protocolClasses: protocolClasses)
        self.maximumBytes = maximumBytes
    }

    deinit { session.invalidateAndCancel() }

    public func image(for request: VeniceImageRequest, key: String) async throws -> Data {
        let urlRequest = try request.urlRequest(key: key)
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: urlRequest)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.url?.host == VeniceImageRequest.endpoint.host else {
                throw VeniceImageError.unexpectedResponse
            }
            guard http.statusCode == 200 else { throw VeniceImageError(status: http.statusCode) }
            // Moderation can answer 200 with a black or blurred picture.
            if Self.flag("x-venice-is-content-violation", in: http) { throw VeniceImageError.refused }
            if Self.flag("x-venice-is-blurred", in: http) { throw VeniceImageError.blurred }
            guard let type = http.mimeType?.lowercased(), type.hasPrefix("image/"),
                  http.expectedContentLength <= Int64(maximumBytes) else {
                throw VeniceImageError.unexpectedResponse
            }

            var data = Data()
            if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
            for try await byte in bytes {
                data.append(byte)
                if data.count > maximumBytes { throw VeniceImageError.unexpectedResponse }
            }
            try Task.checkCancellation()
            guard !data.isEmpty else { throw VeniceImageError.unexpectedResponse }
            return data
        } catch let error as VeniceImageError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled, Task.isCancelled { throw CancellationError() }
            throw VeniceImageError(error)
        } catch {
            throw VeniceImageError.connectionFailed
        }
    }

    private static func flag(_ name: String, in response: HTTPURLResponse) -> Bool {
        response.value(forHTTPHeaderField: name)?.lowercased() == "true"
    }
}
