import AppKit

/// Accepts images anywhere in the composer. SwiftUI's drop handlers do not
/// receive file promises.
///
/// It lies above the editor. Measured on macOS 27.0.1: beneath it, a focused
/// text field took a dropped file as its path, and the scene description is
/// what Generate sends. Clicks pass through, and so do drags of plain text.
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

    /// A view with `content` filling it and this view on top.
    func covering(_ content: NSView, size: NSSize) -> NSView {
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        for view in [content, self] {
            view.frame = root.bounds
            view.autoresizingMask = [.width, .height]
            root.addSubview(view)
        }
        return root
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
