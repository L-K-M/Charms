import Foundation

/// One file of a GIF at one size.
public struct GIFRendition: Sendable, Equatable {
    public let url: URL
    public let width: Int
    public let height: Int
    /// Bytes, when the service says.
    public let bytes: Int?

    public init(url: URL, width: Int, height: Int, bytes: Int? = nil) {
        self.url = url
        self.width = width
        self.height = height
        self.bytes = bytes
    }
}

/// A search result.
public struct GIFItem: Sendable, Equatable, Identifiable {
    public let id: String
    /// The service's title, used as the image's alternative text.
    public let title: String
    /// Small and light, for the picker grid.
    public let preview: GIFRendition
    /// What is inserted: large enough to read in a conversation, small
    /// enough to send quickly.
    public let message: GIFRendition

    public init(id: String, title: String, preview: GIFRendition, message: GIFRendition) {
        self.id = id
        self.title = title
        self.preview = preview
        self.message = message
    }
}

public struct GIFPage: Sendable, Equatable {
    public let items: [GIFItem]
    /// Pass back to get the following page; nil at the end.
    public let next: Int?

    public init(items: [GIFItem], next: Int?) {
        self.items = items
        self.next = next
    }
}

public enum GIFSearchError: Error, Equatable, LocalizedError {
    case missingKey
    case rejectedKey
    case rateLimited
    case unavailable
    case malformed

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Add a GIF service key in Settings to search for GIFs."
        case .rejectedKey: return "The GIF service did not accept the key in Settings."
        case .rateLimited: return "The GIF service is limiting searches. Try again in a few minutes."
        case .unavailable: return "The GIF service could not be reached. Try again."
        case .malformed: return "The GIF service sent results Charms cannot read."
        }
    }
}
