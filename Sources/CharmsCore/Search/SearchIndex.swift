import Foundation

public struct SearchHit: Sendable, Equatable {
    /// Relevance tiers, most relevant first. A hit in an earlier tier always
    /// precedes a hit in a later one, whatever its popularity.
    public enum Tier: Int, Sendable, Comparable {
        /// The query is the character itself.
        case literal
        /// An explicit `U+` code point query.
        case codePoint
        /// The whole query equals a curated alias, the name, or a keyword.
        case exact
        /// A bare hex word read as a code point. Ranked under exact names
        /// because `face` and `100` are words and numbers first.
        case bareCodePoint
        /// Every query word starts a word of the entry.
        case prefix
        /// Some of several query words name the entry exactly, offered when
        /// the words together name nothing exactly: `red car` shows the
        /// cars, then red things. Ranked above substrings, which for several
        /// words are mostly coincidences (`scared` holds `car` and `red`).
        case someWords
        /// Every query word occurs inside a word of the entry.
        case substring
        /// A near miss, offered only when little else matched.
        case fuzzy

        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let entry: CatalogEntry
    /// Position in the catalogue, or nil for a character synthesised from an
    /// algorithmically named range.
    public let index: Int?
    public let tier: Tier

    public init(entry: CatalogEntry, index: Int?, tier: Tier) {
        self.entry = entry
        self.index = index
        self.tier = tier
    }
}

public struct SearchOptions: Sendable {
    /// Upper bound on returned hits.
    public var limit: Int
    /// Favourites and recents break ties inside a tier; they never lift a hit
    /// into a better tier.
    public var favourites: Set<ExactString>
    public var recents: Set<ExactString>
    /// Polled between stages so a superseded search stops early.
    public var isCancelled: @Sendable () -> Bool

    public init(limit: Int = 240, favourites: Set<ExactString> = [], recents: Set<ExactString> = [], isCancelled: @escaping @Sendable () -> Bool = { false }) {
        self.limit = limit
        self.favourites = favourites
        self.recents = recents
        self.isCancelled = isCancelled
    }
}

/// An in-memory word index over the catalogue.
///
/// Words are stored once, sorted, in one flat byte buffer with a posting list
/// per word. A prefix is a binary search; a substring or near-miss search is a
/// linear scan over some twenty thousand short words, which is far inside the
/// 30 ms budget and needs no database.
public final class SearchIndex: Sendable {
    public let catalog: Catalog

    private enum Field: UInt32 {
        case alias = 0
        case name = 1
        case keyword = 2
        /// A curated related or preferred word, which suggests the entry
        /// without naming it.
        case related = 3
        case group = 4

        /// Postings and match scores keep the field in their low bits.
        static let bits: UInt32 = 3
        static let mask: UInt32 = (1 << bits) - 1
    }

    private struct AliasPosting: Sendable {
        let entry: Int32
        let rank: UInt8
    }

    /// All words, concatenated in sorted order.
    private let tokenBytes: [UInt8]
    /// Start of each word in `tokenBytes`; one extra element marks the end.
    private let tokenOffsets: [Int32]
    /// Start of each word's postings; one extra element marks the end.
    private let postingOffsets: [Int32]
    /// `entry << Field.bits | field`, at most one per entry and word (the
    /// best field).
    private let postings: [UInt32]
    /// Folded alias text to the entries carrying it.
    private let aliasMap: [String: [AliasPosting]]
    /// Related words, as canonical words joined by spaces, to the entries
    /// carrying them.
    private let relatedMap: [String: [AliasPosting]]
    /// Preferred words, keyed like related words.
    private let preferredMap: [String: [AliasPosting]]
    /// Folded names and keywords that contain no letters or digits, such as
    /// `+` or `<3`, which the word index cannot represent.
    private let symbolicMap: [String: [Int32]]

    public var tokenCount: Int { tokenOffsets.count - 1 }

    // MARK: - Building

    public init(catalog: Catalog) {
        self.catalog = catalog

        var tokenIDs: [[UInt8]: Int] = [:]
        var lists: [[UInt32]] = []
        var aliases: [String: [AliasPosting]] = [:]
        var related: [String: [AliasPosting]] = [:]
        var preferred: [String: [AliasPosting]] = [:]
        var symbolic: [String: [Int32]] = [:]
        var groupTokens: [String: [[UInt8]]] = [:]

        func add(_ token: [UInt8], entry: Int, field: Field) {
            let id: Int
            if let existing = tokenIDs[token] {
                id = existing
            } else {
                id = lists.count
                tokenIDs[token] = id
                lists.append([])
            }
            let packed = UInt32(entry) << Field.bits | field.rawValue
            if let last = lists[id].last, last >> Field.bits == UInt32(entry) {
                // Same entry again: keep whichever field ranks better.
                if packed < last {
                    lists[id][lists[id].count - 1] = packed
                }
                return
            }
            lists[id].append(packed)
        }

        func addPhrase(_ phrase: String, entry: Int, field: Field) {
            let folded = SearchText.fold(phrase)
            let tokens = SearchText.tokens(folded)
            if tokens.isEmpty {
                if !folded.isEmpty, field != .group {
                    symbolic[folded, default: []].append(Int32(entry))
                }
                return
            }
            for token in tokens {
                add(token, entry: entry, field: field)
            }
        }

        for (index, entry) in catalog.entries.enumerated() where entry.kind != .variant {
            addPhrase(entry.name, entry: index, field: .name)
            for keyword in entry.keywords {
                addPhrase(keyword, entry: index, field: .keyword)
            }
            for alias in entry.aliases {
                let folded = SearchText.fold(alias.text)
                aliases[folded, default: []].append(AliasPosting(entry: Int32(index), rank: alias.rank))
                for token in SearchText.tokens(folded) {
                    add(token, entry: index, field: .alias)
                }
            }
            for (words, isPreferred) in [(entry.relatedWords, false), (entry.preferredWords, true)] {
                for word in words {
                    let tokens = SearchText.tokens(SearchText.fold(word.text))
                    guard !tokens.isEmpty else { continue }
                    let posting = AliasPosting(entry: Int32(index), rank: word.rank)
                    if isPreferred {
                        preferred[Self.phraseKey(tokens), default: []].append(posting)
                    } else {
                        related[Self.phraseKey(tokens), default: []].append(posting)
                    }
                    for token in tokens {
                        add(token, entry: index, field: .related)
                    }
                }
            }
            let tokens: [[UInt8]]
            if let cached = groupTokens[entry.group] {
                tokens = cached
            } else {
                // Block names carry fragments such as the `1` of "Latin-1
                // Supplement" or the `a` of "Extended-A"; as search words
                // they would attach a whole block to a one-letter query.
                tokens = SearchText.tokens(SearchText.fold(entry.group)).filter { $0.count >= Self.groupWordMinimumLength }
                groupTokens[entry.group] = tokens
            }
            for token in tokens {
                add(token, entry: index, field: .group)
            }
        }

        let order = tokenIDs.sorted { $0.key.lexicographicallyPrecedes($1.key) }
        var bytes: [UInt8] = []
        var offsets: [Int32] = [0]
        var postingStarts: [Int32] = [0]
        var flatPostings: [UInt32] = []
        offsets.reserveCapacity(order.count + 1)
        postingStarts.reserveCapacity(order.count + 1)
        for (token, id) in order {
            bytes.append(contentsOf: token)
            offsets.append(Int32(bytes.count))
            flatPostings.append(contentsOf: lists[id])
            postingStarts.append(Int32(flatPostings.count))
        }
        tokenBytes = bytes
        tokenOffsets = offsets
        postingOffsets = postingStarts
        postings = flatPostings
        aliasMap = aliases.mapValues { $0.sorted { ($0.rank, $0.entry) < ($1.rank, $1.entry) } }
        relatedMap = related.mapValues { $0.sorted { ($0.rank, $0.entry) < ($1.rank, $1.entry) } }
        preferredMap = preferred.mapValues { $0.sorted { ($0.rank, $0.entry) < ($1.rank, $1.entry) } }
        symbolicMap = symbolic
    }

    // MARK: - Searching

    /// A possible hit. It refers to its entry by position rather than
    /// carrying a copy: copying an entry retains each of its strings and
    /// lists, and a one-letter query has thousands of candidates. With
    /// copies, `s` took 22 ms in an optimised build on Apple silicon (more
    /// once entries gained curated words); by position it takes 5 ms.
    private struct Candidate {
        enum Source {
            case catalogue(Int)
            /// A character outside the catalogue, found by its code point.
            indirect case outside(CatalogEntry)
        }

        var source: Source
        var tier: SearchHit.Tier
        /// Higher is better, compared only inside one tier.
        var quality: Int

        init(index: Int, tier: SearchHit.Tier, quality: Int) {
            self.source = .catalogue(index)
            self.tier = tier
            self.quality = quality
        }

        init(outside entry: CatalogEntry, tier: SearchHit.Tier, quality: Int) {
            self.source = .outside(entry)
            self.tier = tier
            self.quality = quality
        }

        /// The entry's position in the catalogue, if it has one.
        var index: Int? {
            if case .catalogue(let index) = source { return index }
            return nil
        }
    }

    private func entry(of candidate: Candidate) -> CatalogEntry {
        switch candidate.source {
        case .catalogue(let index): return catalog.entries[index]
        case .outside(let entry): return entry
        }
    }

    private func string(of candidate: Candidate) -> String {
        switch candidate.source {
        case .catalogue(let index): return catalog.entries[index].string
        case .outside(let entry): return entry.string
        }
    }

    private func rank(of candidate: Candidate) -> UInt8 {
        switch candidate.source {
        case .catalogue(let index): return catalog.entries[index].rank
        case .outside(let entry): return entry.rank
        }
    }

    public func search(_ rawQuery: String, options: SearchOptions = SearchOptions()) -> [SearchHit] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, options.limit > 0 else { return [] }

        var special: [Candidate] = []
        let codePoints = CodePointQuery.parse(query)
        if let codePoints, codePoints.isExplicit {
            special.append(contentsOf: resolve(codePoints.string, tier: .codePoint))
        }

        // Pasted characters are looked up as themselves. Matching runs on the
        // raw query, before any case or accent folding.
        let hasNonASCII = query.utf8.contains { $0 >= 0x80 }
        if hasNonASCII, !SearchText.containsASCIIAlphanumeric(query) {
            special.append(contentsOf: literalCandidates(query))
            return finish(special, options: options)
        }

        let folded = SearchText.fold(query)
        special.append(contentsOf: aliasCandidates(folded))
        if let symbolHits = symbolicMap[folded] {
            for entry in symbolHits {
                special.append(Candidate(index: Int(entry), tier: .exact, quality: Quality.keyword))
            }
        }

        let tokens = SearchText.tokens(folded)
        if tokens.isEmpty {
            // Punctuation only, such as `#` or `->`. A typed character that is
            // itself an entry leads. When the query is an alias, as `->` is
            // for the arrow, the alias leads and the characters it happens to
            // be written with follow.
            let hasAlias = special.contains { $0.tier == .exact }
            for var candidate in literalCandidates(query) {
                if hasAlias, !string(of: candidate).isExactly(query) {
                    candidate.tier = .prefix
                }
                special.append(candidate)
            }
            return finish(special, options: options)
        }

        special.append(contentsOf: curatedWordCandidates(Self.phraseKey(tokens)))

        // An alias that starts with the query, so that `arr` already shows
        // what `arrow` will show, in the same order.
        for (alias, hits) in aliasMap where alias.utf8.count > folded.utf8.count && alias.hasPrefix(folded) {
            for hit in hits {
                let index = Int(hit.entry)
                special.append(Candidate(index: index, tier: .prefix, quality: Quality.aliasPrefix - min(Int(hit.rank), Quality.aliasPrefix - Quality.aliasPrefixFloor)))
            }
        }

        if let codePoints, !codePoints.isExplicit {
            special.append(contentsOf: resolve(codePoints.string, tier: .bareCodePoint))
        }
        if options.isCancelled() { return [] }

        var candidates = special
        candidates.append(contentsOf: wordCandidates(tokens, matching: .substring))
        if options.isCancelled() { return [] }

        var (hits, matched) = finishCounting(candidates, options: options)

        // Only a query that names nothing exactly is read another way, so a
        // word the catalogue knows is never second-guessed. Dropping filler
        // words is for queries that found little: `letter with` already
        // lists its letters and would otherwise add every other one.
        if let first = hits.first?.tier, first <= .exact {
            // Named exactly as typed.
        } else if CodePointQuery.isNotation(query) {
            // Code points the catalogue lacks, such as `U+10FFFF`: the `u`
            // names the magnet, which is no answer.
        } else {
            let found = candidates.count
            let isSparse = matched < Self.fuzzyThreshold
            // The most faithful reading that names something wins.
            for reading in QueryReadings.alternatives(tokens) where reading.matching == .whole || isSparse {
                let found = readingCandidates(reading)
                candidates.append(contentsOf: found)
                if found.contains(where: { $0.tier == .exact }) { break }
            }
            let words = QueryReadings.significantWords(tokens)
            if words.count > 1, words.count <= QueryReadings.maximumWords {
                candidates.append(contentsOf: someWordsCandidates(words))
            }
            if options.isCancelled() { return [] }
            if candidates.count > found {
                (hits, matched) = finishCounting(candidates, options: options)
            }
        }

        if matched < Self.fuzzyThreshold, tokens.allSatisfy({ $0.count >= Self.fuzzyMinimumLength }) {
            candidates.append(contentsOf: wordCandidates(tokens, matching: .fuzzy))
            if options.isCancelled() { return [] }
            hits = finish(candidates, options: options)
        }
        return hits
    }

    /// Words of a block or emoji group name shorter than this are not indexed.
    static let groupWordMinimumLength = 3
    /// Near misses are offered only when fewer than this many hits exist.
    static let fuzzyThreshold = 8
    /// Shorter words are too ambiguous to correct.
    static let fuzzyMinimumLength = 4
    /// Substring matching starts at this word length; shorter fragments
    /// occur inside almost everything.
    static let substringMinimumLength = 3

    private enum Quality {
        static let alias = 1000
        /// A curated preferred word: after aliases, before names.
        static let preferred = 900
        static let name = 500
        static let keyword = 400
        /// A curated related word: after everything that names the entry,
        /// before every partial match.
        static let related = 300
        /// Added to a keyword match when the entry's name also holds every
        /// query word: for `beer`, a beer mug comes before ginger root.
        static let nameWords = 50
        /// Bonus when every query word equals a whole word of the entry.
        static let wholeWords = 4
        /// Best quality in the prefix tier: an alias that begins with the
        /// query, first target of the alias first.
        static let aliasPrefix = 100
        /// Every alias-prefix match scores at least this, above all other
        /// prefix matches.
        static let aliasPrefixFloor = 20
        /// In the some-words tier, an entry named by more query words leads
        /// whatever the rest; then the position of the word, then how well
        /// that word names it.
        static let someWordsPerWord = 100_000
        static let someWordsPerPosition = 10_000
    }

    // MARK: Literal and code point lookups

    private func resolve(_ string: String, tier: SearchHit.Tier) -> [Candidate] {
        if let index = catalog.index(of: string) {
            return [Candidate(index: index, tier: tier, quality: 0)]
        }
        if let entry = catalog.resolve(string) {
            return [Candidate(outside: entry, tier: tier, quality: 0)]
        }
        return []
    }

    /// The whole query as one item, then each of its characters, then the
    /// scalars of any character that is not itself an entry.
    private func literalCandidates(_ query: String) -> [Candidate] {
        var result = resolve(query, tier: .literal)
        var quality = -1
        for character in query where !character.isWhitespace {
            let text = String(character)
            var found = resolve(text, tier: .literal)
            if found.isEmpty, text.unicodeScalars.count > 1 {
                for scalar in text.unicodeScalars {
                    found.append(contentsOf: resolve(String(scalar), tier: .literal))
                }
            }
            for var candidate in found {
                // Keep the order in which the characters were typed.
                candidate.quality = quality
                quality -= 1
                result.append(candidate)
            }
        }
        return result
    }

    // MARK: Curated words and readings

    private func aliasCandidates(_ key: String) -> [Candidate] {
        (aliasMap[key] ?? []).map { hit in
            let index = Int(hit.entry)
            return Candidate(index: index, tier: .exact, quality: Quality.alias - Int(hit.rank))
        }
    }

    /// Entries whose preferred or related word is exactly this phrase.
    private func curatedWordCandidates(_ key: String) -> [Candidate] {
        func candidates(_ map: [String: [AliasPosting]], quality: Int) -> [Candidate] {
            (map[key] ?? []).map { hit in
                let index = Int(hit.entry)
                return Candidate(index: index, tier: .exact, quality: quality - Int(hit.rank))
            }
        }
        return candidates(preferredMap, quality: Quality.preferred) + candidates(relatedMap, quality: Quality.related)
    }

    /// The form in which a related word or a whole query is looked up.
    private static func phraseKey(_ tokens: [[UInt8]]) -> String {
        String(decoding: SearchText.canonical(tokens), as: UTF8.self)
    }

    private func readingCandidates(_ reading: QueryReadings.Reading) -> [Candidate] {
        switch reading.matching {
        case .prefix:
            let key = Self.phraseKey(reading.tokens)
            return aliasCandidates(key) + curatedWordCandidates(key) + wordCandidates(reading.tokens, matching: .prefix)
        case .whole:
            // A reduced form counts only if it names something exactly, as
            // `cat` does for `cats`; then so do its other whole-word matches,
            // such as the grinning cat.
            let key = Self.phraseKey(reading.tokens)
            let curated = aliasCandidates(key) + curatedWordCandidates(key)
            let words = wordCandidates(reading.tokens, matching: .whole)
            guard !curated.isEmpty || words.contains(where: { $0.tier == .exact }) else { return [] }
            return curated + words
        }
    }

    /// Entries whose alias, preferred or related word, name or keyword is
    /// exactly these words.
    private func exactCandidates(_ tokens: [[UInt8]]) -> [Candidate] {
        let key = Self.phraseKey(tokens)
        return aliasCandidates(key) + curatedWordCandidates(key) + wordCandidates(tokens, matching: .whole).filter { $0.tier == .exact }
    }

    /// For several words that together match little: the entries that some
    /// of them name exactly, each word read in its base form if it names
    /// nothing as typed. Entries named by more of the words lead; then the
    /// matches of later words, since the last word of an English phrase
    /// usually names the thing (`red car`, `urgent message`).
    private func someWordsCandidates(_ words: [[UInt8]]) -> [Candidate] {
        var scores: [Int: (words: Int, position: Int, quality: Int)] = [:]
        for (position, word) in words.enumerated() {
            var matches = exactCandidates([word])
            if matches.isEmpty {
                for base in QueryReadings.baseForms(word) {
                    matches = exactCandidates([base])
                    if !matches.isEmpty { break }
                }
            }
            var qualities: [Int: Int] = [:]
            for match in matches {
                guard let index = match.index else { continue }
                qualities[index] = max(qualities[index] ?? Int.min, match.quality)
            }
            for (index, quality) in qualities {
                let previous = scores[index]?.words ?? 0
                scores[index] = (previous + 1, position, quality)
            }
        }
        return scores.map { index, score in
            let quality = score.words * Quality.someWordsPerWord + score.position * Quality.someWordsPerPosition + score.quality
            return Candidate(index: index, tier: .someWords, quality: quality)
        }
    }

    // MARK: Word matching

    private enum MatchClass: UInt8 {
        case whole = 0
        case prefix = 1
        case substring = 2
        case fuzzy = 3
    }

    /// How loosely each query word may match a word of the entry. Every
    /// level includes the ones before it.
    private enum WordMatching: Int, Comparable {
        case whole
        case prefix
        case substring
        case fuzzy

        static func < (lhs: WordMatching, rhs: WordMatching) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private func wordCandidates(_ queryTokens: [[UInt8]], matching: WordMatching) -> [Candidate] {
        // Words matched so far are counted in a byte. No entry has hundreds
        // of words, so such a query matches nothing.
        guard queryTokens.count < Int(UInt8.max) else { return [] }
        let entryCount = catalog.entries.count
        let none: UInt8 = 0xFF
        /// Best `class << Field.bits | field` for the current query word.
        var current = [UInt8](repeating: none, count: entryCount)
        /// Number of leading query words an entry has matched.
        var matched = [UInt8](repeating: 0, count: entryCount)
        var worstClass = [UInt8](repeating: 0, count: entryCount)
        var worstField = [UInt8](repeating: 0, count: entryCount)
        var touched: [Int32] = []
        var survivors: [Int32] = []

        for (position, queryToken) in queryTokens.enumerated() {
            touched.removeAll(keepingCapacity: true)
            let step = UInt8(truncatingIfNeeded: position)

            func visit(token: Int, matchClass: MatchClass) {
                let start = Int(postingOffsets[token])
                let end = Int(postingOffsets[token + 1])
                for cursor in start..<end {
                    let packed = postings[cursor]
                    let entry = Int(packed >> Field.bits)
                    // An entry that missed an earlier word cannot match.
                    guard matched[entry] == step else { continue }
                    let field = packed & Field.mask
                    // Related words and block names count only as whole words
                    // or prefixes: `port` is no reason to show what
                    // `important` suggests, nor `critical` the Combining
                    // Diacritical Marks.
                    if matchClass == .substring, field == Field.related.rawValue || field == Field.group.rawValue {
                        continue
                    }
                    let score = matchClass.rawValue << UInt8(Field.bits) | UInt8(field)
                    if current[entry] == none {
                        touched.append(Int32(entry))
                        current[entry] = score
                    } else if score < current[entry] {
                        current[entry] = score
                    }
                }
            }

            let range = prefixRange(queryToken)
            for token in range {
                if tokenLength(token) == queryToken.count {
                    visit(token: token, matchClass: .whole)
                } else if matching >= .prefix {
                    visit(token: token, matchClass: .prefix)
                }
            }
            if matching >= .substring, queryToken.count >= Self.substringMinimumLength {
                tokenBytes.withUnsafeBufferPointer { buffer in
                    for token in 0..<tokenCount where !range.contains(token) {
                        let bytes = UnsafeBufferPointer(rebasing: buffer[Int(tokenOffsets[token])..<Int(tokenOffsets[token + 1])])
                        if bytes.count > queryToken.count, Self.contains(bytes, queryToken) {
                            visit(token: token, matchClass: .substring)
                        } else if matching >= .fuzzy, queryToken.count >= Self.fuzzyMinimumLength, bytes.first == queryToken.first {
                            let limit = queryToken.count >= 8 ? 2 : 1
                            if SearchText.editDistance(queryToken, bytes, limit: limit) <= limit {
                                visit(token: token, matchClass: .fuzzy)
                            }
                        }
                    }
                }
            }

            survivors.removeAll(keepingCapacity: true)
            for entry32 in touched {
                let entry = Int(entry32)
                let score = current[entry]
                current[entry] = none
                matched[entry] = step &+ 1
                worstClass[entry] = position == 0 ? score >> UInt8(Field.bits) : max(worstClass[entry], score >> UInt8(Field.bits))
                worstField[entry] = position == 0 ? score & UInt8(Field.mask) : max(worstField[entry], score & UInt8(Field.mask))
                survivors.append(entry32)
            }
            if survivors.isEmpty { return [] }
        }

        let canonicalQuery = SearchText.canonical(queryTokens)
        var result: [Candidate] = []
        result.reserveCapacity(survivors.count)
        for entry32 in survivors {
            let index = Int(entry32)
            let matchClass = worstClass[index]
            let fieldScore = Int(Field.group.rawValue) - Int(worstField[index])
            switch matchClass {
            case MatchClass.whole.rawValue:
                if let quality = exactQuality(at: index, canonicalQuery: canonicalQuery) {
                    result.append(Candidate(index: index, tier: .exact, quality: quality))
                } else {
                    result.append(Candidate(index: index, tier: .prefix, quality: Quality.wholeWords + fieldScore))
                }
            case MatchClass.prefix.rawValue:
                result.append(Candidate(index: index, tier: .prefix, quality: fieldScore))
            case MatchClass.substring.rawValue:
                result.append(Candidate(index: index, tier: .substring, quality: fieldScore))
            default:
                // Without the fuzzy pass no entry reaches this class.
                result.append(Candidate(index: index, tier: .fuzzy, quality: fieldScore))
            }
        }
        return result
    }

    /// Whether the whole query equals the entry's name or one of its keywords,
    /// comparing words rather than punctuation.
    private func exactQuality(at index: Int, canonicalQuery: [UInt8]) -> Int? {
        let name = catalog.entries[index].name
        if Self.canonicalEquals(name, canonicalQuery) {
            return Quality.name
        }
        for keyword in catalog.entries[index].keywords where Self.canonicalEquals(keyword, canonicalQuery) {
            return Quality.keyword + (Self.nameHoldsWords(name, canonicalQuery) ? Quality.nameWords : 0)
        }
        return nil
    }

    /// True when every word of the query is a word of the name standing by
    /// itself between spaces. A part of a hyphenated word does not count:
    /// `no` is a word of "person gesturing NO" but not of "see-no-evil
    /// monkey".
    private static func nameHoldsWords(_ name: String, _ canonicalQuery: [UInt8]) -> Bool {
        var nameWords = Set<[UInt8]>()
        for word in SearchText.fold(name).split(separator: " ") {
            let tokens = SearchText.tokens(String(word))
            if tokens.count == 1 { nameWords.insert(tokens[0]) }
        }
        return canonicalQuery.split(separator: UInt8(ascii: " ")).allSatisfy { nameWords.contains(Array($0)) }
    }

    private static func canonicalEquals(_ phrase: String, _ canonicalQuery: [UInt8]) -> Bool {
        // Folding never lengthens these phrases past a small factor, so a
        // wildly different length cannot be equal. This skips most work.
        let length = phrase.utf8.count
        guard length >= canonicalQuery.count, length <= canonicalQuery.count * 2 + 8 else { return false }
        return SearchText.canonical(SearchText.tokens(SearchText.fold(phrase))) == canonicalQuery
    }

    private func tokenLength(_ token: Int) -> Int {
        Int(tokenOffsets[token + 1] - tokenOffsets[token])
    }

    /// The contiguous run of words that start with `prefix`.
    private func prefixRange(_ prefix: [UInt8]) -> Range<Int> {
        tokenBytes.withUnsafeBufferPointer { buffer in
            func compare(_ token: Int) -> Int {
                // Negative: word sorts before the prefix. Zero: it starts with
                // the prefix. Positive: it sorts after every such word.
                let start = Int(tokenOffsets[token])
                let length = Int(tokenOffsets[token + 1]) - start
                let shared = min(length, prefix.count)
                for offset in 0..<shared where buffer[start + offset] != prefix[offset] {
                    return buffer[start + offset] < prefix[offset] ? -1 : 1
                }
                return length < prefix.count ? -1 : 0
            }
            var low = 0
            var high = tokenCount
            while low < high {
                let middle = (low + high) / 2
                if compare(middle) < 0 { low = middle + 1 } else { high = middle }
            }
            let lower = low
            high = tokenCount
            while low < high {
                let middle = (low + high) / 2
                if compare(middle) <= 0 { low = middle + 1 } else { high = middle }
            }
            return lower..<low
        }
    }

    private static func contains(_ haystack: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count, let first = needle.first else { return false }
        let last = haystack.count - needle.count
        var start = 0
        while start <= last {
            if haystack[start] == first {
                var offset = 1
                while offset < needle.count, haystack[start + offset] == needle[offset] {
                    offset += 1
                }
                if offset == needle.count { return true }
            }
            start += 1
        }
        return false
    }

    // MARK: Ordering

    /// Keeps the best candidate per item and orders them, fully
    /// deterministically. Exact matches go by quality, then favourites and
    /// recents, then prominence, then catalogue order. Partial matches go by
    /// alias first, then favourites and recents, then prominence before the
    /// finer quality: while a word is still being typed, a familiar symbol
    /// that might be meant is a better guess than a rare letter whose name
    /// happens to contain the fragment as a whole word. Some-words matches
    /// go by quality first, like exact ones, since their quality says how
    /// many of the words they answer.
    private func finish(_ candidates: [Candidate], options: SearchOptions) -> [SearchHit] {
        finishCounting(candidates, options: options).hits
    }

    /// Also counts every distinct match, not just the hits within the limit,
    /// so that how many matched never depends on how many are shown.
    private func finishCounting(_ candidates: [Candidate], options: SearchOptions) -> (hits: [SearchHit], matched: Int) {
        var best: [ExactString: Candidate] = [:]
        best.reserveCapacity(candidates.count)
        for candidate in candidates {
            let key = string(of: candidate).exact
            if let existing = best[key], (existing.tier, -existing.quality) <= (candidate.tier, -candidate.quality) {
                continue
            }
            best[key] = candidate
        }

        func boost(_ candidate: Candidate) -> Int {
            let key = string(of: candidate).exact
            if options.favourites.contains(key) { return 2 }
            if options.recents.contains(key) { return 1 }
            return 0
        }

        let useBoost = !options.favourites.isEmpty || !options.recents.isEmpty
        let ordered = best.values.sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            let isPartial = lhs.tier >= .prefix && lhs.tier != .someWords
            if isPartial {
                let lhsLead = lhs.quality >= Quality.aliasPrefixFloor ? lhs.quality : 0
                let rhsLead = rhs.quality >= Quality.aliasPrefixFloor ? rhs.quality : 0
                if lhsLead != rhsLead { return lhsLead > rhsLead }
            } else if lhs.quality != rhs.quality {
                return lhs.quality > rhs.quality
            }
            if useBoost {
                let lhsBoost = boost(lhs)
                let rhsBoost = boost(rhs)
                if lhsBoost != rhsBoost { return lhsBoost > rhsBoost }
            }
            let lhsRank = rank(of: lhs)
            let rhsRank = rank(of: rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if isPartial, lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
            switch (lhs.index, rhs.index) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return string(of: lhs).unicodeScalars.lexicographicallyPrecedes(string(of: rhs).unicodeScalars)
            }
        }
        return (ordered.prefix(options.limit).map { SearchHit(entry: entry(of: $0), index: $0.index, tier: $0.tier) }, ordered.count)
    }
}

private func <= (lhs: (SearchHit.Tier, Int), rhs: (SearchHit.Tier, Int)) -> Bool {
    if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
    return lhs.1 <= rhs.1
}
