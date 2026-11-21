import CoreServices
import Foundation

/// FSEvents also reports writes made inside an existing file. A directory
/// vnode alone would only reliably notice additions, renames and removals.
final class GIFFolderObserver {
    private let stream: FSEventStreamRef
    private let directory: DispatchSourceFileSystemObject

    private final class Handler {
        let change: () -> Void
        let root: String
        init(folder: URL, change: @escaping () -> Void) {
            root = folder.standardizedFileURL.path
            self.change = change
        }
    }

    init?(folder: URL, change: @escaping () -> Void) {
        let handler = Handler(folder: folder, change: change)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: { _ = Unmanaged<Handler>.fromOpaque($0!).retain(); return $0 },
            release: { Unmanaged<Handler>.fromOpaque($0!).release() }, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, { _, context, count, paths, flags, _ in
            guard let context else { return }
            let handler = Unmanaged<Handler>.fromOpaque(context).takeUnretainedValue()
            let names = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            for i in 0..<count {
                let url = URL(fileURLWithPath: String(cString: names[i]))
                if flags[i] & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 ||
                    url.path == handler.root ||
                    (url.pathExtension.lowercased() == "gif" && url.deletingLastPathComponent().path == handler.root) {
                    handler.change()
                    break
                }
            }
        }, &context, [handler.root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags)
        else { return nil }
        // Some volumes and temporary folders omit events from the journal.
        // Direct directory notifications still cover drops and atomic saves.
        let fd = open(folder.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { FSEventStreamRelease(stream); return nil }
        directory = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
            eventMask: [.write, .delete, .rename], queue: .main)
        directory.setEventHandler(handler: change)
        directory.setCancelHandler { close(fd) }
        directory.resume()
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else { return nil }
    }

    deinit {
        directory.cancel()
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
