import AppKit
import CharmsCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum PickerSource: String, CaseIterable {
    case characters = "Characters"
    case local = "My GIFs"
    case online = "Online GIFs"

    var prompt: String {
        switch self {
        case .characters: return "Find symbols, emoji, snippets…"
        case .local: return "Find GIFs by filename or tag…"
        case .online: return "Search the online GIF provider…"
        }
    }
}

struct GIFRow: Identifiable {
    let id: URL
    let preview: URL
    let title: String
    let detail: String
    // File changes must invalidate a preview even when its URL stays the same.
    let revision: GIFFileSnapshot?
}

struct GIFPickerView: View {
    @ObservedObject var model: PickerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pickerPalette) private var palette
    @State private var image: NSImage?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            if let row = model.selectedGIF {
                GIFPreview(image: image, animate: !reduceMotion)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(row.title)
                    .overlay {
                        if loading {
                            ProgressView().controlSize(.small)
                        } else if image == nil {
                            Text("Preview unavailable").font(.caption)
                        }
                    }
                    .task(id: row.revision) {
                        loading = true
                        image = nil
                        let data = await model.loadPreview?(row)
                        guard !Task.isCancelled else { return }
                        image = data.flatMap(Self.previewImage)
                        loading = false
                    }
                    .id(row.id)
                    .frame(height: PickerViewModel.proofHeight)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if let status = model.gifStatus {
                            Text(status).font(.callout).padding(8)
                        }
                        ForEach(model.gifRows) { row in
                            Button {
                                model.selectedGIFID = row.id
                                model.onActivateGIF?()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title).lineLimit(1)
                                    if !row.detail.isEmpty {
                                        Text(row.detail).font(.caption).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(model.selectedGIFID == row.id ? palette.paper : .clear)
                            .foregroundStyle(model.selectedGIFID == row.id ? palette.ink : palette.chalk)
                            .accessibilityAddTraits(model.selectedGIFID == row.id ? .isSelected : [])
                            .id(row.id)
                        }
                        if model.hasMoreGIFs {
                            Button("More Results") { model.onMoreGIFs?() }
                                .padding(7)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: model.selectedGIFID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            HStack {
                Button {
                    model.onActivateGIF?()
                } label: {
                    Label(model.source == .local ? "Copy GIF" : model.canInsert ? "Insert link" : "Copy link",
                          systemImage: "return")
                }
                .disabled(model.selectedGIF == nil || (model.selectedGIF?.revision?.size ?? 0) > GIFAnalyzer.maximumFileBytes)
                Spacer()
                if model.source == .online { Text(model.attribution).font(.caption) }
            }
            .padding(.horizontal, 19)
            .frame(height: PickerViewModel.footerHeight)
        }
        .foregroundStyle(palette.chalk)
        .background(palette.tray)
    }

    /// AppKit can expand every bitmap in an animation. Check the dimensions
    /// and total pixel budget before handing it provider or local file bytes.
    private static func previewImage(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) == UTType.gif.identifier as CFString?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard (1...400).contains(count) else { return nil }
        if width * height <= 16_000_000 / count {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 512]
        guard let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: frame, size: .zero)
    }
}

private struct GIFPreview: NSViewRepresentable {
    let image: NSImage?
    let animate: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
        view.animates = animate
    }
}
