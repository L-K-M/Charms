import AppKit
import CharmsCore
import Combine
import SwiftUI
import UniformTypeIdentifiers
#if canImport(ImagePlayground)
import ImagePlayground
#endif

@MainActor
final class MemeComposerWindow: NSObject, NSWindowDelegate {
    private static let size = NSSize(width: 540, height: 660)
    private static let minimumSize = NSSize(width: 460, height: 580)

    private let insertion: InsertionService
    private let preferences: PreferencesStore
    private let venice: VeniceArtworkService
    private let showSettings: () -> Void
    private let draft = MemeDraft()
    private var window: NSWindow?
    /// The description Image Playground was opened with.
    private var playgroundPrompt = ""
    private var subscriptions = Set<AnyCancellable>()
    var onClose: (() -> Void)?

    init(prompt: String, insertion: InsertionService, preferences: PreferencesStore,
         venice: VeniceArtworkService, showSettings: @escaping () -> Void) {
        self.insertion = insertion
        self.preferences = preferences
        self.venice = venice
        self.showSettings = showSettings
        super.init()
        draft.sceneDescription = prompt
    }

    static var isPlaygroundAvailable: Bool {
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *) { return ImagePlaygroundViewController.isAvailable }
        #endif
        return false
    }

    func show(on screen: NSScreen?) {
        venice.refreshKeyPresence()
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered,
                              defer: false, screen: screen)
        self.window = window
        window.contentViewController = makeContent()
        window.contentMinSize = Self.minimumSize
        window.setContentSize(Self.size)
        window.title = "Create a Meme"
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        observe()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // With Venice on there is a choice to make, so nothing opens by itself.
        if !preferences.value.veniceImagesEnabled, !trimmedDescription.isEmpty { openPlayground(.apple) }
    }

    private var trimmedDescription: String {
        draft.sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAcceptArtwork: Bool {
        !draft.isBusy && window?.attachedSheet == nil
    }

    private func makeContent() -> NSViewController {
        let actions = MemeEditorActions(
            openPlayground: { [weak self] entry in self?.openPlayground(entry) },
            chooseImage: { [weak self] in self?.chooseImage() },
            generate: { [weak self] in self?.generate() },
            stop: { [weak self] in self?.draft.stopLoading() },
            showSettings: showSettings,
            cancel: { [weak self] in self?.window?.close() },
            copy: { [weak self] in self?.copyMeme() }
        )
        let editor = MemeEditorView(draft: draft, preferences: preferences, venice: venice,
                                    canUsePlayground: Self.isPlaygroundAvailable, actions: actions)

        let root = NSViewController()
        let drop = MemeDropView(frame: NSRect(origin: .zero, size: Self.size))
        drop.canAccept = { [weak self] in self?.canAcceptArtwork ?? false }
        drop.onTargeted = { [weak self] targeted in self?.draft.isDropTargeted = targeted }
        drop.onDrop = { [weak self] source in self?.receiveDrop(source) }

        let host = NSHostingController(rootView: editor)
        host.sizingOptions = []
        root.view = drop.covering(host.view, size: Self.size)
        root.addChild(host)
        return root
    }

    private func observe() {
        preferences.$value
            .map(\.veniceImagesEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard !enabled, let self, self.draft.activity == .generating else { return }
                self.draft.stopLoading()
            }
            .store(in: &subscriptions)

        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didResignActiveNotification)
            .merge(with: center.publisher(for: NSApplication.didBecomeActiveNotification))
            .map { _ in () }
            .merge(with: draft.$preview.map { _ in () })
            // Both the activation state and the draft settle after they report.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateLevel() }
            .store(in: &subscriptions)
    }

    /// An accessory app has no Dock icon to bring a window back with, and an
    /// image can only be dragged here while the composer is in view.
    private func updateLevel() {
        guard let window else { return }
        let awaitsDrop = !NSApp.isActive && !draft.hasArtwork && window.attachedSheet == nil
        window.level = awaitsDrop ? .floating : .normal
    }

    // MARK: Artwork sources

    private func openPlayground(_ entry: MemePlaygroundEntry) {
        #if canImport(ImagePlayground)
        guard #available(macOS 15.1, *), canAcceptArtwork,
              let host = window?.contentViewController, Self.isPlaygroundAvailable else { return }
        let playground = ImagePlaygroundViewController()
        playground.delegate = self
        playgroundPrompt = trimmedDescription
        playground.concepts = playgroundPrompt.isEmpty ? [] : [.text(playgroundPrompt)]
        if #available(macOS 15.4, *) {
            playground.allowedGenerationStyles = MemePlaygroundStyles.allowed
            playground.selectedGenerationStyle = MemePlaygroundStyles.initial(for: entry)
        }
        host.presentAsSheet(playground)
        #endif
    }

    private func chooseImage() {
        guard let window, canAcceptArtwork else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importImage(.file(url))
        }
    }

    private func receiveDrop(_ source: MemeImageSource) {
        importImage(source)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The typed description may have nothing to do with someone's own
    /// image, so the caption model gets only the picture.
    private func importImage(_ source: MemeImageSource) {
        draft.loadArtwork(.importing, prompt: "") { try await source.image() }
    }

    private func generate() {
        guard canAcceptArtwork else { return }
        let description = trimmedDescription
        draft.loadArtwork(.generating, prompt: description) { [venice] in
            let data = try await venice.generate(description: description)
            return try await MemeImageSource.data(data).image()
        }
    }

    private func copyMeme() {
        if draft.copy(using: insertion) { window?.close() }
    }

    func windowWillClose(_ notification: Notification) {
        subscriptions.removeAll()
        draft.stopLoading()
        draft.stopSuggesting()
        onClose?()
    }
}

#if canImport(ImagePlayground)
@available(macOS 15.1, *)
extension MemeComposerWindow: ImagePlaygroundViewController.Delegate {
    func imagePlaygroundViewController(_ controller: ImagePlaygroundViewController, didCreateImageAt url: URL) {
        draft.acceptTemporaryArtwork(at: url, prompt: playgroundPrompt)
        controller.dismiss(nil)
    }

    /// Back to the composer, where the other artwork sources are.
    func imagePlaygroundViewControllerDidCancel(_ controller: ImagePlaygroundViewController) {
        controller.dismiss(nil)
    }
}
#endif
