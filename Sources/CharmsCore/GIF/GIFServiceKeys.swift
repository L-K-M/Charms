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
}

/// One generic-password item per service, on this Mac only.
public struct KeychainGIFServiceKeyStore: GIFServiceKeyStoring {
    public static let service = "ch.lkmc.Charms.gif-service-key"

    public init() {}

    private func query(_ provider: GIFProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: provider.rawValue]
    }

    public func key(for provider: GIFProvider) -> String? {
        var item = query(provider)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), GIFSearchRequest.isPlausibleKey(key) else { return nil }
        return key
    }

    /// A nil or empty key removes the stored one.
    public func setKey(_ key: String?, for provider: GIFProvider) throws {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            let status = SecItemDelete(query(provider) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw GIFServiceKeyError.keychain(status) }
            return
        }
        guard GIFSearchRequest.isPlausibleKey(trimmed) else { throw GIFServiceKeyError.implausible }
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(provider)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw GIFServiceKeyError.keychain(added) }
        } else if status != errSecSuccess {
            throw GIFServiceKeyError.keychain(status)
        }
    }
}

/// Keys for an isolated home, as one JSON file readable only by this user.
public struct FileGIFServiceKeyStore: GIFServiceKeyStoring {
    public static let fileName = "gif-service-keys.json"

    private struct Storage: Codable {
        var keys: [String: String]
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public func key(for provider: GIFProvider) -> String? {
        guard let key = try? load().keys[provider.rawValue], GIFSearchRequest.isPlausibleKey(key) else { return nil }
        return key
    }

    /// A nil or empty key removes the stored one, and an emptied file is
    /// deleted.
    public func setKey(_ key: String?, for provider: GIFProvider) throws {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var storage = try load()
        if trimmed.isEmpty {
            storage.keys[provider.rawValue] = nil
            if storage.keys.isEmpty { try remove() } else { try save(storage) }
            return
        }
        guard GIFSearchRequest.isPlausibleKey(trimmed) else { throw GIFServiceKeyError.implausible }
        storage.keys[provider.rawValue] = trimmed
        try save(storage)
    }

    private func load() throws -> Storage {
        do {
            return try JSONDecoder().decode(Storage.self, from: Data(contentsOf: fileURL))
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return Storage(keys: [:])
        } catch {
            throw GIFServiceKeyError.storage(path: fileURL.path, reason: "reading failed")
        }
    }

    private func save(_ storage: Storage) throws {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Publish a complete, already-private file, including when replacing
            // a key in an existing isolated home with permissive directory modes.
            let staging = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: staging, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: staging) }
            let temporary = staging.appendingPathComponent(Self.fileName)
            try JSONEncoder().encode(storage).write(to: temporary)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            guard rename(temporary.path, fileURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            throw GIFServiceKeyError.storage(path: fileURL.path, reason: error.localizedDescription)
        }
    }

    private func remove() throws {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        } catch {
            throw GIFServiceKeyError.storage(path: fileURL.path, reason: error.localizedDescription)
        }
    }
}

public enum GIFServiceKeyStores {
    /// The real home keeps its keys in the Keychain. Every other directory
    /// is an isolated home and keeps them in that directory, so it never
    /// touches the real keys.
    public static func make(supportDirectory: URL) -> any GIFServiceKeyStoring {
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let real = base.appendingPathComponent("Charms", isDirectory: true)
            if samePath(supportDirectory, real) { return KeychainGIFServiceKeyStore() }
        }
        return FileGIFServiceKeyStore(directory: supportDirectory)
    }

    private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
