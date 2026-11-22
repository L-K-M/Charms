import AppKit

/// The composer's root view. It accepts images anywhere in the window;
/// SwiftUI's drop handlers do not receive file promises.
final class MemeDropView: NSView {
    var canAccept: () -> Bool = { false }
    var onTargeted: (Bool) -> Void = { _ in }
    var onDrop: (MemeImageSource) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let promises = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        let images = NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes([.fileURL] + images + promises)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(), MemeImageSource.isOffered(on: sender.draggingPasteboard) else { return [] }
        let offered = sender.draggingSourceOperationMask
        if offered.contains(.copy) { return .copy }
        return offered.contains(.generic) ? .generic : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = operation(for: sender)
        onTargeted(!operation.isEmpty)
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargeted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargeted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargeted(false)
        guard canAccept(), let source = MemeImageSource(receivingFrom: sender.draggingPasteboard) else { return false }
        onDrop(source)
        return true
    }
}
