import Foundation
import Security

/// Storage for the service credentials the user saves, by account name.
public protocol SecretStoring: Sendable {
    /// Reads the value. This can make macOS ask for Keychain access.
    func secret(for account: String) throws -> String?
    /// Looks for a value without asking for Keychain access.
    func containsSecret(for account: String) -> Bool
    /// A nil value removes the stored one.
    func setSecret(_ secret: String?, for account: String) throws
}

public enum SecretStoreError: Error, Equatable {
    case keychain(OSStatus)
    case storage(path: String, reason: String)
}

/// One generic-password item per account, on this Mac only.
public struct KeychainSecretStore: SecretStoring {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func secret(for account: String) throws -> String? {
        var item = query(account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.keychain(errSecDecode)
        }
        return secret
    }

    public func containsSecret(for account: String) -> Bool {
        // Matching attributes alone does not consult the item's access list.
        SecItemCopyMatching(query(account) as CFDictionary, nil) == errSecSuccess
    }

    public func setSecret(_ secret: String?, for account: String) throws {
        guard let secret else {
            let status = SecItemDelete(query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
            return
        }
        let data = Data(secret.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw SecretStoreError.keychain(added) }
        } else if status != errSecSuccess {
            throw SecretStoreError.keychain(status)
        }
    }
}

/// Credentials for an isolated home, as one JSON file readable only by this
/// user.
public struct FileSecretStore: SecretStoring {
    private struct Storage: Codable {
        var keys: [String: String]
    }

    private let directory: URL
    private let fileName: String

    public init(directory: URL, fileName: String) {
        self.directory = directory
        self.fileName = fileName
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    public func secret(for account: String) throws -> String? {
        try load().keys[account]
    }

    public func containsSecret(for account: String) -> Bool {
        (try? load())?.keys[account] != nil
    }

    /// An emptied file is deleted.
    public func setSecret(_ secret: String?, for account: String) throws {
        var storage = try load()
        storage.keys[account] = secret
        if storage.keys.isEmpty { try remove() } else { try save(storage) }
    }

    private func load() throws -> Storage {
        do {
            return try JSONDecoder().decode(Storage.self, from: Data(contentsOf: fileURL))
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return Storage(keys: [:])
        } catch {
            throw SecretStoreError.storage(path: fileURL.path, reason: "reading failed")
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
            let temporary = staging.appendingPathComponent(fileName)
            try JSONEncoder().encode(storage).write(to: temporary)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            guard rename(temporary.path, fileURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            throw SecretStoreError.storage(path: fileURL.path, reason: error.localizedDescription)
        }
    }

    private func remove() throws {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        } catch {
            throw SecretStoreError.storage(path: fileURL.path, reason: error.localizedDescription)
        }
    }
}
