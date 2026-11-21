import Foundation

/// Which GIF media Charms fetches by itself.
///
/// A preview is an image hotlinked from a GIF service's media host, which
/// the service loads for the reader. Charms therefore fetches media only
/// from the services it integrates with, and only for previews the picker
/// asks for. Every other remote address is left alone.
public enum GIFMediaPolicy {
    /// Registrable domains of the GIF services. Their media hosts are
    /// subdomains (for example `media2.giphy.com`, `static.klipy.com`).
    public static let serviceDomains = ["giphy.com", "klipy.com"]
    /// GIFs are larger than link preview pictures; a long one at full size
    /// is several megabytes.
    public static let maximumMediaBytes = 12 * 1024 * 1024
    /// The longest address accepted from a service.
    public static let maximumURLLength = 2048
    /// One preview fetched for the picker.
    public static let maximumPreviewBytes = 1 * 1024 * 1024
    /// All cached previews together.
    public static let maximumPreviewCacheBytes = 32 * 1024 * 1024

    /// True for an HTTPS address on a GIF service's domain, on the default
    /// port, without credentials.
    public static func isServiceMedia(_ url: URL, provider: GIFProvider? = nil) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.absoluteString.utf8.count <= maximumURLLength,
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        let domains = provider.map { [$0.rawValue + ".com"] } ?? serviceDomains
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The address of a service media file when Charms may load it, else nil.
    public static func mediaURL(_ src: String) -> URL? {
        let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), isServiceMedia(url) else { return nil }
        return url
    }
}
