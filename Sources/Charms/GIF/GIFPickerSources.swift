import CharmsCore
import Combine
import Foundation

/// A GIF session has its own query. Opening online search always starts with
/// a blank field, so an existing local query cannot be sent to a provider.
@MainActor
final class GIFPickerSources {
    private let library: LocalGIFLibrary
    private let online: OnlineGIFSearch
    private let model: PickerViewModel
    private var query = ""
    private var observations = Set<AnyCancellable>()

    init(services: AppServices, model: PickerViewModel) {
        self.model = model
        library = services.localGIFs
        online = services.onlineGIFs
        library.objectWillChange.merge(with: online.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &observations)
        model.onMoreGIFs = { [weak online] in online?.loadMore() }
        model.loadPreview = { [weak self] row in
            guard let self else { return nil }
            switch self.model.source {
            case .characters: return nil
            case .local: return try? await row.revision?.data(at: row.id)
            case .online: return await self.online.previewData(for: row.preview)
            }
        }
    }

    func reset(to source: PickerSource) {
        model.source = source
        if source == .local { library.refresh() }
        online.cancel()
        query = ""
        model.gifRows = []
        model.selectedGIFID = nil
        refresh()
    }

    func updateQuery(_ text: String) {
        guard text != query else { return }
        query = text
        model.selectedGIFID = nil
        if model.source == .online {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                online.cancel()
            } else {
                online.search(text)
            }
        }
        refresh()
    }

    private func refresh() {
        let rows: [GIFRow]
        switch model.source {
        case .characters: return
        case .local:
            model.hasMoreGIFs = false
            let words = query.split(whereSeparator: \.isWhitespace)
            rows = library.entries.compactMap { entry in
                let title = entry.url.lastPathComponent
                let detail = entry.tags.joined(separator: ", ")
                let searchable = title + " " + detail
                guard words.allSatisfy({ searchable.localizedStandardContains(String($0)) }) else { return nil }
                let description = entry.revision.size > GIFAnalyzer.maximumFileBytes
                    ? "Exceeds the 64 MiB preview and copy limit" : detail
                return GIFRow(id: entry.url, preview: entry.url, title: title, detail: description,
                              revision: entry.revision)
            }
            model.gifStatus = library.status ?? (rows.isEmpty ? (library.folder == nil
                ? "Choose a folder in Settings → GIFs." : "No matching GIFs.") : nil)
        case .online:
            var seen = Set<URL>()
            rows = online.items.compactMap { item in
                guard seen.insert(item.message.url).inserted else { return nil }
                return GIFRow(id: item.message.url, preview: item.preview.url,
                              title: item.title.isEmpty ? "GIF" : item.title, detail: "",
                              revision: nil)
            }
            model.hasMoreGIFs = online.nextPage != nil
            model.attribution = online.attribution
            model.gifStatus = online.status ?? (rows.isEmpty ? (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Type to search online." : "No matching GIFs.") : nil)
        }
        model.gifRows = rows
        if !rows.contains(where: { $0.id == model.selectedGIFID }) {
            model.selectedGIFID = rows.first?.id
        }
    }

    func move(by offset: Int) {
        let rows = model.gifRows
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == model.selectedGIFID } ?? 0
        model.selectedGIFID = rows[max(0, min(current + offset, rows.count - 1))].id
    }
}
