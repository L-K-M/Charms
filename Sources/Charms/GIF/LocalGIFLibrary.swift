import Combine
import Foundation

struct LocalGIFEntry: Codable, Equatable, Sendable {
    let url: URL
    let revision: GIFFileSnapshot
    var generatedTags: [String] = []
    var userTags: [String]?
    var method: GIFAnalyzer.Method?
    var tags: [String] { userTags ?? generatedTags }
}

/// The scan publishes filenames first. One worker then tags unchanged
/// snapshots, merging its answer with any edits made while it was suspended.
@MainActor
final class LocalGIFLibrary: ObservableObject {
    @Published private(set) var folder: URL?
    @Published private(set) var entries: [LocalGIFEntry] = []
    @Published private(set) var status: String?
    private let index: URL
    private let analyze: (URL) async throws -> GIFAnalyzer.Analysis
    private var observer: GIFFolderObserver?
    private var scan: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var failed: Set<GIFFileSnapshot> = []
    private var modelDeferred: Set<GIFFileSnapshot> = []
    private var cached: [LocalGIFEntry] = []
    private var loadFailed = false

    private struct Archive: Codable {
        let folder: URL?
        let entries: [LocalGIFEntry]
    }

    init(supportDirectory: URL, analyze: @escaping (URL) async throws -> GIFAnalyzer.Analysis = GIFAnalyzer.analyze) {
        index = supportDirectory.appendingPathComponent("gif-library.json")
        self.analyze = analyze
        do {
            let saved = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: index))
            folder = saved.folder?.standardizedFileURL.resolvingSymlinksInPath()
            cached = saved.entries
            watch()
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // No folder has been chosen yet.
        } catch {
            status = "Could not read the saved GIF library. Check gif-library.json in Charms’ support folder."
            loadFailed = true
        }
    }

    func setFolder(_ url: URL?) {
        guard !loadFailed else { return }
        let newFolder = url?.standardizedFileURL.resolvingSymlinksInPath()
        if newFolder == folder {
            observer = nil
            watch()
            return
        }
        guard newFolder?.isFileURL != false, save(folder: newFolder, entries: []) else { return }
        observer = nil
        scan?.cancel()
        worker?.cancel()
        worker = nil
        failed.removeAll()
        cached = []
        modelDeferred.removeAll()
        entries = []
        folder = newFolder
        status = nil
        watch()
    }

    func setTags(_ tags: [String], for url: URL) {
        guard let i = entries.firstIndex(where: { $0.url == url }) else { return }
        var updated = entries
        var seen = Set<String>()
        updated[i].userTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        if save(folder: folder, entries: updated) { entries = updated }
    }

    private func watch() {
        guard let folder else { return }
        observer = GIFFolderObserver(folder: folder) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        scheduleScan()
    }

    func refresh() {
        if folder != nil { scheduleScan() }
    }

    private func scheduleScan() {
        guard let folder else { return }
        scan?.cancel()
        scan = Task {
            do {
                let files = try await Self.files(in: folder)
                guard !Task.isCancelled else { return }
                apply(files)
            } catch {
                guard !Task.isCancelled else { return }
                cached = entries.isEmpty ? cached : entries
                entries = []
                status = "Cannot read the GIF folder. Check its location and permissions."
            }
        }
    }

    private nonisolated static func files(in folder: URL) async throws -> [LocalGIFEntry] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles])
        return urls.compactMap { url -> LocalGIFEntry? in
            guard url.pathExtension.lowercased() == "gif", let revision = GIFFileSnapshot.inspect(url) else { return nil }
            return LocalGIFEntry(url: url, revision: revision)
        }.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    private func apply(_ files: [LocalGIFEntry]) {
        let existing = cached.isEmpty ? entries : cached
        cached = []
        let old = Dictionary(existing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        let byRevision = Dictionary(existing.map { ($0.revision, $0) }, uniquingKeysWith: { first, _ in first })
        let updated = files.map { file -> LocalGIFEntry in
            if let previous = old[file.url], previous.revision == file.revision { return previous }
            var entry = file
            if let renamed = byRevision[file.revision] {
                entry.generatedTags = renamed.generatedTags
                entry.method = renamed.method
                entry.userTags = renamed.userTags
            } else {
                entry.userTags = old[file.url]?.userTags
            }
            return entry
        }
        if updated != entries {
            entries = updated
            guard save(folder: folder, entries: entries) else { return }
        }
        if worker == nil { startAnalysis() }
    }

    private func startAnalysis() {
        worker = Task(priority: .utility) {
            let preferred = GIFAnalyzer.preferredMethod
            while !Task.isCancelled,
                  let entry = entries.first(where: {
                      ($0.method == nil || ($0.method == .vision && preferred == .multimodal)) &&
                          !failed.contains($0.revision) && !modelDeferred.contains($0.revision)
                  }) {
                status = "Indexing GIFs…"
                do {
                    let result = try await analyze(entry.url)
                    guard !Task.isCancelled else { return }
                    guard GIFFileSnapshot.inspect(entry.url) == entry.revision,
                          let i = entries.firstIndex(where: { $0.url == entry.url && $0.revision == entry.revision }) else {
                        failed.insert(entry.revision)
                        continue
                    }
                    entries[i].generatedTags = result.tags
                    entries[i].method = result.method
                    if preferred == .multimodal && result.method == .vision { modelDeferred.insert(entry.revision) }
                    guard save(folder: folder, entries: entries) else { worker = nil; return }
                } catch {
                    guard !Task.isCancelled else { return }
                    failed.insert(entry.revision)
                }
            }
            guard !Task.isCancelled else { return }
            worker = nil
            failed.formIntersection(entries.map(\.revision))
            modelDeferred.formIntersection(entries.map(\.revision))
            if observer == nil { status = "Could not watch this folder. Choose it again to refresh." }
            else if !failed.isEmpty { status = "Some GIFs could only be indexed by filename." }
            else if !modelDeferred.isEmpty { status = "Some GIFs have Vision tags. Reaction tagging will retry on the next launch." }
            else { status = nil }
        }
    }

    private func save(folder: URL?, entries: [LocalGIFEntry]) -> Bool {
        do {
            let bytes = try JSONEncoder().encode(Archive(folder: folder, entries: entries))
            try FileManager.default.createDirectory(at: index.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: index, options: .atomic)
            return true
        } catch {
            status = "Could not save the GIF index. Check access to the Charms support folder."
            return false
        }
    }
}
