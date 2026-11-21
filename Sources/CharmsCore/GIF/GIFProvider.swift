import Foundation

/// A GIF search service. Tenor is not one: Google shut its public API down
/// on 30 June 2026.
public enum GIFProvider: String, Sendable, CaseIterable, Identifiable {
    case klipy, giphy

    public var id: String { rawValue }

    public static let standard = GIFProvider.klipy

    public var name: String {
        switch self {
        case .klipy: return "KLIPY"
        case .giphy: return "GIPHY"
        }
    }

    /// Both services require this line wherever their results are shown.
    public var attribution: String { "Powered by \(name)" }

    /// Where a developer key is created.
    public var keyPage: URL {
        switch self {
        case .klipy: return URL(string: "https://partner.klipy.com")!
        case .giphy: return URL(string: "https://developers.giphy.com/dashboard/")!
        }
    }

    /// The API host. Search requests go nowhere else.
    var apiHost: String {
        switch self {
        case .klipy: return "api.klipy.com"
        case .giphy: return "api.giphy.com"
        }
    }
}

/// How strict the service's content filter is.
public enum GIFRating: String, Sendable, CaseIterable, Identifiable {
    case g, pg, pg13 = "pg-13", r

    public var id: String { rawValue }

    /// A workplace default.
    public static let standard = GIFRating.pg

    public var title: String {
        switch self {
        case .g: return "G: suitable for everyone"
        case .pg: return "PG: mild"
        case .pg13: return "PG-13: moderate"
        case .r: return "R: unrestricted"
        }
    }

    /// KLIPY names its levels after how much it filters.
    var klipyFilter: String {
        switch self {
        case .g: return "high"
        case .pg: return "medium"
        case .pg13: return "low"
        case .r: return "off"
        }
    }
}
