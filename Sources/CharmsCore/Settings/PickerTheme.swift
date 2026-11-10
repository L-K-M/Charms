import Foundation

/// Visual theme for the picker. Its opaque color roles contain no UI types.
public enum PickerTheme: String, Codable, CaseIterable, Sendable {
    case impression
    case blueprint
    case plum
}

/// Which appearance the picker asks the system for. `.system` follows the
/// user's overall setting.
public enum PickerAppearance: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}
