import Foundation

/// Other ways to read a query whose words, as typed, name nothing exactly.
///
/// People search the way they talk: `heart emoji`, `command key`, `symbol
/// for infinity`, `rockets`, `approved`. The catalogue's names, keywords
/// and curated words are mostly bare singular nouns and base verbs, so those
/// queries used to find nothing or only fragments. A reading writes two
/// words as one (`key board`), drops filler words or reduces one word to a
/// base form; the search engine tries the
/// readings only when the typed query has no exact match, so a word the
/// catalogue does know, such as `glasses` or `news`, is never second-guessed.
///
/// The rules are deliberately small and purely English. A reading that
/// produces a word the catalogue does not know simply finds nothing.
enum QueryReadings {
    struct Reading: Equatable, Sendable {
        enum Matching: Sendable {
            /// The last word may still be a prefix, as in the typed query.
            case prefix
            /// Every word must be whole, and the reading counts only if it
            /// names something exactly. A reduced form such as `approv` is
            /// not a prefix worth completing, and a base form that is merely
            /// one word of a longer name is too weak a reason to show
            /// anything.
            case whole
        }

        let tokens: [[UInt8]]
        let matching: Matching

        /// The same words, all of them whole.
        var whole: Reading { Reading(tokens: tokens, matching: .whole) }
    }

    /// Words that describe what kind of thing is wanted rather than which
    /// one. They are dropped only when other words remain, so `key` alone
    /// still finds the key. `a` is not one of them: `letter a` means the
    /// letter.
    static let fillerWords: Set<[UInt8]> = Set([
        "emoji", "emojis", "emoticon", "emoticons", "smiley", "symbol", "symbols", "sign", "signs",
        "icon", "icons", "character", "characters", "char", "glyph", "glyphs", "key", "keys",
        "mark", "marks", "button", "buttons", "logo"
    ].map { Array($0.utf8) }).union(stopWords)

    /// Grammatical words, which are filler too but never a base form:
    /// `thing` is not a form of `the`.
    static let stopWords: Set<[UInt8]> = Set(["an", "the", "of", "for", "to", "with", "my"].map { Array($0.utf8) })

    /// The longest query that is rewritten; longer ones are sentences, not
    /// searches.
    static let maximumWords = 6
    /// Shorter words are left alone: `bus`, `gas` and `yes` are not plurals.
    static let minimumInflectedLength = 4
    /// A base form shorter than this is too ambiguous to look up.
    static let minimumBaseLength = 3
    /// Words are written as one only when each has at least this many
    /// letters: `a b` is two letters, not `ab`.
    static let minimumJoinedPartLength = 2

    /// The query's words without filler words, or all of them when nothing
    /// else would remain.
    static func significantWords(_ tokens: [[UInt8]]) -> [[UInt8]] {
        let kept = tokens.filter { !fillerWords.contains($0) }
        return kept.isEmpty ? tokens : kept
    }

    /// Two neighbouring words written as one, as typed or in a base form:
    /// `key board`, `cup cakes`. These readings come before the others
    /// because they change no letter, and the words they join may be
    /// filler words (`key`) or words that name other things (`rain`,
    /// `bow`), which the other readings would read apart: `key board`
    /// would show boards and `rain bow` bows, ahead of the keyboard and
    /// the rainbow that only substrings of the two words had found.
    static func joined(_ tokens: [[UInt8]]) -> [Reading] {
        guard tokens.count > 1, tokens.count <= maximumWords else { return [] }
        var readings: [Reading] = []
        for position in tokens.indices.dropLast() {
            let first = tokens[position]
            let second = tokens[position + 1]
            guard first.count >= minimumJoinedPartLength, second.count >= minimumJoinedPartLength else { continue }
            var joined = tokens
            joined.replaceSubrange(position...(position + 1), with: [first + second])
            readings.append(Reading(tokens: joined, matching: .whole))
            for base in baseForms(first + second) {
                joined[position] = base
                readings.append(Reading(tokens: joined, matching: .whole))
            }
        }
        return readings
    }

    /// Alternative readings, most faithful first: without filler words, then
    /// with one word at a time reduced to each of its base forms.
    static func alternatives(_ tokens: [[UInt8]]) -> [Reading] {
        guard !tokens.isEmpty, tokens.count <= maximumWords else { return [] }
        var readings: [Reading] = []
        let significant = significantWords(tokens)
        if significant != tokens {
            readings.append(Reading(tokens: significant, matching: .prefix))
        }
        for (position, token) in significant.enumerated() {
            for base in baseForms(token) {
                var replaced = significant
                replaced[position] = base
                let reading = Reading(tokens: replaced, matching: .whole)
                if !readings.contains(reading) {
                    readings.append(reading)
                }
            }
        }
        return readings
    }

    /// Candidate base forms of an English word: singulars of plurals, bare
    /// verbs of past and present participles, the plain adjective of a
    /// comparative or adverb, and the American spelling of a British one.
    /// Several candidates are offered where English is irregular (`approved`
    /// may be `approve` or `approv`); the index decides which exist.
    static func baseForms(_ token: [UInt8]) -> [[UInt8]] {
        guard token.count >= minimumInflectedLength, token.allSatisfy({ $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "z") }) else {
            return []
        }
        let word = String(decoding: token, as: UTF8.self)
        var forms: [String] = []

        func strip(_ suffix: String, add: String = "") {
            guard word.hasSuffix(suffix) else { return }
            let stem = String(word.dropLast(suffix.count))
            forms.append(stem + add)
        }
        /// The bare verb of an -ed or -ing form. A one-syllable stem ending
        /// in consonant, vowel, consonant lost a silent `e`, since English
        /// would have doubled the consonant otherwise: `caring` is `care`,
        /// not `car`, and `rated` is `rate`, not `rat` (but `hopping` is
        /// `hop`). Only a consonant can come before a lost `e`: `being` is
        /// not `bee`. An -ed form may simply have added `d` (`agreed`).
        func verbStem(_ suffix: String) {
            guard word.hasSuffix(suffix) else { return }
            let stem = Array(word.dropLast(suffix.count).utf8)
            let withE = suffix == "ed" ? String(word.dropLast()) : String(decoding: stem, as: UTF8.self) + "e"
            if !isShortSyllable(stem) {
                forms.append(String(decoding: stem, as: UTF8.self))
            }
            if suffix == "ed" || stem.last.map({ !isVowel($0) }) == true {
                forms.append(withE)
            }
        }
        /// `stopped` → `stop`, `running` → `run`: a doubled final consonant
        /// before the suffix.
        func undouble(_ suffix: String) {
            guard word.hasSuffix(suffix) else { return }
            let stem = Array(word.dropLast(suffix.count).utf8)
            guard stem.count >= 3, stem[stem.count - 1] == stem[stem.count - 2], !isVowel(stem[stem.count - 1]) else { return }
            forms.append(String(decoding: stem.dropLast(), as: UTF8.self))
        }

        // Plurals and third-person verbs.
        if word.hasSuffix("ies") {
            strip("ies", add: "y")
        } else if word.hasSuffix("es"), ["s", "x", "z", "ch", "sh", "o"].contains(where: { word.dropLast(2).hasSuffix($0) }) {
            strip("es")
        }
        if word.hasSuffix("s"), !["ss", "us", "is"].contains(where: { word.hasSuffix($0) }) {
            strip("s")
        }

        // Past tense and participles.
        if word.hasSuffix("ied") {
            // `worried` is `worry`; `tied` is `tie`.
            strip("ied", add: "y")
            strip("d")
        } else if word.hasSuffix("ed") {
            verbStem("ed")
            undouble("ed")
        }
        if word.hasSuffix("ing") {
            verbStem("ing")
            undouble("ing")
        }

        // Comparatives, superlatives and adverbs of -y adjectives.
        strip("ier", add: "y")
        strip("iest", add: "y")
        if word.hasSuffix("ily") {
            strip("ily", add: "y")
        } else if word.count >= 6 {
            strip("ly")
        }

        // British spellings: colour, favourite, centre, grey.
        if word.count >= 6, word.contains("our") {
            forms.append(word.replacingOccurrences(of: "our", with: "or"))
        }
        if word.hasSuffix("tre") {
            strip("tre", add: "ter")
        }
        if word == "grey" {
            forms.append("gray")
        }

        var seen: Set<String> = [word]
        return forms.compactMap { form in
            let bytes = Array(form.utf8)
            guard bytes.count >= minimumBaseLength, !stopWords.contains(bytes), seen.insert(form).inserted else { return nil }
            return bytes
        }
    }

    private static func isVowel(_ byte: UInt8) -> Bool {
        [UInt8(ascii: "a"), UInt8(ascii: "e"), UInt8(ascii: "i"), UInt8(ascii: "o"), UInt8(ascii: "u")].contains(byte)
    }

    /// One vowel, ending consonant-vowel-consonant, as in `car`, `rat` or
    /// `shin`. A final w, x or y never doubles, so `snow` and `fix` are not.
    private static func isShortSyllable(_ stem: [UInt8]) -> Bool {
        guard stem.count >= 3, let last = stem.last, !isVowel(last),
              ![UInt8(ascii: "w"), UInt8(ascii: "x"), UInt8(ascii: "y")].contains(last),
              isVowel(stem[stem.count - 2]), !isVowel(stem[stem.count - 3]) else { return false }
        return stem.filter(isVowel).count == 1
    }
}
