import Foundation
import Security

/// Where Charms keeps the GIF service keys. A key is a credential for the
/// user's own developer account, so it goes to the Keychain in the real
/// home, never to logs or diagnostics. An isolated home
/// (`CHARMS_HOME`) keeps its own keys in its own directory, so it cannot
/// read or change the real ones.
public protocol GIFServiceKeyStoring: Sendable {
    func key(for provider: GIFProvider) -> String?
    func setKey(_ key: String?, for provider: GIFProvider) throws
}

public enum GIFServiceKeyError: Error, LocalizedError, Equatable {
    case implausible
    case keychain(OSStatus)
    case storage(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .implausible: return "That does not look like a GIF service key. Paste the key from the service's developer page."
        case .keychain(let status): return "The key could not be saved in the Keychain (\(status))."
        case .storage: return "The GIF service key could not be saved. Check that Charms can write its application-support folder."
        }
    }

    init(_ error: SecretStoreError) {
        switch error {
        case .keychain(let status): self = .keychain(status)
        case .storage(let path, let reason): self = .storage(path: path, reason: reason)
        }
    }

    /// Trims and checks a key on its way into a store. Nil removes it.
    static func save(_ key: String?, for provider: GIFProvider, in secrets: some SecretStoring) throws {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty || GIFSearchRequest.isPlausibleKey(trimmed) else { throw GIFServiceKeyError.implausible }
        do {
            try secrets.setSecret(trimmed.isEmpty ? nil : trimmed, for: provider.rawValue)
        } catch let error as SecretStoreError {
            throw GIFServiceKeyError(error)
        }
    }
}

/// One generic-password item per service, on this Mac only.
public struct KeychainGIFServiceKeyStore: GIFServiceKeyStoring {
    public static let service = "ch.lkmc.Charms.gif-service-key"

    private let secrets = KeychainSecretStore(service: Self.service)

    public init() {}

    public func key(for provider: GIFProvider) -> String? {
        guard let key = try? secrets.secret(for: provider.rawValue), GIFSearchRequest.isPlausibleKey(key) else { return nil }
        return key
    }

    /// A nil or empty key removes the stored one.
    public func setKey(_ key: String?, for provider: GIFProvider) throws {
        try GIFServiceKeyError.save(key, for: provider, in: secrets)
    }
}

/// Keys for an isolated home, as one JSON file readable only by this user.
public struct FileGIFServiceKeyStore: GIFServiceKeyStoring {
    public static let fileName = "gif-service-keys.json"

    private let secrets: FileSecretStore

    public init(directory: URL) {
        secrets = FileSecretStore(directory: directory, fileName: Self.fileName)
    }

    public func key(for provider: GIFProvider) -> String? {
        guard let key = try? secrets.secret(for: provider.rawValue), GIFSearchRequest.isPlausibleKey(key) else { return nil }
        return key
    }

    /// A nil or empty key removes the stored one, and an emptied file is
    /// deleted.
    public func setKey(_ key: String?, for provider: GIFProvider) throws {
        try GIFServiceKeyError.save(key, for: provider, in: secrets)
    }
}

public enum GIFServiceKeyStores {
    /// An explicit CHARMS_HOME keeps its keys on disk even when it aliases
    /// the default support directory. Only the ordinary app uses the Keychain.
    public static func make(supportDirectory: URL, isIsolated: Bool) -> any GIFServiceKeyStoring {
        if isIsolated { return FileGIFServiceKeyStore(directory: supportDirectory) }
        return KeychainGIFServiceKeyStore()
    }
}
