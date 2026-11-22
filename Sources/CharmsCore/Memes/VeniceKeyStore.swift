import Foundation

public enum VeniceKeyError: Error, LocalizedError, Equatable {
    case implausible
    case keychain(OSStatus)
    case storage

    public var errorDescription: String? {
        switch self {
        case .implausible: return "That does not look like a Venice API key. Paste the key from Venice’s API settings."
        case .keychain(let status): return "The Keychain could not change the Venice key (\(status))."
        case .storage: return "The Venice key could not be saved. Check that Charms can write its application-support folder."
        }
    }
}

/// The user's Venice key: in the Keychain in the real home, in a private
/// file in an isolated one (`CHARMS_HOME`).
public struct VeniceKeyStore: Sendable {
    public static let service = "ch.lkmc.Charms.image-service-key"
    public static let fileName = "image-service-keys.json"
    private static let account = "venice"
    private static let keyLengths = 16...512

    private let secrets: any SecretStoring

    public init(secrets: any SecretStoring) {
        self.secrets = secrets
    }

    /// An explicit CHARMS_HOME never reaches the Keychain, even when it
    /// aliases the default support directory.
    public static func make(supportDirectory: URL, isIsolated: Bool) -> VeniceKeyStore {
        if isIsolated { return VeniceKeyStore(secrets: FileSecretStore(directory: supportDirectory, fileName: fileName)) }
        return VeniceKeyStore(secrets: KeychainSecretStore(service: service))
    }

    /// Printable ASCII without spaces, so a key cannot add a header.
    static func isPlausible(_ key: String) -> Bool {
        keyLengths.contains(key.utf8.count) && key.utf8.allSatisfy { (0x21...0x7E).contains($0) }
    }

    /// Reads the key. This can wait for a Keychain prompt, so do not call it
    /// on the main thread.
    public func key() throws -> String? {
        guard let key = try secrets.secret(for: Self.account), Self.isPlausible(key) else { return nil }
        return key
    }

    public var hasKey: Bool { secrets.containsSecret(for: Self.account) }

    /// A nil or empty key removes the stored one.
    public func setKey(_ key: String?) throws {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty || Self.isPlausible(trimmed) else { throw VeniceKeyError.implausible }
        do {
            try secrets.setSecret(trimmed.isEmpty ? nil : trimmed, for: Self.account)
        } catch SecretStoreError.keychain(let status) {
            throw VeniceKeyError.keychain(status)
        } catch is SecretStoreError {
            throw VeniceKeyError.storage
        }
    }
}
