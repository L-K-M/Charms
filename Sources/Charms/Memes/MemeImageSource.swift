import AppKit
import UniformTypeIdentifiers

/// An image handed to the composer: a local file, image data, or a file
/// another app promises to write. A web address is never an image source,
/// so a drop cannot make Charms contact a server.
enum MemeImageSource {
    case file(URL)
    case data(Data)
    case promise(PromisedImageFile)

    static func isOffered(on pasteboard: NSPasteboard) -> Bool {
        if hasFileURL(on: pasteboard) { return imageFileURL(on: pasteboard) != nil }
        return imageDataType(on: pasteboard) != nil || imagePromise(on: pasteboard) != nil
    }

    /// Call this while the drop is performed: a promise must be accepted
    /// before the dragging session ends.
    init?(receivingFrom pasteboard: NSPasteboard) {
        if Self.hasFileURL(on: pasteboard) {
            guard let url = Self.imageFileURL(on: pasteboard) else { return nil }
            self = .file(url)
        } else if let type = Self.imageDataType(on: pasteboard), let data = pasteboard.data(forType: type), !data.isEmpty {
            self = .data(data)
        } else if let receiver = Self.imagePromise(on: pasteboard) {
            guard let file = PromisedImageFile(receiving: receiver) else { return nil }
            self = .promise(file)
        } else {
            return nil
        }
    }

    /// Not isolated to an actor, so decoding stays off the main thread.
    func image() async throws -> CGImage {
        switch self {
        case .file(let url): return try MemeImageDecoder.decodeFile(at: url)
        case .data(let data): return try MemeImageDecoder.decode(data)
        case .promise(let file): return try await file.image()
        }
    }

    private static func hasFileURL(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private static func imageFileURL(on pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        guard let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first,
              url.isFileURL else { return nil }
        return url
    }

    private static func imageDataType(on pasteboard: NSPasteboard) -> NSPasteboard.PasteboardType? {
        let types = pasteboard.types ?? []
        // Sources often add a TIFF conversion beside the original PNG.
        if types.contains(.png) { return .png }
        return types.first { UTType($0.rawValue)?.conforms(to: .image) == true }
    }

    private static func imagePromise(on pasteboard: NSPasteboard) -> NSFilePromiseReceiver? {
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]
        return receivers?.first { receiver in
            receiver.fileTypes.contains { name in
                (UTType(name) ?? UTType(filenameExtension: name))?.conforms(to: .image) == true
            }
        }
    }
}
