import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

enum MemeTestImages {
    static func image(width: Int = 120, height: Int = 80) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    static func data(width: Int = 120, height: Int = 80, type: UTType = .png, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try image(width: width, height: height), properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}
