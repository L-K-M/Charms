import AppKit
import CharmsCore
import SwiftUI

/// Settings ▸ Memes: whether the composer may use Venice, and its key.
struct MemeSettingsView: View {
    @ObservedObject var venice: VeniceArtworkService
    @ObservedObject var preferences: PreferencesStore
    @State private var keyDraft = ""
    @State private var keyMessage: String?

    var body: some View {
        Form {
            Section("Venice") {
                Toggle("Generate meme artwork with Venice", isOn: preferences.binding(\.veniceImagesEnabled))
                    // A key removed outside Charms must not trap the switch on.
                    .disabled(!venice.hasKey && !preferences.value.veniceImagesEnabled)
                SecureField("API key", text: $keyDraft)
                    .onSubmit(saveKey)
                    .autocorrectionDisabled()
                HStack {
                    Button("Save Key", action: saveKey).disabled(keyDraft.isEmpty)
                    if venice.hasKey {
                        Button("Remove Key") {
                            keyMessage = venice.setKey(nil)
                            keyDraft = ""
                        }
                    }
                    Button("Get a Key…") { NSWorkspace.shared.open(VeniceArtworkService.keyPage) }
                }
                if let keyMessage {
                    Text(keyMessage).font(.callout).foregroundStyle(.orange)
                }
                Text(keyHint).font(.callout).foregroundStyle(.secondary)
                Text("Venice bills your account for each image. Use an inference key with a spending limit. Choose the model in the meme composer.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("What is sent") {
                Text("Nothing until you press Generate. Then Charms sends the scene description, your key, and the model and image options to Venice. Your images, captions and the text you were typing are never sent.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(VeniceImageModel.allCases) { model in
                    LabeledContent(model.name) {
                        Text(model.privacyNote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: venice.refreshKeyPresence)
    }

    private var keyHint: String {
        venice.hasKey
            ? "A Venice key is saved. Saving another replaces it."
            : "No Venice key yet. Image Playground and your own images work without one."
    }

    private func saveKey() {
        guard !keyDraft.isEmpty else { return }
        keyMessage = venice.setKey(keyDraft)
        if keyMessage == nil { keyDraft = "" }
    }
}
