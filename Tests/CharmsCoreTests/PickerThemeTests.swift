import XCTest
import Foundation
@testable import CharmsCore

/// Regression coverage for the picker theme and appearance preferences.
/// Both fields are cosmetic, so a bad value must never take the rest of the
/// stored document with it.
final class PickerThemeTests: XCTestCase {
    func testDefaults() {
        let preferences = Preferences()
        XCTAssertEqual(preferences.pickerTheme, .impression)
        XCTAssertEqual(preferences.pickerAppearance, .system)
    }

    func testInitializerParametersSetBothFields() {
        let preferences = Preferences(pickerTheme: .plum, pickerAppearance: .dark)
        XCTAssertEqual(preferences.pickerTheme, .plum)
        XCTAssertEqual(preferences.pickerAppearance, .dark)
    }

    func testEveryThemeAndAppearanceCombinationRoundTrips() {
        for theme in PickerTheme.allCases {
            for appearance in PickerAppearance.allCases {
                let preferences = Preferences(pickerTheme: theme, pickerAppearance: appearance)
                XCTAssertEqual(Preferences.decoded(from: preferences.encoded()), preferences,
                               "\(theme)/\(appearance) did not survive encoding")
            }
        }
    }

    func testOldPreferencesWithoutTheNewFieldsKeepTheirExistingSettings() throws {
        // Build the document an older build would have written: every field
        // except the two new ones.
        var source = Preferences()
        source.shortcut = KeyCombo(keyCode: 40, modifiers: [.control, .option])
        source.skinTone = .dark
        source.typedTriggerEnabled = true
        source.triggerExclusions = ["a.b"]
        source.pasteApplications = ["c.d"]
        source.shortcutPassThrough = ["e.f"]
        source.fieldAccessApplications = ["f.g"]
        source.fieldAccessDeclined = ["h.i"]
        source.hasCompletedOnboarding = true
        var object = try JSONSerialization.jsonObject(with: source.encoded()) as? [String: Any] ?? [:]
        object.removeValue(forKey: "pickerTheme")
        object.removeValue(forKey: "pickerAppearance")
        let data = try JSONSerialization.data(withJSONObject: object)
        let preferences = Preferences.decoded(from: data)
        XCTAssertEqual(preferences.shortcut, KeyCombo(keyCode: 40, modifiers: [.control, .option]))
        XCTAssertEqual(preferences.skinTone, .dark)
        XCTAssertTrue(preferences.typedTriggerEnabled)
        XCTAssertEqual(preferences.triggerExclusions, ["a.b"])
        XCTAssertEqual(preferences.pasteApplications, ["c.d"])
        XCTAssertEqual(preferences.shortcutPassThrough, ["e.f"])
        XCTAssertEqual(preferences.fieldAccessApplications, ["f.g"])
        XCTAssertEqual(preferences.fieldAccessDeclined, ["h.i"])
        XCTAssertTrue(preferences.hasCompletedOnboarding)
        XCTAssertEqual(preferences.pickerTheme, .impression, "an old document gets the default theme")
        XCTAssertEqual(preferences.pickerAppearance, .system, "an old document gets the default appearance")
    }

    func testUnknownThemeAndAppearanceFallBackToDefaultsIndependently() {
        let data = Data(#"{"pickerTheme":"chartreuse","pickerAppearance":"sepia","typedTriggerEnabled":true,"skinTone":"dark"}"#.utf8)
        let preferences = Preferences.decoded(from: data)
        XCTAssertEqual(preferences.pickerTheme, .impression)
        XCTAssertEqual(preferences.pickerAppearance, .system)
        XCTAssertTrue(preferences.typedTriggerEnabled, "the other fields survive an unknown theme")
        XCTAssertEqual(preferences.skinTone, .dark, "the other fields survive an unknown appearance")
    }

    func testUnknownThemeDoesNotAffectAValidAppearance() {
        let data = Data(#"{"pickerTheme":"chartreuse","pickerAppearance":"dark","typedTriggerEnabled":true}"#.utf8)
        let preferences = Preferences.decoded(from: data)
        XCTAssertEqual(preferences.pickerTheme, .impression)
        XCTAssertEqual(preferences.pickerAppearance, .dark)
        XCTAssertTrue(preferences.typedTriggerEnabled)
    }

    func testUnknownAppearanceDoesNotAffectAValidTheme() {
        let data = Data(#"{"pickerTheme":"plum","pickerAppearance":"sepia","typedTriggerEnabled":true}"#.utf8)
        let preferences = Preferences.decoded(from: data)
        XCTAssertEqual(preferences.pickerTheme, .plum)
        XCTAssertEqual(preferences.pickerAppearance, .system)
        XCTAssertTrue(preferences.typedTriggerEnabled)
    }

    func testWrongTypesFallBackToDefaultsIndependently() {
        let data = Data(#"{"pickerTheme":42,"pickerAppearance":["dark"],"typedTriggerEnabled":true,"skinTone":"dark"}"#.utf8)
        let preferences = Preferences.decoded(from: data)
        XCTAssertEqual(preferences.pickerTheme, .impression)
        XCTAssertEqual(preferences.pickerAppearance, .system)
        XCTAssertTrue(preferences.typedTriggerEnabled)
        XCTAssertEqual(preferences.skinTone, .dark)
    }

    func testNullValuesFallBackToDefaultsIndependently() {
        let data = Data(#"{"pickerTheme":null,"pickerAppearance":null,"typedTriggerEnabled":true,"skinTone":"dark"}"#.utf8)
        let preferences = Preferences.decoded(from: data)
        XCTAssertEqual(preferences.pickerTheme, .impression)
        XCTAssertEqual(preferences.pickerAppearance, .system)
        XCTAssertTrue(preferences.typedTriggerEnabled)
        XCTAssertEqual(preferences.skinTone, .dark)
    }

    func testUnknownFutureFieldsAreTolerated() {
        let data = Data(#"{"pickerTheme":"plum","pickerAppearance":"light","typedTriggerEnabled":true,"futureSetting":{"nested":[1,2,3]},"anotherFuture":true,"futureList":["x","y"]}"#.utf8)
        let preferences = Preferences.decoded(from: data)
        XCTAssertEqual(preferences.pickerTheme, .plum)
        XCTAssertEqual(preferences.pickerAppearance, .light)
        XCTAssertTrue(preferences.typedTriggerEnabled)
        XCTAssertEqual(preferences.skinTone, .none)
    }

    func testAllThemeCasesAreCovered() {
        XCTAssertEqual(PickerTheme.allCases, [.impression, .blueprint, .plum])
        XCTAssertEqual(PickerAppearance.allCases, [.system, .light, .dark])
    }
}
