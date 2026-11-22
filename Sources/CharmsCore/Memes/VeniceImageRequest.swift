import Foundation

/// One image request. Pure, so tests can check exactly what would be sent.
public struct VeniceImageRequest: Sendable {
    /// Both offered models take at least this much; the endpoint takes no more.
    public static let maximumDescriptionLength = 7500
    static let endpoint = URL(string: "https://api.venice.ai/api/v1/image/generate")!
    private static let side = 1024

    public let model: VeniceImageModel
    public let quality: VeniceImageQuality
    let description: String

    public init(description: String, model: VeniceImageModel, quality: VeniceImageQuality) throws {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VeniceImageError.emptyDescription }
        guard trimmed.utf16.count <= Self.maximumDescriptionLength else { throw VeniceImageError.descriptionTooLong }
        self.description = trimmed
        self.model = model
        self.quality = quality
    }

    private struct Body: Encodable {
        let model: String
        let prompt: String
        let format = "png"
        let return_binary = true
        // Venice's default, stated so a changed default cannot switch it off.
        let safe_mode = true
        let hide_watermark = true
        // Metadata would carry the description inside the shared image.
        let embed_exif_metadata = false
        var width: Int?
        var height: Int?
        var aspect_ratio: String?
        var resolution: String?
        var quality: String?
    }

    func urlRequest(key: String) throws -> URLRequest {
        var body = Body(model: model.rawValue, prompt: description)
        switch model {
        case .zImageTurbo:
            body.width = Self.side
            body.height = Self.side
        case .gptImageFlare:
            body.aspect_ratio = "1:1"
            body.resolution = "1K"
            body.quality = quality.rawValue
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("image/png", forHTTPHeaderField: "Accept")
        // URLSession would otherwise name the app, the user's languages and
        // the OS build. Venice needs none of them to make an image.
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue("macOS", forHTTPHeaderField: "User-Agent")
        return request
    }
}
