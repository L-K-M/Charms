import AppKit
import ImageIO
import XCTest
@testable import Charms

final class MemeRendererTests: XCTestCase {
    func testPNGPreservesArtworkOrientationAndAddsVisibleCaptionBelow() throws {
        let width = 480, height = 160
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let source = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        source.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        source.fill(CGRect(x: 0, y: 0, width: width, height: height))
        source.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        source.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        let artwork = try XCTUnwrap(source.makeImage())
        let rendered = try MemeRenderer.render(artwork: artwork, caption: "My weekend plans")
        let data = try MemeRenderer.png(rendered)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(image.width, width)
        XCTAssertGreaterThan(image.height, height)
        let bitmap = NSBitmapImageRep(cgImage: image)
        func rgb(_ x: Int, _ y: Int) throws -> NSColor {
            try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        }
        XCTAssertGreaterThan(try rgb(0, 0).redComponent, 0.95)
        XCTAssertGreaterThan(try rgb(0, height - 1).blueComponent, 0.95)
        XCTAssertLessThan(try rgb(0, height).redComponent, 0.05)
        var hasWhiteText = false
        for y in height..<image.height {
            if try (0..<width).contains(where: { try rgb($0, y).greenComponent > 0.85 }) {
                hasWhiteText = true
                break
            }
        }
        XCTAssertTrue(hasWhiteText)
    }
}
