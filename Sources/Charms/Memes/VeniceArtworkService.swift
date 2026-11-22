import CharmsCore
import Combine
import Foundation

/// The one place Memes reaches Venice through. It sends nothing until
/// `generate` is called, and then only while the user has Venice switched on.
@MainActor
final class VeniceArtworkService: ObservableObject {
    static let keyPage = URL(string: "https://venice.ai/settings/api")!

    @Published private(set) var hasKey = false

    private let preferences: PreferencesStore
    private let keys: VeniceKeyStore
    private let client: any VeniceImageGenerating

    init(preferences: PreferencesStore, keys: VeniceKeyStore, client: any VeniceImageGenerating = VeniceImageClient()) {
        self.preferences = preferences
        self.keys = keys
        self.client = client
    }

    /// Looks whether a key is saved without reading it.
    func refreshKeyPresence() {
        hasKey = keys.hasKey
    }

    /// Saves or removes the key. Returns nil on success, else the message
    /// to show. Removing it also switches Venice off.
    func setKey(_ key: String?) -> String? {
        do {
            try keys.setKey(key)
        } catch {
            return error.localizedDescription
        }
        refreshKeyPresence()
        if !hasKey { preferences.update { $0.veniceImagesEnabled = false } }
        return nil
    }

    func generate(description: String) async throws -> Data {
        // The model is the one shown when Generate was pressed.
        let choice = preferences.value
        guard choice.veniceImagesEnabled else { throw VeniceImageError.turnedOff }
        let request = try VeniceImageRequest(description: description, model: choice.veniceModel, quality: choice.veniceQuality)

        let keys = keys
        let key: String?
        do {
            // Reading can wait for a Keychain prompt.
            key = try await Task.detached { try keys.key() }.value
        } catch {
            throw VeniceImageError.keyUnreadable
        }
        guard let key else {
            refreshKeyPresence()
            throw VeniceImageError.missingKey
        }
        // Stop, closing the window and switching Venice off all count until
        // the request leaves.
        try Task.checkCancellation()
        guard preferences.value.veniceImagesEnabled else { throw VeniceImageError.turnedOff }
        return try await client.image(for: request, key: key)
    }
}
