import Foundation

/// Reads and writes the user's saved snippets as `snippets.json` in a directory.
///
/// Loading is strict: a missing file returns nil, while unreadable, non-regular,
/// malformed, invalid, duplicate and newer-schema files all throw and are left
/// byte-for-byte untouched so the app can present a read-only retry. Saving
/// never seeds defaults: an intentionally empty library stays empty, and the
/// app owns first-run seeding.
///
/// This store is not thread-safe. Call `load()` and `save(_:)` from one serial
/// context; the app calls them from the main actor, and a concurrent save would
/// race on the destination.
public final class SnippetStore {
    /// File name inside the directory.
    static let fileName = "snippets.json"
    /// Reads are capped at 1 MiB so an oversized file is rejected before parsing.
    static let maximumFileSize = 1 << 20

    /// Errors thrown by `load()` and `save(_:)`. No case includes file content.
    public enum SnippetStoreError: Error, Equatable, CustomStringConvertible {
        case unreadable(path: String, reason: String)
        case notRegularFile(path: String)
        case oversized(path: String, size: Int64)
        case malformedJSON
        case unsupportedSchema
        case invalidLibrary
        case directoryCreationFailed(path: String, reason: String)
        case writeFailed(path: String, reason: String)
        case replaceFailed(path: String, reason: String)

        public var description: String {
            switch self {
            case .unreadable(let path, let reason):
                return "could not read \(path): \(reason)"
            case .notRegularFile(let path):
                return "\(path) is not a regular file"
            case .oversized(let path, let size):
                return "\(path) is \(size) bytes, which exceeds the 1 MiB limit"
            case .malformedJSON:
                return "snippets.json is not valid JSON"
            case .unsupportedSchema:
                return "snippets.json uses a schema this version cannot read"
            case .invalidLibrary:
                return "snippets.json contains an invalid snippet library"
            case .directoryCreationFailed(let path, let reason):
                return "could not create \(path): \(reason)"
            case .writeFailed(let path, let reason):
                return "could not write \(path): \(reason)"
            case .replaceFailed(let path, let reason):
                return "could not replace \(path): \(reason)"
            }
        }
    }

    private let directory: URL
    private let fileManager: FileManager
    private let fileURL: URL

    /// - Parameters:
    ///   - directory: Directory that contains `snippets.json`. Created on the
    ///     first save.
    ///   - fileManager: File manager used for every disk operation.
    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.fileURL = directory.appendingPathComponent(Self.fileName)
    }

    // MARK: - Loading

    /// Returns the saved library, or nil only when `snippets.json` is missing.
    ///
    /// The file is bounded to 1 MiB before it is read, and is never modified by
    /// loading.
    public func load() throws -> SnippetLibrary? {
        // Inspect the path directly rather than asking fileExists first: a file
        // behind an unreadable directory must throw, not look missing.
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        } catch let error as NSError {
            if Self.isMissingFileError(error) { return nil }
            throw SnippetStoreError.unreadable(path: fileURL.path, reason: error.localizedDescription)
        }

        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw SnippetStoreError.notRegularFile(path: fileURL.path)
        }

        if let size = (attributes[.size] as? NSNumber)?.int64Value,
           size > Self.maximumFileSize {
            throw SnippetStoreError.oversized(path: fileURL.path, size: size)
        }

        let data = try readBoundedData()

        do {
            return try JSONDecoder().decode(SnippetLibrary.self, from: data)
        } catch let error as SnippetError {
            // SnippetError cases carry no file content, so reporting the
            // distinction stays free of payload.
            switch error {
            case .unsupportedSchema: throw SnippetStoreError.unsupportedSchema
            default: throw SnippetStoreError.invalidLibrary
            }
        } catch {
            throw SnippetStoreError.malformedJSON
        }
    }

    // MARK: - Saving

    /// Writes the library as sorted, pretty-printed JSON, atomically replacing
    /// `snippets.json`.
    ///
    /// The JSON goes to a unique temporary file in the same directory with
    /// permissions 0600, then replaces the destination with new metadata. The
    /// temporary file is removed on every exit, including failures, so a failed
    /// save leaves the previous file intact and no debris behind.
    public func save(_ library: SnippetLibrary) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data: Data
        do {
            data = try encoder.encode(library)
        } catch {
            throw SnippetStoreError.writeFailed(path: fileURL.path, reason: error.localizedDescription)
        }

        do {
            try fileManager.createDirectory(at: directory,
                                            withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
        } catch {
            throw SnippetStoreError.directoryCreationFailed(path: directory.path,
                                                            reason: error.localizedDescription)
        }

        let temporaryURL = uniqueTemporaryURL()
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard !fileManager.fileExists(atPath: temporaryURL.path),
              fileManager.createFile(atPath: temporaryURL.path,
                                     contents: data,
                                     attributes: [.posixPermissions: 0o600]) else {
            throw SnippetStoreError.writeFailed(path: temporaryURL.path,
                                                reason: "could not create the temporary file")
        }

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                // Never replace a non-file: a failed save must not destroy a
                // directory that happens to sit at the destination.
                let destinationType = (try? fileManager.attributesOfItem(atPath: fileURL.path))?[.type]
                guard destinationType as? FileAttributeType == .typeRegular else {
                    throw SnippetStoreError.replaceFailed(path: fileURL.path,
                                                          reason: "destination is not a regular file")
                }
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL,
                                                   backupItemName: nil,
                                                   options: [.usingNewMetadataOnly])
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch let error as SnippetStoreError {
            throw error
        } catch {
            throw SnippetStoreError.replaceFailed(path: fileURL.path, reason: error.localizedDescription)
        }
    }

    // MARK: - Private

    /// True only for the Cocoa/POSIX errors that mean there is no file at the
    /// path. Permission, type and malformed-path errors are unreadable instead.
    private static func isMissingFileError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) { return true }
        return false
    }

    /// Reads at most `maximumFileSize` bytes, refusing to slurp a file that
    /// grew past the bound after the size check.
    private func readBoundedData() throws -> Data {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw SnippetStoreError.unreadable(path: fileURL.path, reason: error.localizedDescription)
        }
        defer { try? handle.close() }

        var data = Data()
        while true {
            let remaining = Self.maximumFileSize + 1 - data.count
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: remaining) ?? Data()
            } catch {
                throw SnippetStoreError.unreadable(path: fileURL.path, reason: error.localizedDescription)
            }
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > Self.maximumFileSize {
                throw SnippetStoreError.oversized(path: fileURL.path, size: Int64(data.count))
            }
        }
        return data
    }

    /// A temporary path in the destination directory that does not exist yet.
    private func uniqueTemporaryURL() -> URL {
        while true {
            let candidate = directory
                .appendingPathComponent("\(Self.fileName).\(UUID().uuidString).tmp")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
    }
}
