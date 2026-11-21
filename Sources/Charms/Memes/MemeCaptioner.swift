import CoreGraphics
import Foundation
#if canImport(FoundationModels) && canImport(_Vision_FoundationModels)
import FoundationModels
#endif

enum MemeCaptioner {
    static let maximumCaptionCharacters = 180
    private enum Failure: Error { case unavailable, invalidCaption }

    static func suggest(for artwork: CGImage, prompt: String) async throws -> String {
        #if canImport(FoundationModels) && canImport(_Vision_FoundationModels)
        if #available(macOS 27, *) {
            let model = SystemLanguageModel(useCase: .general)
            guard model.isAvailable, model.capabilities.contains(.vision) else { throw Failure.unavailable }
            try Task.checkCancellation()
            let session = LanguageModelSession(
                model: model,
                instructions: """
                Write one funny, short meme caption for the supplied artwork. The description is what the
                user asked Image Playground to draw. Return the caption alone, without quotation marks,
                using at most \(maximumCaptionCharacters) characters.
                """
            )
            let request = Prompt {
                prompt
                Attachment(artwork)
            }
            let response = try await session.respond(to: request, options: GenerationOptions(maximumResponseTokens: 128))
            try Task.checkCancellation()
            let caption = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !caption.isEmpty, caption.count <= maximumCaptionCharacters else { throw Failure.invalidCaption }
            return caption
        }
        #endif
        throw Failure.unavailable
    }
}
