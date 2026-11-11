import CharmsCore
import Combine
import Foundation

/// Saves before publishing, so a failed edit leaves the active list intact.
/// A file we cannot understand is read-only until a successful reload.
@MainActor
final class SnippetController: ObservableObject {
    @Published private(set) var library = SnippetLibrary()
    @Published private(set) var isUnavailable = false
    @Published private(set) var message: String?

    private let store: SnippetStore
    private let diagnostics: DiagnosticsLog

    init(paths: AppPaths, diagnostics: DiagnosticsLog) {
        store = SnippetStore(directory: paths.supportDirectory)
        self.diagnostics = diagnostics
        reload()
    }

    func reload() {
        do {
            if let saved = try store.load() {
                library = saved
                message = nil
            } else {
                // Seeding is separate from loading an intentionally empty list.
                // A failed first write still leaves the built-ins usable.
                library = DefaultSnippets.library
                do {
                    try store.save(library)
                    message = nil
                } catch {
                    message = "The starter snippets are available, but could not be saved. Check that Charms can write its application-support folder."
                    diagnostics.record(.storage, "snippets-save-failed")
                }
            }
            isUnavailable = false
        } catch {
            library = SnippetLibrary()
            isUnavailable = true
            message = "Could not load snippets. Your saved file was left untouched. Restore or repair snippets.json while Charms is closed, then try again."
            diagnostics.record(.storage, "snippets-load-failed")
        }
    }

    @discardableResult
    func save(_ snippet: TextSnippet) -> Bool {
        change { try $0.upsert(snippet) }
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        change { $0.remove(id: id) }
    }

    @discardableResult
    func addMissingStarters() -> Bool {
        change { try $0.addMissingStarters() }
    }

    private func change(_ mutate: (inout SnippetLibrary) throws -> Void) -> Bool {
        guard !isUnavailable else { return false }
        var updated = library
        do {
            try mutate(&updated)
            guard updated != library else { message = nil; return true }
            try store.save(updated)
            library = updated
            message = nil
            return true
        } catch let error as SnippetError {
            message = error.localizedDescription
        } catch {
            message = "Could not save snippets. Your active list is unchanged. Check that Charms can write its application-support folder, then try again."
            diagnostics.record(.storage, "snippets-save-failed")
        }
        return false
    }
}
