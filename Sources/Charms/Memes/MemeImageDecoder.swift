import Darwin
import Foundation
import ImageIO

/// Turns untrusted image bytes into bounded, orientation-corrected artwork.
enum MemeImageDecoder {
    static let maximumFileBytes = 64 * 1024 * 1024
    /// A small file can declare an enormous canvas, so this is checked
    /// before anything is decoded.
    static let maximumPixels = 100_000_000
    static let maximumDimension = 1600

    enum Failure: Error, LocalizedError, Equatable {
        case unreadable, tooManyBytes, tooManyPixels

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Charms couldn’t read that image. Try a PNG or JPEG."
            case .tooManyBytes: return "That file is larger than 64 MB. Choose a smaller image."
            case .tooManyPixels: return "That image is larger than 100 megapixels. Choose a smaller one."
            }
        }
    }

    static func decode(_ data: Data, pixelLimit: Int = maximumPixels) throws -> CGImage {
        guard data.count <= maximumFileBytes else { throw Failure.tooManyBytes }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw Failure.unreadable }
        guard width <= pixelLimit / height else { throw Failure.tooManyPixels }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension
        ] as CFDictionary) else { throw Failure.unreadable }
        return image
    }

    /// Reads the file without changing it.
    static func decodeFile(at url: URL) throws -> CGImage {
        guard url.isFileURL else { throw Failure.unreadable }
        // Non-blocking, so a pipe in place of a file cannot hang the read.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.unreadable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw Failure.unreadable }
        guard info.st_size <= maximumFileBytes else { throw Failure.tooManyBytes }
        guard let data = try handle.read(upToCount: maximumFileBytes + 1) else { throw Failure.unreadable }
        return try decode(data)
    }
}
