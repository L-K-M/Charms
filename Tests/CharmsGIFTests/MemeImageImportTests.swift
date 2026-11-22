import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Charms

final class MemeImageImportTests: XCTestCase {
    private var directory: URL!
    private var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CharmsMemeImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    func testDroppedFileIsDecodedAndLeftExactlyWhereItWas() async throws {
        let bytes = try MemeTestImages.data()
        let url = directory.appendingPathComponent("Draw Things output.png")
        try bytes.write(to: url)
        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))

        XCTAssertTrue(MemeImageSource.isOffered(on: pasteboard))
        let source = try XCTUnwrap(MemeImageSource(receivingFrom: pasteboard))
        let image = try await source.image()
        XCTAssertEqual([image.width, image.height], [120, 80])
        XCTAssertEqual(try Data(contentsOf: url), bytes, "a person's own file is never consumed")
    }

    func testRawImageDataIsAccepted() async throws {
        for type in [UTType.png, .jpeg, .tiff] {
            pasteboard.clearContents()
            pasteboard.setData(try MemeTestImages.data(type: type), forType: .init(type.identifier))
            XCTAssertTrue(MemeImageSource.isOffered(on: pasteboard), type.identifier)
            let source = try XCTUnwrap(MemeImageSource(receivingFrom: pasteboard))
            let image = try await source.image()
            XCTAssertEqual(image.width, 120)
        }
    }

    func testWebAddressesAndTextAreNeverImageSources() {
        pasteboard.writeObjects([NSURL(string: "https://example.com/cat.png")!])
        XCTAssertFalse(MemeImageSource.isOffered(on: pasteboard))
        XCTAssertNil(MemeImageSource(receivingFrom: pasteboard))

        pasteboard.clearContents()
        pasteboard.setString("https://example.com/cat.png", forType: .string)
        XCTAssertFalse(MemeImageSource.isOffered(on: pasteboard))
        XCTAssertNil(MemeImageSource(receivingFrom: pasteboard))
    }

    func testAnotherKindOfFileIsRefusedEvenBesideImageData() throws {
        let url = directory.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: url)
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(try MemeTestImages.data(), forType: .png)
        pasteboard.writeObjects([item])
        XCTAssertFalse(MemeImageSource.isOffered(on: pasteboard), "the picture would be the file's icon")
        XCTAssertNil(MemeImageSource(receivingFrom: pasteboard))
    }

    func testLargeArtworkIsScaledAndSmallArtworkIsNotEnlarged() throws {
        let large = try MemeImageDecoder.decode(MemeTestImages.data(width: 3200, height: 800))
        XCTAssertEqual([large.width, large.height], [1600, 400])
        let small = try MemeImageDecoder.decode(MemeTestImages.data(width: 64, height: 32))
        XCTAssertEqual([small.width, small.height], [64, 32])
    }

    func testOrientationIsApplied() throws {
        let sideways = try MemeTestImages.data(type: .jpeg, properties: [kCGImagePropertyOrientation: 6])
        let image = try MemeImageDecoder.decode(sideways)
        XCTAssertEqual([image.width, image.height], [80, 120])
    }

    func testACanvasOverThePixelLimitIsRefused() throws {
        // ImageIO rejects a forged huge header itself, and a real 100-megapixel
        // fixture is too costly, so the limit is lowered around a real image.
        let data = try MemeTestImages.data(width: 120, height: 80)
        XCTAssertNoThrow(try MemeImageDecoder.decode(data, pixelLimit: 9600))
        XCTAssertThrowsError(try MemeImageDecoder.decode(data, pixelLimit: 9599)) {
            XCTAssertEqual($0 as? MemeImageDecoder.Failure, .tooManyPixels)
        }
    }

    func testUnreadableAndOversizedFilesAreRefusedAndKept() throws {
        let text = directory.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: text)
        XCTAssertThrowsError(try MemeImageDecoder.decodeFile(at: text)) {
            XCTAssertEqual($0 as? MemeImageDecoder.Failure, .unreadable)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: text.path))

        let large = directory.appendingPathComponent("large.png")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(MemeImageDecoder.maximumFileBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try MemeImageDecoder.decodeFile(at: large)) {
            XCTAssertEqual($0 as? MemeImageDecoder.Failure, .tooManyBytes)
        }
    }

    func testAPipeCannotHangTheReader() {
        let pipe = directory.appendingPathComponent("pipe.png")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try MemeImageDecoder.decodeFile(at: pipe)) {
            XCTAssertEqual($0 as? MemeImageDecoder.Failure, .unreadable)
        }
    }
}
