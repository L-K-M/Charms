import AppKit
import CharmsCore

/// An in-memory draft owned by one composer window.
@MainActor
final class MemeDraft: ObservableObject {
    typealias Suggest = (CGImage, String) async throws -> String

    enum Activity {
        case idle, importing, generating
    }

    @Published var sceneDescription = ""
    @Published var isDropTargeted = false
    @Published private(set) var activity = Activity.idle
    @Published private(set) var preview: CGImage?
    @Published private(set) var caption = ""
    @Published private(set) var isSuggesting = false
    @Published private(set) var notice: String?
    private var artwork: CGImage?
    private var suggestion: Task<Void, Never>?
    private var loading: Task<Void, Never>?
    /// A caption the user wrote outlives the artwork it was written for.
    private var hasUserCaption = false

    var hasArtwork: Bool { artwork != nil }
    var isBusy: Bool { activity != .idle }

    func acceptTemporaryArtwork(at url: URL, prompt: String, suggest: @escaping Suggest = MemeCaptioner.suggest) {
        // Image Playground gives its delegate a temporary file to consume.
        // Decode eagerly so the draft no longer needs the file after unlinking.
        // Only this path removes a file: images the user hands over are theirs.
        let image = try? MemeImageDecoder.decodeFile(at: url)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            notice = "Charms couldn’t remove Image Playground’s temporary image."
            return
        }
        guard let image else {
            notice = "Charms couldn’t read that image. Choose another in Image Playground."
            return
        }
        accept(image, prompt: prompt, suggest: suggest)
    }

    /// Runs one artwork operation. A second is refused while it lasts, and a
    /// failure leaves the artwork and caption as they were.
    func loadArtwork(_ kind: Activity, prompt: String, suggest: @escaping Suggest = MemeCaptioner.suggest,
                     load: @escaping () async throws -> CGImage) {
        guard !isBusy else { return }
        activity = kind
        notice = nil
        loading = Task { [weak self] in
            do {
                let image = try await load()
                guard !Task.isCancelled, let self else { return }
                self.finishLoading()
                self.accept(image, prompt: prompt, suggest: suggest)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.finishLoading()
                self.notice = (error as? LocalizedError)?.errorDescription ?? "Charms couldn’t use that image. Try another."
            }
        }
    }

    func stopLoading() {
        guard isBusy else { return }
        let stopped = activity
        loading?.cancel()
        finishLoading()
        notice = stopped == .generating ? "Stopped. Venice may still bill a request it already received." : nil
    }

    private func finishLoading() {
        loading = nil
        activity = .idle
    }

    private func accept(_ image: CGImage, prompt: String, suggest: @escaping Suggest) {
        stopSuggesting()
        artwork = image
        notice = nil
        if hasUserCaption {
            render()
            return
        }
        caption = ""
        preview = image
        isSuggesting = true
        suggestion = Task { [weak self] in
            do {
                let text = try await suggest(image, prompt)
                guard !Task.isCancelled else { return }
                self?.applyCaption(text)
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
        // A text field also reports its unchanged value, for example on focus.
        guard !text.isExactly(caption) else { return }
        applyCaption(text)
        hasUserCaption = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyCaption(_ text: String) {
        stopSuggesting()
        caption = String(text.prefix(MemeCaptioner.maximumCaptionCharacters))
        notice = nil
        render()
    }

    private func render() {
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
        !isBusy && preview != nil && !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
