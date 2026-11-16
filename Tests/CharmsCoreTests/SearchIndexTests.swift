import XCTest
@testable import CharmsCore

/// A hand-built catalogue shaped like the real one: emoji first, then
/// characters, each with the kind of names, keywords and aliases the
/// generator produces. Every expectation below was worked out from the
/// ranking rules, not copied from the engine's output.
final class SearchIndexTests: XCTestCase {
    private static let grin = "\u{1F600}"
    private static let thumbsUp = "\u{1F44D}"
    private static let thumbsUpMedium = "\u{1F44D}\u{1F3FD}"
    private static let hundred = "\u{1F4AF}"
    private static let redHeart = "\u{2764}\u{FE0F}"
    private static let bow = "\u{1F3F9}"
    private static let rightArrowEmoji = "\u{27A1}\u{FE0F}"
    private static let fire = "\u{1F525}"
    private static let fireEngine = "\u{1F692}"
    private static let times = "\u{D7}"
    private static let letterX = "x"
    private static let aMacron = "\u{100}"
    private static let leftArrow = "\u{2190}"
    private static let rightArrow = "\u{2192}"
    private static let upRightArrow = "\u{2197}"
    private static let strokeArrow = "\u{219B}"
    private static let notEqual = "\u{2260}"
    private static let infinity = "\u{221E}"
    private static let command = "\u{2318}"
    private static let check = "\u{2713}"
    private static let textHeart = "\u{2764}"
    private static let ideographFace = "\u{FACE}"
    private static let eAcute = "\u{E9}"
    private static let plus = "+"
    private static let numberSign = "#"
    private static let noBreakSpace = "\u{A0}"
    private static let ohm = "\u{2126}"
    private static let omega = "\u{3A9}"
    private static let exclamation = "\u{2757}"
    private static let policeLight = "\u{1F6A8}"

    private static func age(_ text: String) -> UnicodeAge { UnicodeAge(text)! }

    private static func emoji(_ string: String, _ name: String, _ keywords: [String], group: String, aliases: [CatalogAlias] = [], related: [CatalogAlias] = [], kind: CatalogEntry.Kind = .emoji) -> CatalogEntry {
        CatalogEntry(string: string, kind: kind, rank: 1, age: age("1.0"), group: group, name: name, keywords: keywords, aliases: aliases, relatedWords: related)
    }

    private static func character(_ string: String, _ name: String, kind: CatalogEntry.Kind = .symbol, rank: UInt8, group: String, keywords: [String] = [], aliases: [CatalogAlias] = []) -> CatalogEntry {
        CatalogEntry(string: string, kind: kind, rank: aliases.isEmpty ? rank : 0, age: age("1.1"), group: group, name: name, keywords: keywords, aliases: aliases)
    }

    private static func alias(_ text: String, _ rank: UInt8 = 0) -> CatalogAlias { CatalogAlias(text: text, rank: rank) }

    private static let index: SearchIndex = {
        let entries: [CatalogEntry] = [
            emoji(grin, "grinning face", ["face", "grin", "happy", "smile"], group: "Smileys & Emotion/face-smiling"),
            emoji(thumbsUp, "thumbs up", ["+1", "hand", "thumb", "up"], group: "People & Body/hand-fingers-closed"),
            emoji(thumbsUpMedium, "thumbs up: medium skin tone", ["+1", "hand", "medium skin tone", "thumb", "up"], group: "People & Body/hand-fingers-closed", kind: .variant),
            emoji(hundred, "hundred points", ["100", "full", "hundred", "score"], group: "Smileys & Emotion/emotion"),
            emoji(redHeart, "red heart", ["heart", "love"], group: "Smileys & Emotion/heart", aliases: [alias("heart")]),
            emoji(bow, "bow and arrow", ["archer", "arrow", "bow"], group: "Objects/tool"),
            emoji(rightArrowEmoji, "right arrow", ["arrow", "direction", "east", "right"], group: "Symbols/arrow"),
            emoji(fire, "fire", ["flame", "hot"], group: "Travel & Places/sky & weather"),
            emoji(fireEngine, "fire engine", ["engine", "fire", "truck"], group: "Travel & Places/transport-ground", related: [alias("flame")]),
            // Catalogue order is the opposite of the related-word order.
            emoji(exclamation, "red exclamation mark", ["!", "exclamation", "mark", "punctuation"], group: "Symbols/punctuation", related: [alias("important"), alias("urgent", 1)]),
            emoji(policeLight, "police car light", ["alarm", "beacon", "light", "police"], group: "Travel & Places/transport-ground", related: [alias("urgent")]),
            character(times, "multiplication sign", rank: 1, group: "Latin-1 Supplement", keywords: ["multiply", "times"], aliases: [alias("x"), alias("times")]),
            character(letterX, "latin small letter x", kind: .letter, rank: 3, group: "Basic Latin"),
            character(aMacron, "latin capital letter a with macron", kind: .letter, rank: 3, group: "Latin Extended-A"),
            character(leftArrow, "left arrow", rank: 1, group: "Arrows", keywords: ["arrow", "left", "leftwards arrow"], aliases: [alias("arrow", 1), alias("<-")]),
            character(rightArrow, "right arrow", rank: 1, group: "Arrows", keywords: ["arrow", "right", "rightwards arrow"], aliases: [alias("arrow"), alias("->"), alias("right")]),
            character(upRightArrow, "up-right arrow", rank: 1, group: "Arrows", keywords: ["arrow", "direction", "north east arrow", "northeast"]),
            character(strokeArrow, "rightwards arrow with stroke", rank: 2, group: "Arrows"),
            character(notEqual, "not equal", rank: 1, group: "Mathematical Operators", keywords: ["inequality", "not equal to"], aliases: [alias("!="), alias("neq")]),
            character(infinity, "infinity", rank: 1, group: "Mathematical Operators", aliases: [alias("inf"), alias("infinity")]),
            character(command, "place of interest sign", rank: 2, group: "Miscellaneous Technical", keywords: ["command key"], aliases: [alias("cmd"), alias("command")]),
            character(check, "check mark", rank: 2, group: "Dingbats", aliases: [alias("check"), alias("tick")]),
            character(textHeart, "heavy black heart", rank: 2, group: "Dingbats"),
            character(ideographFace, "cjk compatibility ideograph-face", kind: .letter, rank: 4, group: "CJK Compatibility Ideographs"),
            character(eAcute, "latin small letter e with acute", kind: .letter, rank: 3, group: "Latin-1 Supplement"),
            character(plus, "plus sign", rank: 1, group: "Basic Latin", keywords: ["+", "add"]),
            character(numberSign, "number sign", kind: .punctuation, rank: 2, group: "Basic Latin", keywords: ["hash", "pound"]),
            character(noBreakSpace, "no-break space", kind: .space, rank: 2, group: "Latin-1 Supplement", keywords: ["nbsp"], aliases: [alias("nbsp")]),
            character(ohm, "ohm sign", rank: 2, group: "Letterlike Symbols", aliases: [alias("ohm")]),
            character(omega, "greek capital letter omega", kind: .letter, rank: 3, group: "Greek and Coptic", aliases: [alias("omega")])
        ]
        let ranges = [
            CodePointRange(first: 0x4E00, last: 0x9FFF, rule: .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"), group: "CJK Unified Ideographs", age: age("1.1")),
            CodePointRange(first: 0xAC00, last: 0xD7A3, rule: .hangulSyllable, group: "Hangul Syllables", age: age("2.0"))
        ]
        let header = CatalogFormat.Header(unicodeVersion: "18.0.0", emojiVersion: "18.0", cldrVersion: "49")
        return SearchIndex(catalog: Catalog(contents: CatalogFormat.Contents(header: header, entries: entries, ranges: ranges)))
    }()

    private func strings(_ query: String, options: SearchOptions = SearchOptions()) -> [String] {
        Self.index.search(query, options: options).map(\.entry.string)
    }

    private func assertResults(_ query: String, _ expected: [String], options: SearchOptions = SearchOptions(), file: StaticString = #filePath, line: UInt = #line) {
        let actual = strings(query, options: options)
        XCTAssertEqual(actual.count, expected.count, "\(query): got \(actual.map(\.codePointDescription))", file: file, line: line)
        for (got, want) in zip(actual, expected) {
            XCTAssertTrue(got.isExactly(want), "\(query): got \(actual.map(\.codePointDescription)), want \(expected.map(\.codePointDescription))", file: file, line: line)
        }
    }

    // MARK: - Aliases and exact matches

    func testCuratedAliasOrderLeadsThenKeywordMatchesThenNameWords() {
        assertResults("arrow", [Self.rightArrow, Self.leftArrow, Self.bow, Self.rightArrowEmoji, Self.upRightArrow, Self.strokeArrow])
    }

    func testPunctuationAliases() {
        assertResults("->", [Self.rightArrow])
        assertResults("<-", [Self.leftArrow])
        assertResults("!=", [Self.notEqual])
    }

    func testSingleLetterPrefersTheCuratedAliasOverTheLetter() {
        assertResults("x", [Self.times, Self.letterX])
    }

    func testAliasIsCaseInsensitive() {
        assertResults("CMD", [Self.command])
        assertResults("Tick", [Self.check])
    }

    func testAliasPrefixAlreadyFindsTheEntry() {
        assertResults("cm", [Self.command])
    }

    func testExactNameOutranksExactKeyword() {
        assertResults("fire", [Self.fire, Self.fireEngine])
    }

    func testKeywordOnlyMatch() {
        assertResults("happy", [Self.grin])
    }

    func testOfficialNameKeyword() {
        assertResults("rightwards arrow", [Self.rightArrow, Self.strokeArrow])
    }

    func testHyphenatedNameMatchesSpacedQuery() {
        XCTAssertEqual(strings("up right").first, Self.upRightArrow)
        XCTAssertEqual(Self.index.search("up right").first?.tier, .prefix)
        XCTAssertEqual(Self.index.search("up-right arrow").first?.tier, .exact)
        XCTAssertEqual(Self.index.search("up right arrow").first?.tier, .exact)
    }

    func testAliasThenWholeWordInName() {
        assertResults("heart", [Self.redHeart, Self.textHeart])
    }

    func testSkinToneVariantsStayOutOfWordResults() {
        assertResults("thumbs up", [Self.thumbsUp])
        assertResults("medium skin tone", [])
    }

    func testCanonicallyEquivalentEntriesAreSeparate() {
        assertResults("ohm", [Self.ohm])
        assertResults("omega", [Self.omega])
        XCTAssertEqual(Self.index.search("\u{2126}").first?.entry.name, "ohm sign")
        XCTAssertEqual(Self.index.search("\u{3A9}").first?.entry.name, "greek capital letter omega")
    }

    func testBlockNameFindsItsCharacters() {
        // Both characters of the Dingbats block match the block name as a
        // whole word; the aliased check mark is more prominent.
        assertResults("dingbats", [Self.check, Self.textHeart])
        XCTAssertEqual(Self.index.search("dingbats").map(\.tier), [.prefix, .prefix])
    }

    func testBlockNameIsNotMatchedInsideAWord() {
        // `motio` occurs only inside the group name "Smileys & Emotion".
        assertResults("motio", [])
    }

    func testBlockNameFragmentsAreNotSearchWords() {
        // "Latin-1 Supplement" must not attach its characters to the query 1.
        XCTAssertFalse(strings("1").contains { $0.isExactly(Self.noBreakSpace) || $0.isExactly(Self.eAcute) })
    }

    // MARK: - Related words

    func testRelatedWordListsItsItemsInCuratedOrder() {
        assertResults("urgent", [Self.policeLight, Self.exclamation])
        XCTAssertEqual(Self.index.search("urgent").map(\.tier), [.exact, .exact])
        assertResults("Important", [Self.exclamation])
    }

    func testRelatedWordFollowsEverythingTheWordNames() {
        // `flame` is a keyword of the fire and only a related word of the
        // fire engine.
        assertResults("flame", [Self.fire, Self.fireEngine])
    }

    func testRelatedWordIsFoundWhileTyped() {
        let hits = Self.index.search("urg")
        XCTAssertEqual(Set(hits.map(\.entry.string)), [Self.policeLight, Self.exclamation])
        XCTAssertEqual(Set(hits.map(\.tier)), [.prefix])
    }

    func testRelatedWordIsNotMatchedInsideAWord() {
        assertResults("rgent", [])
        assertResults("portant", [])
    }

    func testRelatedWordJoinsOtherWordsOfTheQuery() {
        // Both words match the police light, one by keyword and one as a
        // related word. The exclamation mark answers only `urgent`.
        assertResults("urgent police", [Self.policeLight, Self.exclamation])
        XCTAssertEqual(Self.index.search("urgent police").map(\.tier), [.prefix, .someWords])
    }

    // MARK: - Other readings of the query

    func testFillerWordsAreDroppedWhenNothingMatchesExactly() {
        assertResults("heart emoji", [Self.redHeart, Self.textHeart])
        assertResults("cmd symbol", [Self.command])
        assertResults("symbol for infinity", [Self.infinity])
        // A filler word on its own is still a word.
        assertResults("key", [Self.command])
    }

    func testPluralReadsAsItsSingular() {
        assertResults("fires", [Self.fire, Self.fireEngine])
        assertResults("hearts", [Self.redHeart, Self.textHeart])
        assertResults("grinning faces", [Self.grin])
        XCTAssertEqual(Self.index.search("fires").first?.tier, .exact)
    }

    func testPluralOfABlockNameReadsAsItsSingularFirst() {
        // `arrows` names nothing; read as `arrow` it finds the curated
        // arrows first, then the keyword matches, then the rest of the
        // Arrows block.
        assertResults("arrows", [Self.rightArrow, Self.leftArrow, Self.bow, Self.rightArrowEmoji, Self.upRightArrow, Self.strokeArrow])
    }

    func testReducedWordMustNameSomethingExactly() {
        // `grinnings` would reduce to `grinning`, which is only part of a
        // name; a near miss is all that is left.
        XCTAssertEqual(Self.index.search("grinnings").map(\.tier), [.fuzzy])
    }

    func testSomeWordsShowWhatEachWordFinds() {
        // Nothing matches both words. The fire, named by the later word,
        // leads; the urgent items follow in their curated order.
        assertResults("urgent fire", [Self.fire, Self.fireEngine, Self.policeLight, Self.exclamation])
        XCTAssertEqual(Set(Self.index.search("urgent fire").map(\.tier)), [.someWords])
    }

    func testSomeWordsComeAfterMatchesOfEveryWord() {
        XCTAssertEqual(strings("up right"), [Self.upRightArrow, Self.rightArrow, Self.rightArrowEmoji, Self.thumbsUp])
        XCTAssertEqual(Self.index.search("up right").map(\.tier), [.prefix, .someWords, .someWords, .someWords])
    }

    // MARK: - Code points

    func testExplicitCodePointFindsExactlyThatCharacter() {
        assertResults("U+0078", [Self.letterX])
        assertResults("u+2192", [Self.rightArrow])
        XCTAssertEqual(Self.index.search("U+2192").first?.tier, .codePoint)
    }

    func testExplicitSequenceIsParsedAsAWhole() {
        assertResults("U+1F44D U+1F3FD", [Self.thumbsUpMedium])
        assertResults("U+2764, U+FE0F", [Self.redHeart])
    }

    func testBareHexIsASecondaryReading() {
        assertResults("2192", [Self.rightArrow])
        XCTAssertEqual(Self.index.search("2192").first?.tier, .bareCodePoint)
        // `face` is a keyword first and U+FACE second.
        assertResults("face", [Self.grin, Self.ideographFace])
        // `100` is the hundred-points keyword first and U+0100 second.
        assertResults("100", [Self.hundred, Self.aMacron])
    }

    func testBareHexInAnAlgorithmicRangeIsSynthesised() {
        let hits = Self.index.search("cafe")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.entry.string, "\u{CAFE}")
        XCTAssertNil(hits.first?.index)
        XCTAssertTrue(hits.first?.entry.name.hasPrefix("hangul syllable") ?? false)
    }

    func testInvalidCodePointsAreRejectedGracefully() {
        assertResults("U+D800", [])
        assertResults("U+110000", [])
        assertResults("U+ZZZZ", [])
        assertResults("U+0007", [])
        // Code point notation is never read as words: `x` names the
        // multiplication sign, but this query is not about it.
        assertResults("U+D800 x", [])
    }

    // MARK: - Literals

    func testPastedCharacterFindsItself() {
        assertResults(Self.rightArrow, [Self.rightArrow])
        XCTAssertEqual(Self.index.search(Self.rightArrow).first?.tier, .literal)
        assertResults(Self.eAcute, [Self.eAcute])
    }

    func testPastedVariantAndSequenceAreFoundExactly() {
        // A pasted sequence that is itself an entry is not taken apart.
        assertResults(Self.thumbsUpMedium, [Self.thumbsUpMedium])
        assertResults(Self.redHeart, [Self.redHeart])
        assertResults(Self.textHeart, [Self.textHeart])
    }

    func testPastedUnknownSequenceFallsBackToItsScalars() {
        // x followed by a combining acute is not an entry; its base letter is.
        assertResults("\u{2192}\u{301}", [Self.rightArrow])
    }

    func testSeveralPastedCharactersKeepTheirOrder() {
        assertResults(Self.leftArrow + Self.rightArrow, [Self.leftArrow, Self.rightArrow])
    }

    func testPastedIdeographResolvesThroughItsRange() {
        let hits = Self.index.search("\u{4E2D}")
        XCTAssertEqual(hits.map(\.entry.name), ["cjk unified ideograph-4e2d"])
    }

    func testAsciiPunctuationFallsBackToTheCharacterItself() {
        assertResults("#", [Self.numberSign])
        assertResults("+", [Self.plus])
    }

    func testSymbolicKeywordWithDigits() {
        // `+1` is a keyword of thumbs up; `1` also starts the `100` keyword.
        assertResults("+1", [Self.thumbsUp, Self.hundred])
    }

    // MARK: - Substring and fuzzy

    func testSubstringTier() {
        let hits = Self.index.search("finit")
        XCTAssertEqual(hits.map(\.entry.string), [Self.infinity])
        XCTAssertEqual(hits.first?.tier, .substring)
    }

    func testFuzzyOnlyForGenuineNearMisses() {
        let hits = Self.index.search("infinty")
        XCTAssertEqual(hits.map(\.entry.string), [Self.infinity])
        XCTAssertEqual(hits.first?.tier, .fuzzy)
        // Three letters are too few to correct.
        assertResults("arw", [])
    }

    func testAccentsInTheQueryAreFolded() {
        let hits = Self.index.search("Infinit\u{E9}")
        XCTAssertEqual(hits.map(\.entry.string), [Self.infinity])
    }

    // MARK: - Ordering rules

    func testFavouriteBreaksTiesInsideATierOnly() {
        var options = SearchOptions()
        options.favourites = [Self.upRightArrow.exact, Self.strokeArrow.exact]
        // The favourite leads the keyword matches but stays behind the alias
        // matches, and the name-word match stays in its later tier.
        assertResults("arrow", [Self.rightArrow, Self.leftArrow, Self.upRightArrow, Self.bow, Self.rightArrowEmoji, Self.strokeArrow], options: options)
    }

    func testRecentRanksBelowFavouriteInATie() {
        var options = SearchOptions()
        options.recents = [Self.rightArrowEmoji.exact]
        options.favourites = [Self.upRightArrow.exact]
        assertResults("arrow", [Self.rightArrow, Self.leftArrow, Self.upRightArrow, Self.rightArrowEmoji, Self.bow, Self.strokeArrow], options: options)
    }

    func testLimitAndEmptyQueries() {
        var options = SearchOptions()
        options.limit = 2
        assertResults("arrow", [Self.rightArrow, Self.leftArrow], options: options)
        assertResults("", [])
        assertResults("   ", [])
    }

    func testCancellationReturnsNothing() {
        let options = SearchOptions(isCancelled: { true })
        assertResults("arrow", [], options: options)
    }

    func testResultsAreDeterministic() {
        for query in ["arrow", "a", "e", "fire", "x", "latin"] {
            XCTAssertEqual(strings(query), strings(query), query)
        }
    }

    func testNoResult() {
        assertResults("zzzzqqq", [])
    }

    func testHundredsOfWordsMatchNothing() {
        // The per-word counter is a byte; a query this long must not wrap it
        // and let an entry through on its last word alone.
        assertResults(Array(repeating: "arrow", count: 256).joined(separator: " ") + " fire", [])
    }
}

final class QueryReadingsTests: XCTestCase {
    private func words(_ text: String) -> [[UInt8]] { SearchText.tokens(text) }
    private func text(_ tokens: [[UInt8]]) -> String { String(decoding: SearchText.canonical(tokens), as: UTF8.self) }
    private func bases(_ word: String) -> [String] { QueryReadings.baseForms(Array(word.utf8)).map { String(decoding: $0, as: UTF8.self) } }

    func testFillerWordsAreDroppedOnlyBesideOtherWords() {
        XCTAssertEqual(text(QueryReadings.significantWords(words("heart emoji"))), "heart")
        XCTAssertEqual(text(QueryReadings.significantWords(words("the symbol for infinity"))), "infinity")
        XCTAssertEqual(text(QueryReadings.significantWords(words("key"))), "key")
        XCTAssertEqual(text(QueryReadings.significantWords(words("emoji symbol"))), "emoji symbol")
    }

    func testBaseFormsOfRegularInflections() {
        XCTAssertTrue(bases("rockets").contains("rocket"))
        XCTAssertTrue(bases("parties").contains("party"))
        XCTAssertTrue(bases("boxes").contains("box"))
        XCTAssertTrue(bases("movies").contains("movie"))
        XCTAssertTrue(bases("approved").contains("approve"))
        XCTAssertTrue(bases("blocked").contains("block"))
        XCTAssertTrue(bases("stopped").contains("stop"))
        XCTAssertTrue(bases("worried").contains("worry"))
        XCTAssertTrue(bases("celebrating").contains("celebrate"))
        XCTAssertTrue(bases("running").contains("run"))
        XCTAssertTrue(bases("happier").contains("happy"))
        XCTAssertTrue(bases("happily").contains("happy"))
        XCTAssertTrue(bases("lovely").contains("love"))
        XCTAssertTrue(bases("opening").contains("open"))
        XCTAssertTrue(bases("cooking").contains("cook"))
        XCTAssertTrue(bases("snowing").contains("snow"))
    }

    func testShortStemsTakeBackTheirSilentE() {
        // `caring` is not a form of `car`, nor `rated` of `rat`.
        XCTAssertEqual(bases("caring"), ["care"])
        XCTAssertEqual(bases("rated"), ["rate"])
        XCTAssertEqual(bases("coding"), ["code"])
        XCTAssertTrue(bases("hopping").contains("hop"))
        XCTAssertFalse(bases("hoping").contains("hop"))
        // Only a consonant comes before a lost `e`.
        XCTAssertFalse(bases("being").contains("bee"))
        XCTAssertTrue(bases("seeing").contains("see"))
        XCTAssertTrue(bases("agreed").contains("agree"))
        XCTAssertTrue(bases("tied").contains("tie"))
    }

    func testPluralsOfFillerWordsStillReduce() {
        // Filler words are real words of the catalogue when they stand alone.
        XCTAssertTrue(bases("buttons").contains("button"))
        XCTAssertTrue(bases("marks").contains("mark"))
        XCTAssertTrue(bases("keys").contains("key"))
    }

    func testBaseFormsOfBritishSpellings() {
        XCTAssertTrue(bases("colour").contains("color"))
        XCTAssertTrue(bases("favourite").contains("favorite"))
        XCTAssertTrue(bases("centre").contains("center"))
        XCTAssertEqual(bases("grey"), ["gray"])
    }

    func testWordsThatAreNotInflectionsStayAlone() {
        XCTAssertEqual(bases("bus"), [])
        XCTAssertEqual(bases("glass"), [])
        XCTAssertEqual(bases("virus"), [])
        XCTAssertEqual(bases("caf\u{E9}s"), [])
        // A base form is never a filler word or too short to mean anything.
        XCTAssertFalse(bases("thing").contains("the"))
        XCTAssertEqual(bases("king"), [])
    }

    func testReadingsDropFillerWordsFirstThenReduceOneWordAtATime() {
        let readings = QueryReadings.alternatives(words("red hearts emoji"))
        XCTAssertEqual(readings.first, QueryReadings.Reading(tokens: words("red hearts"), matching: .prefix))
        XCTAssertTrue(readings.contains(QueryReadings.Reading(tokens: words("red heart"), matching: .whole)))
        XCTAssertTrue(readings.dropFirst().allSatisfy { $0.matching == .whole })
        XCTAssertEqual(QueryReadings.alternatives(words("one two three four five six seven")), [])
    }
}

final class SearchTextTests: XCTestCase {
    func testFoldLowercasesAndStripsDiacritics() {
        XCTAssertEqual(SearchText.fold("RIGHT Arrow"), "right arrow")
        XCTAssertEqual(SearchText.fold("Caf\u{E9}"), "cafe")
        XCTAssertEqual(SearchText.fold("\u{FF21}"), "a")
    }

    func testTokensSplitOnAnythingButLettersAndDigits() {
        func words(_ text: String) -> [String] { SearchText.tokens(text).map { String(decoding: $0, as: UTF8.self) } }
        XCTAssertEqual(words("up-right arrow"), ["up", "right", "arrow"])
        XCTAssertEqual(words("people & body/hand-fingers"), ["people", "body", "hand", "fingers"])
        XCTAssertEqual(words("+1"), ["1"])
        XCTAssertEqual(words("->"), [])
        XCTAssertEqual(words("\u{3B1}\u{3B2} \u{3B3}"), ["\u{3B1}\u{3B2}", "\u{3B3}"])
    }

    func testEditDistanceCountsTranspositionAsOne() {
        func distance(_ a: String, _ b: String, limit: Int = 3) -> Int {
            Array(b.utf8).withUnsafeBufferPointer { SearchText.editDistance(Array(a.utf8), $0, limit: limit) }
        }
        XCTAssertEqual(distance("arrow", "arrow"), 0)
        XCTAssertEqual(distance("arorw", "arrow"), 1)
        XCTAssertEqual(distance("arow", "arrow"), 1)
        XCTAssertEqual(distance("infinty", "infinity"), 1)
        XCTAssertEqual(distance("kitten", "sitting"), 3)
        XCTAssertGreaterThan(distance("abcdef", "uvwxyz", limit: 2), 2)
    }

    func testCodePointQueryParsing() {
        XCTAssertEqual(CodePointQuery.parse("U+2192"), CodePointQuery(string: "\u{2192}", isExplicit: true))
        XCTAssertEqual(CodePointQuery.parse("u+1f469 u+200d u+1f4bb"), CodePointQuery(string: "\u{1F469}\u{200D}\u{1F4BB}", isExplicit: true))
        XCTAssertEqual(CodePointQuery.parse("1F44D"), CodePointQuery(string: "\u{1F44D}", isExplicit: false))
        XCTAssertEqual(CodePointQuery.parse("U+2764,U+FE0F")?.string.unicodeScalars.count, 2)
        XCTAssertNil(CodePointQuery.parse("arrow"))
        XCTAssertNil(CodePointQuery.parse("U+D800"))
        XCTAssertNil(CodePointQuery.parse("U+110000"))
        XCTAssertNil(CodePointQuery.parse("U+2192 zz"))
        XCTAssertNil(CodePointQuery.parse("f"))
        XCTAssertNil(CodePointQuery.parse("1234567"))
    }

    func testCodePointNotationIsRecognisedEvenWhenInvalid() {
        XCTAssertTrue(CodePointQuery.isNotation("U+D800"))
        XCTAssertTrue(CodePointQuery.isNotation("arrow u+2192"))
        XCTAssertFalse(CodePointQuery.isNotation("2192"))
        XCTAssertFalse(CodePointQuery.isNotation("c++"))
        XCTAssertFalse(CodePointQuery.isNotation("menu+"))
    }
}
