import CharmsCore
import Combine
import Foundation

/// Searches one online GIF service for the picker.
///
/// Nothing is sent until `search` is called, and a search only reaches the
/// provider the user chose and has a key for. Provider, rating and the
/// anonymous client identifier live under the Charms support directory,
/// so an isolated home (`CHARMS_HOME`) keeps its own settings and its own
/// keys; the real home keeps its keys in the Keychain.
@MainActor
public final class OnlineGIFSearch: ObservableObject {
    @Published public private(set) var items: [GIFItem] = []
    @Published public private(set) var attribution: String
    @Published public private(set) var status: String?
    @Published public private(set) var provider: GIFProvider
    @Published public private(set) var rating: GIFRating
    @Published public private(set) var hasKey: Bool

    private static let stateFileName = "gif-search.json"
    private static let gifMagic = Data("GIF8".utf8)

    private let stateFileURL: URL
    private let keys: any GIFServiceKeyStoring
    private let language: String
    private let region: String?
    private let clientID: String
    private let media = GIFMediaFetcher()
    private var searchTask: Task<Void, Never>?
    private var generation = 0
    private var activeQuery = ""
    @Published private(set) var nextPage: Int?
    private var previewCache: [String: Data] = [:]
    private var previewCacheBytes = 0

    public init(supportDirectory: URL) {
        self.stateFileURL = supportDirectory.appendingPathComponent(Self.stateFileName)
        let state = Self.loadState(from: stateFileURL)
        self.provider = state.provider
        self.rating = state.rating
        self.clientID = state.clientID
        self.attribution = state.provider.attribution
        self.keys = GIFServiceKeyStores.make(supportDirectory: supportDirectory)
        self.hasKey = false
        self.language = Locale.current.language.languageCode?.identifier ?? "en"
        self.region = Locale.current.region?.identifier
        if state.needsSave { saveState() }
    }

    /// Searches the chosen service once typing settles. Clearing the field cancels.
    /// A missing key is a status, not a network call. A new search cancels
    /// the previous one, and only the newest result is applied.
    public func search(_ query: String) {
        cancel()
        activeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !activeQuery.isEmpty { loadPage(cursor: nil) }
    }

    func loadMore() {
        guard let nextPage else { return }
        loadPage(cursor: nextPage)
    }

    private func loadPage(cursor: Int?) {
        let request = generation
        nextPage = nil
        status = "Searching…"
        searchTask = Task { [weak self] in
            do {
                if cursor == nil { try await Task.sleep(for: .milliseconds(300)) }
                guard let self, request == self.generation else { return }
                guard let key = self.key(for: self.provider) else { throw GIFSearchError.missingKey }
                let client = GIFSearchClient(request: GIFSearchRequest(
                    provider: self.provider, key: key, rating: self.rating, language: self.language,
                    region: self.region, clientID: self.clientID
                ))
                let page = try await client.page(query: self.activeQuery, cursor: cursor)
                guard !Task.isCancelled, request == self.generation else { return }
                self.items.append(contentsOf: page.items)
                self.nextPage = page.next
                self.status = self.items.isEmpty ? "No matching GIFs." : nil
            } catch {
                guard let self, !Task.isCancelled, request == self.generation else { return }
                self.nextPage = cursor
                self.status = (error as? GIFSearchError ?? .unavailable).localizedDescription
            }
        }
    }

    /// Stops the current search and ignores whatever it still returns.
    public func cancel() {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        activeQuery = ""
        nextPage = nil
        items = []
        clearPreviewCache()
        status = nil
    }

    /// Bytes of one result's preview, bounded and cached. Only a GIF from
    /// a service media host is fetched; anything else is nil.
    public func previewData(for url: URL) async -> Data? {
        guard items.contains(where: { $0.preview.url == url }) else { return nil }
        if let cached = previewCache[url.absoluteString] { return cached }
        let current = generation
        guard let data = await media.data(for: url), current == generation, !Task.isCancelled, data.starts(with: Self.gifMagic) else { return nil }
        cachePreview(data, for: url)
        return data
    }

    // MARK: Provider settings

    public func setProvider(_ provider: GIFProvider) {
        guard provider != self.provider else { return }
        cancel()
        self.provider = provider
        attribution = provider.attribution
        hasKey = keys.key(for: provider) != nil
        saveState()
    }

    public func setRating(_ rating: GIFRating) {
        guard rating != self.rating else { return }
        cancel()
        self.rating = rating
        saveState()
    }

    /// The stored key for a service, for the settings field. Nil when the
    /// service has none.
    public func key(for provider: GIFProvider) -> String? {
        let value = keys.key(for: provider)
        if provider == self.provider { hasKey = value != nil }
        return value
    }

    /// Saves or removes a service's key. Returns nil on success, else the
    /// message to show.
    @discardableResult
    public func setKey(_ key: String?, for provider: GIFProvider) -> String? {
        do {
            try keys.setKey(key, for: provider)
            if provider == self.provider { hasKey = keys.key(for: provider) != nil }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: State

    private struct StoredState: Codable {
        var provider: String?
        var rating: String?
        var clientID: String?
    }

    private struct State {
        let provider: GIFProvider
        let rating: GIFRating
        let clientID: String
        let needsSave: Bool
    }

    private static func loadState(from url: URL) -> State {
        let stored: StoredState?
        do {
            stored = try JSONDecoder().decode(StoredState.self, from: Data(contentsOf: url))
        } catch {
            stored = nil
        }
        var needsSave = stored == nil
        let provider = stored?.provider.flatMap(GIFProvider.init(rawValue:)) ?? .standard
        if stored?.provider != provider.rawValue { needsSave = true }
        let rating = stored?.rating.flatMap(GIFRating.init(rawValue:)) ?? .standard
        if stored?.rating != rating.rawValue { needsSave = true }
        let clientID = stored?.clientID.flatMap { UUID(uuidString: $0) != nil ? $0 : nil } ?? UUID().uuidString
        if stored?.clientID != clientID { needsSave = true }
        return State(provider: provider, rating: rating, clientID: clientID, needsSave: needsSave)
    }

    private func saveState() {
        let state = StoredState(provider: provider.rawValue, rating: rating.rawValue, clientID: clientID)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: stateFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateFileURL, options: .atomic)
    }

    // MARK: Preview cache

    private func cachePreview(_ data: Data, for url: URL) {
        guard data.count <= GIFMediaPolicy.maximumPreviewBytes else { return }
        let key = url.absoluteString
        while previewCacheBytes + data.count > GIFMediaPolicy.maximumPreviewCacheBytes,
              let oldest = previewCache.keys.first {
            previewCacheBytes -= previewCache.removeValue(forKey: oldest)?.count ?? 0
        }
        if let existing = previewCache[key] { previewCacheBytes -= existing.count }
        previewCache[key] = data
        previewCacheBytes += data.count
    }

    private func clearPreviewCache() {
        previewCache.removeAll()
        previewCacheBytes = 0
    }
}
