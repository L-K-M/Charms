import Foundation

/// An explicitly saved, short replacement. Only metadata is normalized;
/// replacement text is kept scalar-for-scalar, including surrounding spaces.
public struct TextSnippet: Codable, Equatable, Sendable, Identifiable {
    public static let maximumTextUnits = InsertionPolicy.maximumUnitsPerEvent
    public static let maximumShortcutLength = 32
    public static let maximumNameUnits = 80

    public let id: UUID
    public let shortcut: String
    public let name: String
    public let text: String

    public init(id: UUID = UUID(), shortcut: String, name: String, text: String) throws {
        let bytes = Array(shortcut.utf8)
        func isLetter(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
        }
        guard let first = bytes.first, isLetter(first), bytes.count <= Self.maximumShortcutLength,
              bytes.allSatisfy({ isLetter($0) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) || $0 == UInt8(ascii: "-") }) else {
            throw SnippetError.invalidShortcut
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf16.count <= Self.maximumNameUnits,
              !name.unicodeScalars.contains(where: Self.isForbidden) else { throw SnippetError.invalidName }
        guard text.utf16.count <= Self.maximumTextUnits else { throw SnippetError.textTooLong }
        guard text.unicodeScalars.contains(where: { !$0.properties.isWhitespace && $0.properties.generalCategory != .format }),
              !text.unicodeScalars.contains(where: Self.isForbidden) else { throw SnippetError.invalidText }
        self.id = id
        self.shortcut = shortcut.lowercased()
        self.name = name
        self.text = text
    }

    func matchesShortcut(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.utf8.allSatisfy { $0 < 128 } && shortcut == query.lowercased()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.shortcut == rhs.shortcut && lhs.name == rhs.name && lhs.text.isExactly(rhs.text)
    }

    private enum CodingKeys: String, CodingKey { case id, shortcut, name, text }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: fields.decode(UUID.self, forKey: .id),
                      shortcut: fields.decode(String.self, forKey: .shortcut),
                      name: fields.decode(String.self, forKey: .name),
                      text: fields.decode(String.self, forKey: .text))
    }

    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: return true
        default: break
        }
        // Directional overrides can disguise the saved text in an editor.
        // Joiners, variation selectors and emoji tags remain valid payload.
        return scalar.value == 0x061C || (0x200E...0x200F).contains(scalar.value)
            || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
    }
}

public enum SnippetError: Error, LocalizedError {
    case invalidShortcut, invalidName, invalidText, textTooLong
    case duplicateShortcut, duplicateID, tooManySnippets, unsupportedSchema

    public var errorDescription: String? {
        switch self {
        case .invalidShortcut: return "Use 1–32 ASCII letters, digits or hyphens, starting with a letter. Leave out the :: prefix."
        case .invalidName: return "Enter a single-line name of up to 80 Unicode units, without control or directional formatting characters."
        case .invalidText: return "Enter visible, single-line text without tabs, control characters or directional overrides."
        case .textTooLong: return "Keep the replacement within \(TextSnippet.maximumTextUnits) UTF-16 units. Most characters use one; many emoji use more."
        case .duplicateShortcut: return "Another snippet already uses that shortcut. Choose a different one."
        case .duplicateID: return "Two saved snippets have the same identifier."
        case .tooManySnippets: return "You can save up to \(SnippetLibrary.maximumCount) snippets."
        case .unsupportedSchema: return "This snippets file needs a different version of Charms. It has not been changed."
        }
    }
}
