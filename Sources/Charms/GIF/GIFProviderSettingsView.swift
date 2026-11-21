import AppKit
import CharmsCore
import SwiftUI

/// Settings ▸ GIFs ▸ Online: which service the picker searches, its key
/// and how strictly it filters. Keys are stored per service; an isolated
/// home keeps them in its own directory and never touches the real ones.
struct GIFProviderSettingsView: View {
    @ObservedObject var service: OnlineGIFSearch
    @State private var keyDraft = ""
    @State private var keyMessage: String?

    var body: some View {
        Section("Online GIFs") {
            Picker("Search with", selection: providerBinding) {
                ForEach(GIFProvider.allCases) { provider in
                    Text(provider.name).tag(provider)
                }
            }

            SecureField("Key", text: $keyDraft)
                .onSubmit(saveKey)
                .autocorrectionDisabled()
            HStack {
                Button("Save Key") { saveKey() }.disabled(keyDraft.isEmpty)
                if service.hasKey {
                    Button("Remove Key") {
                        keyMessage = service.setKey(nil, for: service.provider)
                        keyDraft = ""
                    }
                }
                Button("Get a Key…") { openKeyPage() }
                if let keyMessage {
                    Text(keyMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(keyHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Content rating", selection: ratingBinding) {
                ForEach(GIFRating.allCases) { rating in
                    Text(rating.title).tag(rating)
                }
            }
        }
        .onAppear(perform: loadKey)
        .onChange(of: service.provider) { loadKey() }
    }

    private var providerBinding: Binding<GIFProvider> {
        Binding(
            get: { service.provider },
            set: { provider in
                service.setProvider(provider)
            }
        )
    }

    private var ratingBinding: Binding<GIFRating> {
        Binding(get: { service.rating }, set: { service.setRating($0) })
    }

    private var keyHint: String {
        service.hasKey
            ? "The \(service.provider.name) key is saved. Searching sends it only to \(service.provider.name)."
            : "No \(service.provider.name) key yet. Online search stays off until you add one."
    }

    private func loadKey() {
        _ = service.key(for: service.provider)
        keyDraft = ""
        keyMessage = nil
    }

    private func saveKey() {
        guard !keyDraft.isEmpty else { return }
        keyMessage = service.setKey(keyDraft, for: service.provider)
        if keyMessage == nil { keyDraft = "" }
    }

    private func openKeyPage() {
        NSWorkspace.shared.open(service.provider.keyPage)
    }
}
