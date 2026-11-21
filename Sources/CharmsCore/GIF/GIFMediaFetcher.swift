import Foundation

/// Fetches a bounded preview from a GIF service's media host.
///
/// The address is checked against `GIFMediaPolicy` before anything is
/// sent, redirects are refused, and the answer stops at
/// `GIFMediaPolicy.maximumPreviewBytes`. A failure is nil, never a
/// partial or oversized payload.
public struct GIFMediaFetcher: Sendable {
    public static let maximumBytes = GIFMediaPolicy.maximumPreviewBytes
    private let session: URLSession

    public init() {
        self.session = GIFSession.make()
    }

    /// Tests inject a session whose `URLProtocol` answers locally.
    init(session: URLSession) {
        self.session = session
    }

    public func data(for url: URL) async -> Data? {
        guard GIFMediaPolicy.isServiceMedia(url) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("image/gif", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  http.url?.host?.lowercased() == url.host?.lowercased(),
                  http.expectedContentLength <= Int64(Self.maximumBytes) else { return nil }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maximumBytes { return nil }
            }
            return data
        } catch {
            return nil
        }
    }
}
