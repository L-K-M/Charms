import CoreGraphics
import CoreML
import Foundation
import ImageIO
import Vision

#if canImport(FoundationModels) && canImport(_Vision_FoundationModels)
import FoundationModels
#endif

/// Tags a GIF from frames sampled across its playback time, without sending
/// anything off the device.
///
/// Work is bounded before any model sees a frame: files larger than
/// `maximumFileBytes` are refused, at most `maximumSampledFrames` frames are
/// decoded, each at most `maximumFrameEdge` pixels on its long edge, and the
/// model is asked for at most `maximumResponseTokens` tokens.
///
/// Vision labels and recognized text remain searchable when an available
/// on-device Foundation Models session adds reaction and action tags.
enum GIFAnalyzer: Sendable {
    enum Method: String, Codable {
        case vision
        case multimodal
    }

    struct Analysis {
        let tags: [String]
        let method: Method
    }

    static var preferredMethod: Method {
        #if canImport(FoundationModels) && canImport(_Vision_FoundationModels)
        if #available(macOS 27, *), SystemLanguageModel.default.isAvailable,
           SystemLanguageModel.default.capabilities.contains(.vision) { return .multimodal }
        #endif
        return .vision
    }

    /// Refuse files above this size before reading them.
    static let maximumFileBytes: Int64 = 64 * 1024 * 1024

    /// Decode at most this many frames, spread across playback time.
    static let maximumSampledFrames = 4

    /// Longest edge of a decoded frame, in pixels.
    static let maximumFrameEdge = 512

    /// Bound the model's answer so a verbose reply cannot dominate indexing.
    static let maximumResponseTokens = 128

    /// Bound the returned tag list.
    static let maximumTags = 8

    enum Failure: Error, Equatable, Sendable {
        case notAFileURL
        case fileTooLarge(limit: Int64, actual: Int64)
        case unreadable
        case noFrames
        case analysisFailed(String)
    }

    /// Returns searchable tags for the GIF at `url`.
    ///
    /// Throws `Failure` when the file cannot be read or no frame can be
    /// decoded, or when neither system inference backend can run.
    static func tags(for url: URL) async throws -> [String] {
        try await analyze(url).tags
    }

    static func analyze(_ url: URL) async throws -> Analysis {
        let frames = try await sampledFrames(at: url)

        try Task.checkCancellation()
        let vision = try? await visionTags(for: frames)
        try Task.checkCancellation()
        var semantic: [String] = []
        #if canImport(FoundationModels) && canImport(_Vision_FoundationModels)
        if #available(macOS 27, *) {
            semantic = (try? await foundationModelTags(for: frames)) ?? []
        }
        #endif
        try Task.checkCancellation()
        guard vision != nil || !semantic.isEmpty else { throw Failure.analysisFailed("inference-unavailable") }
        let baseline = vision ?? []
        return Analysis(tags: sanitize(Array(baseline.prefix(3)) + semantic + baseline),
                        method: semantic.isEmpty ? .vision : .multimodal)
    }

    // MARK: - Foundation Models

    #if canImport(FoundationModels) && canImport(_Vision_FoundationModels)
    @available(macOS 27, *)
    private static func foundationModelTags(for frames: [CGImage]) async throws -> [String] {
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else {
            throw Failure.analysisFailed("system-model-unavailable")
        }
        guard model.capabilities.contains(.vision) else {
            throw Failure.analysisFailed("system-model-without-vision")
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You tag animated GIFs for local search. Describe only what is \
            visible in the frames: the subject, the action and the reaction. \
            Reply with a JSON array of at most \(maximumTags) short lowercase \
            tags and nothing else.
            """
        )
        let prompt = Prompt {
            "Sampled frames of one animated GIF, in playback order."
            for frame in frames {
                Attachment(frame)
            }
        }
        let response = try await session.respond(
            to: prompt,
            generating: [String].self,
            options: GenerationOptions(maximumResponseTokens: maximumResponseTokens)
        )
        return sanitize(response.content)
    }
    #endif

    // MARK: - Vision baseline

    static func visionTags(for frames: [CGImage]) async throws -> [String] {
        var captions: [String] = []
        var labels: [String] = []
        var ranVision = false
        for frame in frames {
            try Task.checkCancellation()
            let handler = VNImageRequestHandler(cgImage: frame, options: [:])
            let classify = VNClassifyImageRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            // The classifier and OCR can have different hardware support.
            // A classifier failure must not discard a readable caption.
            for request in [classify as VNRequest, text] {
                if perform(request, with: handler) { ranVision = true }
            }
            for observation in (classify.results ?? []).prefix(5) where observation.confidence >= 0.5 {
                labels.append(observation.identifier)
            }
            for observation in (text.results ?? []).prefix(2) {
                if let caption = observation.topCandidates(1).first {
                    let words = caption.string.split { !$0.isLetter && !$0.isNumber }
                    captions.append(words.joined(separator: " "))
                }
            }
        }
        guard ranVision else { throw Failure.analysisFailed("vision-unavailable") }
        return sanitize(captions + labels)
    }

    private static func perform(_ request: VNRequest, with handler: VNImageRequestHandler) -> Bool {
        do {
            try handler.perform([request])
            return true
        } catch {
            // Virtual Macs may expose CPU compute without a usable GPU.
            guard let stages = try? request.supportedComputeStageDevices else { return false }
            for (stage, devices) in stages {
                for case let .cpu(cpu) in devices {
                    request.setComputeDevice(.cpu(cpu), for: stage)
                    break
                }
            }
            return (try? handler.perform([request])) != nil
        }
    }

    // MARK: - Decoding

    static func sampledFrames(at url: URL) async throws -> [CGImage] {
        try Task.checkCancellation()
        return try decodeSampledFrames(at: url)
    }

    private static func decodeSampledFrames(at url: URL) throws -> [CGImage] {
        guard url.isFileURL else { throw Failure.notAFileURL }

        guard let snapshot = GIFFileSnapshot.inspect(url) else { throw Failure.unreadable }
        let data = try snapshot.read(url)

        // Image I/O may composite the full canvas even for a thumbnail.
        guard data.count >= 10, data.starts(with: Data("GIF8".utf8)) else { throw Failure.unreadable }
        let width = Int(data[6]) + Int(data[7]) * 256
        let height = Int(data[8]) + Int(data[9]) * 256
        guard (1...4096).contains(width), (1...4096).contains(height) else { throw Failure.unreadable }
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw Failure.unreadable
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw Failure.noFrames }

        guard count <= 1500 else { throw Failure.unreadable }
        let delays = frameDelays(source: source, count: count)
        let indices = sampledIndices(frameCount: count, delays: delays)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumFrameEdge
        ]
        let frames = try indices.compactMap { index in
            try Task.checkCancellation()
            return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
        }
        guard !frames.isEmpty else { throw Failure.noFrames }
        return frames
    }

    /// Per-frame playback delays, falling back to the usual 100 ms when the
    /// file does not say. `DelayTime` is the clamped value ImageIO reports,
    /// which is what a browser plays.
    private static func frameDelays(source: CGImageSource, count: Int) -> [TimeInterval] {
        (0..<count).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFDelayTime] as? TimeInterval
                ?? gif?[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
            guard let delay, delay.isFinite, delay >= 0 else { return 0.1 }
            return delay
        }
    }

    /// Indices spread across playback time, including both ends. When the
    /// timing is unknown the indices are spread evenly across the file.
    static func sampledIndices(frameCount: Int, delays: [TimeInterval]) -> [Int] {
        guard frameCount > 0 else { return [] }
        if frameCount <= maximumSampledFrames {
            return Array(0..<frameCount)
        }

        let timing = delays.prefix(frameCount)
        let total = timing.reduce(0, +)
        guard total > 0 else {
            return (0..<maximumSampledFrames).map { sample in
                (sample * (frameCount - 1)) / (maximumSampledFrames - 1)
            }
        }

        var cumulative: [TimeInterval] = []
        cumulative.reserveCapacity(frameCount)
        var sum: TimeInterval = 0
        for delay in timing {
            sum += delay
            cumulative.append(sum)
        }

        var indices: [Int] = []
        for sample in 0..<maximumSampledFrames {
            let target = total * Double(sample) / Double(maximumSampledFrames - 1)
            let index = cumulative.firstIndex(where: { $0 > target }) ?? (frameCount - 1)
            if indices.last != index {
                indices.append(index)
            }
        }
        return indices
    }

    // MARK: - Tags

    /// Lowercases, splits underscores, drops punctuation and duplicates, and
    /// caps the list. Vision identifiers arrive as `night_sky`; model output
    /// may arrive as prose or a quoted list.
    static func sanitize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var clean: [String] = []
        for tag in tags {
            let words = tag
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .reduce(into: "") { kept, character in
                    if character.isLetter || character.isNumber || character.isWhitespace {
                        kept.append(character)
                    }
                }
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard words.contains(where: { $0.isLetter }), words.count <= 40 else { continue }
            guard seen.insert(words).inserted else { continue }
            clean.append(words)
            if clean.count == maximumTags { break }
        }
        return clean
    }
}
