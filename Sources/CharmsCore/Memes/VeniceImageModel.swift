import Foundation

/// The Venice models Memes offers. The identifiers, prices and privacy tiers
/// were read from Venice's `GET /models?type=image` on 22 November 2026.
public enum VeniceImageModel: String, Codable, Sendable, CaseIterable, Identifiable {
    case zImageTurbo = "z-image-turbo"
    case gptImageFlare = "gpt-image-2-6-flare"

    public static let standard = VeniceImageModel.zImageTurbo

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .zImageTurbo: return "Z-Image Turbo"
        case .gptImageFlare: return "GPT Image 2.6 Flare"
        }
    }

    public var offersQuality: Bool {
        switch self {
        case .zImageTurbo: return false
        case .gptImageFlare: return true
        }
    }

    /// What Venice says happens to the description with this model.
    public var privacyNote: String {
        switch self {
        case .zImageTurbo:
            return "Private: Venice says the description isn’t kept after the request."
        case .gptImageFlare:
            return "Anonymized: OpenAI can read the description. Venice says it withholds your identity."
        }
    }

    /// The list price in US cents of one 1K image. An estimate for the
    /// interface: Venice decides what is billed.
    public func priceInCents(quality: VeniceImageQuality) -> Int {
        switch (self, quality) {
        case (.zImageTurbo, _): return 1
        case (.gptImageFlare, .low): return 5
        case (.gptImageFlare, .medium): return 7
        case (.gptImageFlare, .high): return 9
        }
    }
}
