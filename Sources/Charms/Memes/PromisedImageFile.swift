import AppKit

/// Receives one promised file into a private temporary folder and removes
/// that folder once the image is decoded, fails or is cancelled.
struct PromisedImageFile {
    enum Failure: Error, LocalizedError {
        case notDelivered

        var errorDescription: String? {
            "The other app didn’t deliver the image. Save it as a file, then drop that or use Choose Image."
        }
    }

    private static let deliveryTimeout: TimeInterval = 60

    private let directory: URL
    private let deliveries: AsyncThrowingStream<URL, Error>

    init?(receiving receiver: NSFilePromiseReceiver) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Charms-drop-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return nil
        }
        let (deliveries, continuation) = AsyncThrowingStream<URL, Error>.makeStream()
        let queue = OperationQueue()
        receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue) { url, error in
            if error != nil {
                continuation.finish(throwing: Failure.notDelivered)
            } else {
                continuation.yield(url)
                continuation.finish()
            }
        }
        // A source that never writes also never calls back.
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.deliveryTimeout) {
            continuation.finish(throwing: Failure.notDelivered)
        }
        self.directory = directory
        self.deliveries = deliveries
    }

    func image() async throws -> CGImage {
        defer { try? FileManager.default.removeItem(at: directory) }
        for try await url in deliveries {
            return try MemeImageDecoder.decodeFile(at: url)
        }
        try Task.checkCancellation()
        throw Failure.notDelivered
    }
}
