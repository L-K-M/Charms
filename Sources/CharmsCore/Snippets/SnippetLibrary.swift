import Foundation

/// The editable list is separate from generated Unicode data. An empty saved
/// list is intentional; defaults are applied only when the file is missing.
public struct SnippetLibrary: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumCount = 500
    public private(set) var snippets: [TextSnippet]

    public init() { snippets = [] }

    public init(snippets: [TextSnippet]) throws {
        guard snippets.count <= Self.maximumCount else { throw SnippetError.tooManySnippets }
        guard Set(snippets.map(\.id)).count == snippets.count else { throw SnippetError.duplicateID }
        guard Set(snippets.map(\.shortcut)).count == snippets.count else { throw SnippetError.duplicateShortcut }
        self.snippets = snippets
    }

    public mutating func upsert(_ snippet: TextSnippet) throws {
        var updated = snippets
        if let index = updated.firstIndex(where: { $0.id == snippet.id }) {
            updated[index] = snippet
        } else {
            updated.append(snippet)
        }
        self = try Self(snippets: updated)
    }

    public mutating func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
    }

    /// Restore deleted starters without overwriting edited IDs or shortcuts
    /// claimed by custom entries. The whole merge is validated before mutation.
    public mutating func addMissingStarters() throws {
        let ids = Set(snippets.map(\.id))
        let shortcuts = Set(snippets.map(\.shortcut))
        let missing = DefaultSnippets.library.snippets.filter { !ids.contains($0.id) && !shortcuts.contains($0.shortcut) }
        self = try Self(snippets: snippets + missing)
    }

    /// Exact shortcuts/payloads first, then metadata matches. Search folding
    /// is never applied to the replacement itself.
    public func matches(query: String) -> [TextSnippet] {
        let folded = SearchText.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !folded.isEmpty else { return [] }
        let tokens = SearchText.tokens(folded)
        func rank(_ snippet: TextSnippet) -> Int? {
            if snippet.matchesShortcut(query) { return 0 }
            if snippet.text.isExactly(query) { return 1 }
            let name = SearchText.fold(snippet.name)
            if name == folded { return 2 }
            guard !tokens.isEmpty else { return nil }
            let words = SearchText.tokens(name + " " + snippet.shortcut)
            return tokens.allSatisfy({ token in words.contains(where: { $0.starts(with: token) }) }) ? 3 : nil
        }
        let ranked: [(snippet: TextSnippet, rank: Int)] = snippets.compactMap { snippet in
            guard let value = rank(snippet) else { return nil }
            return (snippet, value)
        }
        let sorted = ranked.sorted { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.snippet.shortcut < rhs.snippet.shortcut : lhs.rank < rhs.rank
        }
        return sorted.map(\.snippet)
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, snippets }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard try fields.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnippetError.unsupportedSchema
        }
        try self.init(snippets: fields.decode([TextSnippet].self, forKey: .snippets))
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(Self.schemaVersion, forKey: .schemaVersion)
        try fields.encode(snippets, forKey: .snippets)
    }
}
