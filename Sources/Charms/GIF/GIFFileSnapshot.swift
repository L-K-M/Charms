import Darwin
import Foundation

/// A watched folder may be changing while the picker is reading it. A
/// regular-file descriptor and two matching stamps tie bytes to one revision.
struct GIFFileSnapshot: Codable, Equatable, Sendable, Hashable {
    let inode: UInt64
    let size: Int64
    let seconds: Int
    let nanoseconds: Int

    private init(_ info: stat) {
        inode = UInt64(info.st_ino)
        size = info.st_size
        seconds = info.st_mtimespec.tv_sec
        nanoseconds = info.st_mtimespec.tv_nsec
    }

    static func inspect(_ url: URL) -> Self? {
        var info = stat()
        guard url.isFileURL, lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return Self(info)
    }

    func data(at url: URL) async throws -> Data {
        try read(url)
    }

    func read(_ url: URL) throws -> Data {
        guard size <= GIFAnalyzer.maximumFileBytes else {
            throw GIFAnalyzer.Failure.fileTooLarge(limit: GIFAnalyzer.maximumFileBytes, actual: size)
        }
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw GIFAnalyzer.Failure.unreadable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              self == Self(info) else { throw GIFAnalyzer.Failure.unreadable }
        guard let data = try handle.read(upToCount: Int(size) + 1), data.count == Int(size),
              data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)),
              fstat(fd, &info) == 0, self == Self(info), Self.inspect(url) == self else {
            throw GIFAnalyzer.Failure.unreadable
        }
        return data
    }
}
