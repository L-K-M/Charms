import XCTest
@testable import CharmsCore

final class PickerThemeColorTests: XCTestCase {
    func testAllThemeComponentsAreValidSRGB() {
        for theme in PickerTheme.allCases {
            let c = theme.colors
            for color in [c.paper, c.ink, c.tray, c.chalk, c.block, c.accent, c.proofAccent, c.lightShell, c.darkShell] {
                for component in [color.red, color.green, color.blue] {
                    XCTAssertTrue(component.isFinite && (0...1).contains(component), theme.rawValue)
                }
            }
        }
    }

    func testTextHasAtLeastAAContrastInEveryThemeAndAppearance() {
        for theme in PickerTheme.allCases {
            let c = theme.colors
            for (role, foreground, background) in [
                ("proof and selected block", c.ink, c.paper),
                ("tray actions", c.chalk, c.tray),
                ("unselected block", c.chalk, c.block),
                ("light search", c.ink, c.lightShell),
                ("dark search", c.chalk, c.darkShell),
                ("copy-only action", c.accent, c.tray),
                ("proof accent", c.proofAccent, c.paper)
            ] {
                XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5, "\(theme.rawValue): \(role)")
            }
        }
    }

    func testSecondaryTextRetainsAAContrast() {
        for theme in PickerTheme.allCases {
            let c = theme.colors
            for (foreground, background, opacity) in [
                (c.ink, c.paper, 0.70),
                (c.ink, c.lightShell, 0.70),
                (c.chalk, c.darkShell, 0.70),
                (c.chalk, c.tray, 0.75)
            ] {
                let blended = (
                    foreground.red * opacity + background.red * (1 - opacity),
                    foreground.green * opacity + background.green * (1 - opacity),
                    foreground.blue * opacity + background.blue * (1 - opacity)
                )
                XCTAssertGreaterThanOrEqual(ratio(luminance(blended), luminance(background)), 4.5, theme.rawValue)
            }
        }
    }

    func testSelectionAccentContrastsWithTrayAndBlocks() {
        for theme in PickerTheme.allCases {
            let c = theme.colors
            XCTAssertGreaterThanOrEqual(contrast(c.accent, c.tray), 3, theme.rawValue)
            XCTAssertGreaterThanOrEqual(contrast(c.accent, c.block), 3, theme.rawValue)
        }
    }

    private func contrast(_ a: PickerTheme.RGB, _ b: PickerTheme.RGB) -> Double {
        ratio(luminance(a), luminance(b))
    }

    private func ratio(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ rgb: PickerTheme.RGB) -> Double {
        luminance((rgb.red, rgb.green, rgb.blue))
    }

    // WCAG's sRGB transfer function. Opacity is composited before measuring.
    private func luminance(_ rgb: (Double, Double, Double)) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }
}
