import Foundation

public enum VeniceImageQuality: String, Codable, Sendable, CaseIterable, Identifiable {
    case low, medium, high

    /// Venice bills `high` when a request names no quality. Charms starts
    /// with the cheapest and always names one.
    public static let standard = VeniceImageQuality.low

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}
