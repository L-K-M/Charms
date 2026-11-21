import AppKit
import ImageIO

/// An in-memory draft owned by one composer window.
@MainActor
final class MemeDraft: ObservableObject {
    @Published private(set) var preview: CGImage?
    @Published private(set) var caption = ""
    @Published private(set) var isSuggesting = false
    @Published private(set) var notice: String?
    private var artwork: CGImage?
    private var suggestion: Task<Void, Never>?

    func accept(_ url: URL, prompt: String,
                suggest: @escaping (CGImage, String) async throws -> String = MemeCaptioner.suggest) {
        // Image Playground owns this temporary URL. Read the pixels before
        // returning from its delegate, including the file's orientation.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else {
            notice = "Charms couldn’t read that image. Choose another in Image Playground."
            return
        }
        stopSuggesting()
        caption = ""
        artwork = image
        preview = image
        isSuggesting = true
        notice = nil
        suggestion = Task { [weak self] in
            do {
                let text = try await suggest(image, prompt)
                guard !Task.isCancelled else { return }
                self?.editCaption(text)
            } catch {
                guard !Task.isCancelled else { return }
                self?.isSuggesting = false
                self?.notice = "The on-device caption is unavailable. Type your own caption below."
            }
        }
    }

    func stopSuggesting() {
        suggestion?.cancel()
        suggestion = nil
        isSuggesting = false
    }

    func editCaption(_ text: String) {
        stopSuggesting()
        caption = String(text.prefix(MemeCaptioner.maximumCaptionCharacters))
        notice = nil
        guard let artwork else { return }
        if caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preview = artwork
            return
        }
        do {
            preview = try MemeRenderer.render(artwork: artwork, caption: caption)
        } catch {
            preview = nil
            notice = "Charms couldn’t render this caption. Try a shorter one."
        }
    }

    var canCopy: Bool {
        preview != nil && !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func copy(using insertion: InsertionService) -> Bool {
        guard canCopy, let preview else { return false }
        do {
            let item = NSPasteboardItem()
            let png = try MemeRenderer.png(preview)
            guard item.setData(png, forType: .png), insertion.copy(item) else {
                notice = "Charms couldn’t copy the PNG. Try again."
                return false
            }
            return true
        } catch {
            notice = "Charms couldn’t encode the PNG. Try again."
            return false
        }
    }
}
