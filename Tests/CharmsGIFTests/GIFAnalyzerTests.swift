import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision
import XCTest
@testable import Charms

final class GIFAnalyzerTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GIFAnalyzerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        super.tearDown()
    }

    // MARK: - Sampling

    func testSamplingSpreadsAcrossPlaybackTime() {
        let delays = [0.01, 0.01, 0.01, 0.01, 1.0, 0.01, 0.01, 0.01]
        let indices = GIFAnalyzer.sampledIndices(frameCount: 8, delays: delays)
        XCTAssertEqual(indices, [0, 4, 7])
    }

    func testSamplingKeepsShortAnimationsWhole() {
        XCTAssertEqual(GIFAnalyzer.sampledIndices(frameCount: 3, delays: [0.1, 0.1, 0.1]), [0, 1, 2])
        XCTAssertEqual(GIFAnalyzer.sampledIndices(frameCount: 1, delays: [0.1]), [0])
        XCTAssertEqual(GIFAnalyzer.sampledIndices(frameCount: 0, delays: []), [])
    }

    func testSamplingFallsBackToEvenSpacingWithoutTiming() {
        XCTAssertEqual(
            GIFAnalyzer.sampledIndices(frameCount: 8, delays: Array(repeating: 0, count: 8)),
            [0, 2, 4, 7]
        )
    }

    // MARK: - Tags

    func testSanitizeNormalizesAndDeduplicates() {
        let input = [" Red ", "RED", "night_sky", "Hello, World!", "  ", "123", "ok"]
        XCTAssertEqual(GIFAnalyzer.sanitize(input), ["red", "night sky", "hello world", "ok"])
    }

    func testSanitizeCapsTheList() {
        let input = (1...20).map { "tag\($0)" }
        XCTAssertEqual(GIFAnalyzer.sanitize(input).count, GIFAnalyzer.maximumTags)
    }

    // MARK: - Decoding

    func testDecodeBoundsFrames() async throws {
        let url = try makeGIF(named: "bounds.gif", count: 6, delays: [0.05, 0.20, 0.10, 0.40, 0.05, 0.20])
        let frames = try await GIFAnalyzer.sampledFrames(at: url)

        XCTAssertEqual(frames.count, GIFAnalyzer.maximumSampledFrames)
        for frame in frames {
            XCTAssertLessThanOrEqual(frame.width, GIFAnalyzer.maximumFrameEdge)
            XCTAssertLessThanOrEqual(frame.height, GIFAnalyzer.maximumFrameEdge)
        }
        // The fixture's frames are solid, distinct colors, so the sampled
        // frames must be distinct too.
        let averages = frames.map(averageColor)
        XCTAssertEqual(Set(averages).count, frames.count)
    }

    // MARK: - Analysis

    func testVisionFallbackReadsText() async throws {
        let url = try makeGIF(named: "text.gif", count: 3, delays: [0.2, 0.2, 0.2], label: "CAT")
        let frames = try await GIFAnalyzer.sampledFrames(at: url)
        try requireSystemOCR(for: XCTUnwrap(frames.first))
        let tags = try await GIFAnalyzer.visionTags(for: frames)
        XCTAssertTrue(tags.contains("cat"), "expected OCR to read CAT, got \(tags)")
    }

    func testTagsForAnimatedFixtureAreBounded() async throws {
        // The drawn word keeps the Vision baseline non-empty even where the
        // Foundation Models path is unavailable.
        let url = try makeGIF(named: "text.gif", count: 3, delays: [0.2, 0.2, 0.2], label: "CAT")
        let tags: [String]
        do {
            tags = try await GIFAnalyzer.tags(for: url)
        } catch GIFAnalyzer.Failure.analysisFailed("inference-unavailable") {
            // A machine with neither inference backend still indexes filenames.
            let frames = try await GIFAnalyzer.sampledFrames(at: url)
            try requireSystemOCR(for: XCTUnwrap(frames.first))
            throw GIFAnalyzer.Failure.analysisFailed("inference-unavailable")
        }

        XCTAssertLessThanOrEqual(tags.count, GIFAnalyzer.maximumTags)
        XCTAssertEqual(tags, GIFAnalyzer.sanitize(tags))
    }

    /// Probe Apple's request directly. A Charms regression still fails on
    /// hosts where Vision can execute the same input.
    private func requireSystemOCR(for frame: CGImage) throws {
        let request = VNRecognizeTextRequest()
        do {
            try VNImageRequestHandler(cgImage: frame).perform([request])
        } catch {
            throw XCTSkip("System OCR unavailable on this host: " + error.localizedDescription)
        }
    }

    // MARK: - Refusals

    func testRefusesNonFileURL() async {
        await assertFailure(URL(string: "https://example.com/animation.gif")!, .notAFileURL)
    }

    func testRefusesMissingFile() async {
        await assertFailure(directory.appendingPathComponent("missing.gif"), .unreadable)
    }

    func testRefusesOversizedFile() async throws {
        let url = directory.appendingPathComponent("oversized.gif")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: UInt64(GIFAnalyzer.maximumFileBytes))
        try handle.write(contentsOf: Data([0]))
        try handle.close()

        await assertFailure(url, .fileTooLarge(limit: GIFAnalyzer.maximumFileBytes,
                                               actual: GIFAnalyzer.maximumFileBytes + 1))
    }

    // MARK: - Helpers

    private func assertFailure(_ url: URL, _ expected: GIFAnalyzer.Failure) async {
        do {
            _ = try await GIFAnalyzer.tags(for: url)
            XCTFail("expected \(expected)")
        } catch let error as GIFAnalyzer.Failure {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    private func makeGIF(
        named name: String,
        count: Int,
        delays: [Double],
        label: String? = nil
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, count, nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for index in 0..<count {
            let image = makeFrame(index: index, count: count, label: label)
            let gif: [CFString: Any] = [
                kCGImagePropertyGIFDelayTime: delays[index],
                kCGImagePropertyGIFUnclampedDelayTime: delays[index]
            ]
            CGImageDestinationAddImage(
                destination, image, [kCGImagePropertyGIFDictionary: gif] as CFDictionary
            )
        }
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private func makeFrame(index: Int, count: Int, label: String?) -> CGImage {
        let size = CGSize(width: 256, height: 256)
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (0, 1, 1), (1, 0, 1)
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let color = colors[index % colors.count]
        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        if let label {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 96, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)
            ]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: label, attributes: attributes)
            )
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: 16, y: 80)
            CTLineDraw(line, context)
        }
        return context.makeImage()!
    }

    private func averageColor(_ image: CGImage) -> String {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var red = 0
        var green = 0
        var blue = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[pixel])
            green += Int(pixels[pixel + 1])
            blue += Int(pixels[pixel + 2])
        }
        let count = width * height
        return "\(red / count),\(green / count),\(blue / count)"
    }
}
