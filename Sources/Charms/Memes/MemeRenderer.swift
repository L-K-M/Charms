import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

enum MemeRenderer {
    enum Failure: Error { case invalidCaption, renderFailed, encodingFailed }

    static func render(artwork: CGImage, caption: String) throws -> CGImage {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= MemeCaptioner.maximumCaptionCharacters else { throw Failure.invalidCaption }
        let scale = min(1, 1600 / CGFloat(max(artwork.width, artwork.height)))
        let artWidth = max(1, Int((CGFloat(artwork.width) * scale).rounded()))
        let artHeight = max(1, Int((CGFloat(artwork.height) * scale).rounded()))
        let width = max(480, artWidth)
        let inset = ceil(CGFloat(width) * 0.035)
        let textWidth = CGFloat(width) - 2 * inset
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let font = NSFont.systemFont(ofSize: CGFloat(width) * 0.048, weight: .bold)
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.white, .paragraphStyle: style
        ])
        let setter = CTFramesetterCreateWithAttributedString(string)
        let range = CFRange(location: 0, length: string.length)
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, range, nil, CGSize(width: textWidth, height: .greatestFiniteMagnitude), nil
        )
        // Explicit newlines can make even a short caption many screens tall.
        guard measured.height <= CGFloat(width) else { throw Failure.invalidCaption }
        let textHeight = ceil(measured.height) + 2
        let bandHeight = Int(textHeight + 2 * inset)
        guard let context = CGContext(data: nil, width: width, height: artHeight + bandHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.renderFailed }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: artHeight + bandHeight))
        context.interpolationQuality = .high
        context.draw(artwork, in: CGRect(x: (width - artWidth) / 2, y: bandHeight, width: artWidth, height: artHeight))
        let rect = CGRect(x: inset, y: inset, width: textWidth, height: textHeight)
        let frame = CTFramesetterCreateFrame(setter, range, CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, context)
        guard let image = context.makeImage() else { throw Failure.renderFailed }
        return image
    }

    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.encodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return data as Data
    }
}
