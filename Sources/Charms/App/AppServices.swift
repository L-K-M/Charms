import CharmsCore
import Foundation

/// The long-lived objects every part of the app shares.
@MainActor
final class AppServices {
    let paths: AppPaths
    let diagnostics = DiagnosticsLog(sink: AppServices.traceSink())
    let preferences: PreferencesStore
    let library: LibraryController
    let snippets: SnippetController
    let localGIFs: LocalGIFLibrary
    let onlineGIFs: OnlineGIFSearch
    let veniceArtwork: VeniceArtworkService
    let glyphs = GlyphSupport()
    /// Nil until the catalogue has been read, a fraction of a second after
    /// launch.
    private(set) var content: PickerContent?
    var onCatalogLoaded: (() -> Void)?

    init(paths: AppPaths) {
        self.paths = paths
        localGIFs = LocalGIFLibrary(supportDirectory: paths.supportDirectory)
        onlineGIFs = OnlineGIFSearch(supportDirectory: paths.supportDirectory, isIsolated: paths.isIsolated)
        preferences = PreferencesStore(paths: paths)
        veniceArtwork = VeniceArtworkService(
            preferences: preferences,
            keys: VeniceKeyStore.make(supportDirectory: paths.supportDirectory, isIsolated: paths.isIsolated)
        )
        library = LibraryController(paths: paths, diagnostics: diagnostics)
        snippets = SnippetController(paths: paths, diagnostics: diagnostics)
    }

    func loadCatalog() async {
        guard let loaded = await CatalogLoader.load() else {
            diagnostics.record(.launch, "catalogue-missing")
            return
        }
        content = PickerContent(catalog: loaded.catalog, index: loaded.index)
        library.seedIfNeeded(from: loaded.catalog)
        diagnostics.record(.launch, "catalogue-loaded", milliseconds: loaded.milliseconds)
        onCatalogLoaded?()
    }

    /// With `CHARMS_TRACE` set, every diagnostics entry is also written to
    /// standard error as it happens. The end-to-end checks read it to learn
    /// what a session did. Entries have no free text, so the trace holds
    /// nothing a diagnostics export would not.
    private static func traceSink() -> (@Sendable (DiagnosticsLog.Entry) -> Void)? {
        guard ProcessInfo.processInfo.environment["CHARMS_TRACE"] != nil else { return nil }
        return { entry in
            FileHandle.standardError.write(Data((DiagnosticsLog.describe(entry) + "\n").utf8))
        }
    }

    var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}
