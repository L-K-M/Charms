import CharmsCore
import SwiftUI

/// What the composer's controls ask the window to do.
struct MemeEditorActions {
    let openPlayground: () -> Void
    let chooseImage: () -> Void
    let generate: () -> Void
    let stop: () -> Void
    let showSettings: () -> Void
    let cancel: () -> Void
    let copy: () -> Void
}

struct MemeEditorView: View {
    @ObservedObject var draft: MemeDraft
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var venice: VeniceArtworkService
    let canUsePlayground: Bool
    let actions: MemeEditorActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork
            status
            if draft.preview != nil || !draft.caption.isEmpty { captionField }
            Divider()
            sources
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: actions.cancel).keyboardShortcut(.cancelAction)
                Button("Copy PNG", action: actions.copy)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!draft.canCopy)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var artwork: some View {
        ZStack {
            if let image = draft.preview {
                Image(image, scale: 1, label: Text("Meme preview"))
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 30)).accessibilityHidden(true)
                    Text("Drop an image here, or create one below.")
                    Text("Images from offline generators such as Draw Things work too.").font(.callout)
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
        .overlay {
            if draft.isDropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3)
            } else if draft.preview == nil {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
        }
    }

    @ViewBuilder private var status: some View {
        if draft.isBusy {
            HStack {
                ProgressView().controlSize(.small)
                Text(draft.activity == .generating ? "Generating with Venice…" : "Opening the image…")
                Spacer()
                Button("Stop", action: actions.stop).keyboardShortcut(".", modifiers: .command)
            }
        } else if draft.isSuggesting {
            HStack {
                ProgressView().controlSize(.small)
                Text("Writing a caption…")
            }
        }
        if let notice = draft.notice {
            Text(notice).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var captionField: some View {
        TextField("Caption", text: Binding(get: { draft.caption }, set: draft.editCaption), axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Meme caption")
    }

    @ViewBuilder private var sources: some View {
        TextField("Describe the scene", text: $draft.sceneDescription, axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Scene description")
            .disabled(draft.isBusy)
        HStack {
            Button("Image Playground…", action: actions.openPlayground)
                .disabled(!canUsePlayground || draft.isBusy)
            Button("Choose Image…", action: actions.chooseImage)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(draft.isBusy)
        }
        if !canUsePlayground {
            Text("Image Playground needs a compatible Mac with Apple Intelligence turned on.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if preferences.value.veniceImagesEnabled, venice.hasKey {
            veniceControls
        } else {
            HStack {
                Text("Generate here with your own Venice API key.").font(.caption).foregroundStyle(.secondary)
                Button("Set Up Venice…", action: actions.showSettings).controlSize(.small)
            }
        }
    }

    @ViewBuilder private var veniceControls: some View {
        let model = preferences.value.veniceModel
        let quality = preferences.value.veniceQuality
        HStack {
            Picker("Venice model", selection: preferences.binding(\.veniceModel)) {
                ForEach(VeniceImageModel.allCases) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            if model.offersQuality {
                Picker("Image quality", selection: preferences.binding(\.veniceQuality)) {
                    ForEach(VeniceImageQuality.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Spacer()
            Button("Generate", action: actions.generate)
                .keyboardShortcut("g", modifiers: .command)
                .disabled(draft.sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .disabled(draft.isBusy)
        Text("About \(Self.price(cents: model.priceInCents(quality: quality))) per image. Generate sends only the description to Venice. \(model.privacyNote)")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private static func price(cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }
}
