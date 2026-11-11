import Foundation

/// One cell of the picker.
public struct PickerItem: Equatable, Sendable, Identifiable {
    /// The exact text this cell inserts.
    public let string: String
    public let name: String
    /// What to draw in the cell. Differs from `string` only for characters
    /// that show nothing by themselves: a combining mark is drawn on a
    /// dotted circle and a space as an open box. Never inserted.
    public let preview: String
    public let isEmoji: Bool
    public let isFavourite: Bool
    /// Catalogue index of the base emoji whose skin-tone variants can be
    /// offered for this cell, or nil when it has none.
    public let variantBaseIndex: Int?
    public let snippetShortcut: String?
    public var isSnippet: Bool { snippetShortcut != nil }

    public init(string: String, name: String, preview: String? = nil, isEmoji: Bool, isFavourite: Bool, variantBaseIndex: Int?, snippetShortcut: String? = nil) {
        self.string = string
        self.name = name
        self.preview = preview ?? string
        self.isEmoji = isEmoji
        self.isFavourite = isFavourite
        self.variantBaseIndex = variantBaseIndex
        self.snippetShortcut = snippetShortcut
    }

    public var id: ExactString { ExactString(string) }

    /// `U+2192`, or every code point of a sequence.
    public var codePoints: String { string.codePointDescription }

    public static func == (lhs: PickerItem, rhs: PickerItem) -> Bool {
        lhs.string.isExactly(rhs.string) && lhs.name == rhs.name && lhs.isEmoji == rhs.isEmoji
            && lhs.isFavourite == rhs.isFavourite && lhs.variantBaseIndex == rhs.variantBaseIndex
            && lhs.snippetShortcut == rhs.snippetShortcut
    }
}

public struct PickerSection: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case favourites
        case recents
        case results
    }

    public let kind: Kind
    public let items: [PickerItem]

    public init(kind: Kind, items: [PickerItem]) {
        self.kind = kind
        self.items = items
    }

    public var id: Kind { kind }
}

/// Decides what the picker shows for a query: favourites and recents when it
/// is empty, one grid of results otherwise.
public struct PickerContent: Sendable {
    /// Rows of favourites and of recents shown before any query.
    public static let favouriteRows = 2
    public static let recentRows = 2

    public let catalog: Catalog
    public let index: SearchIndex

    public init(catalog: Catalog, index: SearchIndex) {
        self.catalog = catalog
        self.index = index
    }

    /// - Parameters:
    ///   - isSupported: Whether this system can draw the entry. Results that
    ///     cannot be drawn are left out, except when the query names them
    ///     literally or by code point: an explicit request is always honoured.
    public func sections(
        query: String,
        library: UserLibrary,
        skinTone: SkinTone,
        columns: Int,
        snippets: SnippetLibrary = SnippetLibrary(),
        isSupported: (CatalogEntry) -> Bool,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> [PickerSection] {
        let columns = max(1, columns)
        guard !query.allSatisfy(\.isWhitespace) else {
            return emptyQuerySections(library: library, columns: columns)
        }

        let favourites = Set(library.favourites.map { ExactString($0.string) })
        let recents = Set(library.recents.map { ExactString($0.string) })
        let hits = index.search(query, options: SearchOptions(favourites: favourites, recents: recents, isCancelled: isCancelled))

        var seen = Set<ExactString>()
        var items: [PickerItem] = []
        items.reserveCapacity(hits.count)
        let matches = snippets.matches(query: query)
        func appendSnippets(_ candidates: [TextSnippet]) {
            for snippet in candidates where seen.insert(ExactString(snippet.text)).inserted {
                items.append(PickerItem(string: snippet.text, name: snippet.name, isEmoji: false,
                                        isFavourite: favourites.contains(ExactString(snippet.text)),
                                        variantBaseIndex: nil, snippetShortcut: snippet.shortcut))
            }
        }
        // Explicit user shortcuts win, including over an emoji's alias.
        // Other snippet matches follow literal/code-point/exact catalogue hits
        // but precede broad prefixes. The catalogue's own ordering is intact.
        appendSnippets(matches.filter { $0.matchesShortcut(query) || $0.text.isExactly(query) })
        var appendedOtherSnippets = false
        for hit in hits {
            if hit.tier >= .prefix, !appendedOtherSnippets {
                appendSnippets(matches)
                appendedOtherSnippets = true
            }
            let explicit = hit.tier == .literal || hit.tier == .codePoint || hit.tier == .bareCodePoint
            guard let shown = displayed(hit.entry, at: hit.index, skinTone: skinTone, explicit: explicit, isSupported: isSupported) else {
                continue
            }
            guard seen.insert(ExactString(shown.entry.string)).inserted else { continue }
            items.append(item(for: shown.entry, at: shown.index, favourites: favourites))
        }
        if !appendedOtherSnippets { appendSnippets(matches) }
        return [PickerSection(kind: .results, items: items)]
    }

    /// The base emoji and its skin-tone variants, for the cell's menu.
    public func variants(ofBaseAt baseIndex: Int, library: UserLibrary, isSupported: (CatalogEntry) -> Bool) -> [PickerItem] {
        guard catalog.entries.indices.contains(baseIndex), let range = catalog.variants(ofEntryAt: baseIndex) else { return [] }
        let favourites = Set(library.favourites.map { ExactString($0.string) })
        var items = [item(for: catalog.entries[baseIndex], at: baseIndex, favourites: favourites)]
        for index in range where isSupported(catalog.entries[index]) {
            items.append(item(for: catalog.entries[index], at: index, favourites: favourites))
        }
        return items
    }

    /// The item for a string the user saved earlier. The stored name is used
    /// when the catalogue no longer lists the string.
    public func item(for saved: LibraryItem, isFavourite: Bool) -> PickerItem {
        if let shortcut = saved.snippetShortcut {
            return PickerItem(string: saved.string, name: saved.name, isEmoji: false,
                              isFavourite: isFavourite, variantBaseIndex: nil, snippetShortcut: shortcut)
        }
        if let index = catalog.index(of: saved.string) {
            let entry = catalog.entries[index]
            return PickerItem(string: entry.string, name: entry.displayName, preview: Self.preview(for: entry), isEmoji: entry.isEmoji, isFavourite: isFavourite, variantBaseIndex: variantBase(for: entry, at: index))
        }
        let name = catalog.resolve(saved.string)?.displayName ?? saved.name
        return PickerItem(string: saved.string, name: name, isEmoji: false, isFavourite: isFavourite, variantBaseIndex: nil)
    }

    private func emptyQuerySections(library: UserLibrary, columns: Int) -> [PickerSection] {
        let favourites = library.favourites.prefix(Self.favouriteRows * columns).map { item(for: $0, isFavourite: true) }
        let shown = Set(favourites.map(\.id))
        // A recent that already sits among the favourites above would only
        // repeat it.
        let recents = library.recents
            .filter { !shown.contains(ExactString($0.string)) }
            .prefix(Self.recentRows * columns)
            .map { item(for: $0, isFavourite: library.isFavourite($0.string)) }
        return [
            PickerSection(kind: .favourites, items: Array(favourites)),
            PickerSection(kind: .recents, items: Array(recents))
        ]
    }

    /// Applies the preferred skin tone and the rendering check to one hit.
    private func displayed(_ entry: CatalogEntry, at index: Int?, skinTone: SkinTone, explicit: Bool, isSupported: (CatalogEntry) -> Bool) -> (entry: CatalogEntry, index: Int?)? {
        guard let index else {
            // An entry synthesised from a range has no variants.
            return explicit || isSupported(entry) ? (entry, nil) : nil
        }
        if explicit {
            return (entry, index)
        }
        guard isSupported(entry) else { return nil }
        if entry.kind == .emoji, skinTone != .none {
            let preferred = catalog.preferredIndex(for: index, tone: skinTone)
            if preferred != index, isSupported(catalog.entries[preferred]) {
                return (catalog.entries[preferred], preferred)
            }
        }
        return (entry, index)
    }

    private func item(for entry: CatalogEntry, at index: Int?, favourites: Set<ExactString>) -> PickerItem {
        PickerItem(
            string: entry.string,
            name: entry.displayName,
            preview: Self.preview(for: entry),
            isEmoji: entry.isEmoji,
            isFavourite: favourites.contains(ExactString(entry.string)),
            variantBaseIndex: index.flatMap { variantBase(for: entry, at: $0) }
        )
    }

    /// A drawable stand-in for entries that are invisible alone.
    static func preview(for entry: CatalogEntry) -> String {
        switch entry.kind {
        case .mark: return "\u{25CC}" + entry.string
        case .space: return "\u{2423}"
        case .emoji, .variant, .symbol, .punctuation, .letter, .number: return entry.string
        }
    }

    private func variantBase(for entry: CatalogEntry, at index: Int) -> Int? {
        switch entry.kind {
        case .emoji:
            return catalog.variants(ofEntryAt: index) == nil ? nil : index
        case .variant:
            return catalog.base(ofVariantAt: index)
        case .symbol, .punctuation, .letter, .number, .mark, .space:
            return nil
        }
    }
}

/// The favourites a new user starts with: the ones in the design sketch.
public enum SeedFavourites {
    public static let strings: [String] = [
        "\u{2192}", "\u{2713}", "\u{2014}", "\u{221E}", "\u{1F44D}", "\u{1F60A}", "\u{2764}\u{FE0F}", "\u{1F389}"
    ]

    /// The seed as library items, named from the catalogue. Strings the
    /// catalogue does not list are left out rather than shown without a name.
    public static func items(in catalog: Catalog) -> [LibraryItem] {
        strings.compactMap { string in
            catalog.resolve(string).map { LibraryItem(string: string, name: $0.displayName) }
        }
    }
}
