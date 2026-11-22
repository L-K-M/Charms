import AppKit
import XCTest
@testable import Charms

@MainActor
final class MemeDropViewTests: XCTestCase {
    /// A text field under the pointer would take a dropped file as its path,
    /// which Generate would then send.
    func testDropsAreCaughtAboveTheEditorWithoutBlockingClicks() {
        let editor = NSView()
        let drop = MemeDropView(frame: .zero)
        let root = drop.covering(editor, size: NSSize(width: 300, height: 200))

        XCTAssertTrue(root.subviews.last === drop, "the drop target is above every field")
        XCTAssertNil(drop.hitTest(NSPoint(x: 10, y: 10)))
        XCTAssertTrue(root.hitTest(NSPoint(x: 10, y: 10)) === editor)
        XCTAssertTrue(drop.registeredDraggedTypes.contains(.fileURL))
        XCTAssertFalse(drop.registeredDraggedTypes.contains(.string), "text can still be dragged into the fields")
    }
}
