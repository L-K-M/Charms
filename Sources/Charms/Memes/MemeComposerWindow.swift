import AppKit
import SwiftUI
#if canImport(ImagePlayground)
import ImagePlayground
#endif

@MainActor
final class MemeComposerWindow: NSObject, NSWindowDelegate {
    private let prompt: String
    private let insertion: InsertionService
    private let draft = MemeDraft()
    private var window: NSWindow?
    var onClose: (() -> Void)?

    init(prompt: String, insertion: InsertionService) {
        self.prompt = prompt
        self.insertion = insertion
    }

    static var isAvailable: Bool {
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *) { return ImagePlaygroundViewController.isAvailable }
        #endif
        return false
    }

    func show(on screen: NSScreen?) {
        let editor = MemeEditorView(draft: draft, openPlayground: { [weak self] in self?.openPlayground() },
                                    cancel: { [weak self] in self?.window?.close() },
                                    copy: { [weak self] in self?.copyMeme() })
        let host = NSHostingController(rootView: editor)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 540),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered,
                              defer: false, screen: screen)
        self.window = window
        window.contentViewController = host
        window.title = "Create a Meme"
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        openPlayground()
    }

    private func openPlayground() {
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *), let host = window?.contentViewController, Self.isAvailable {
            let playground = ImagePlaygroundViewController()
            playground.delegate = self
            playground.concepts = [.text(prompt)]
            if #available(macOS 15.4, *) {
                playground.allowedGenerationStyles = [.animation, .illustration, .sketch]
                playground.selectedGenerationStyle = .illustration
            }
            host.presentAsSheet(playground)
        }
        #endif
    }

    private func copyMeme() {
        if draft.copy(using: insertion) { window?.close() }
    }

    func windowWillClose(_ notification: Notification) {
        draft.stopSuggesting()
        onClose?()
    }
}

#if canImport(ImagePlayground)
@available(macOS 15.1, *)
extension MemeComposerWindow: ImagePlaygroundViewController.Delegate {
    func imagePlaygroundViewController(_ controller: ImagePlaygroundViewController, didCreateImageAt url: URL) {
        draft.acceptTemporaryArtwork(at: url, prompt: prompt)
        controller.dismiss(nil)
    }

    func imagePlaygroundViewControllerDidCancel(_ controller: ImagePlaygroundViewController) {
        controller.dismiss(nil)
        window?.close()
    }
}
#endif

private struct MemeEditorView: View {
    @ObservedObject var draft: MemeDraft
    let openPlayground: () -> Void
    let cancel: () -> Void
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = draft.preview {
                Image(image, scale: 1, label: Text("Meme preview"))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }

            if draft.isSuggesting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Writing a caption…")
                }
            }
            if let notice = draft.notice {
                Text(notice).foregroundStyle(.secondary)
            }

            if draft.preview != nil || !draft.caption.isEmpty {
                TextField("Caption", text: Binding(get: { draft.caption }, set: draft.editCaption), axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Meme caption")
                HStack {
                    Spacer()
                    Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                    Button("Copy PNG", action: copy)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!draft.canCopy)
                }
            } else {
                Button("Open Image Playground…", action: openPlayground)
            }
        }
        .padding(18)
        .frame(minWidth: 380, minHeight: 360)
    }
}
