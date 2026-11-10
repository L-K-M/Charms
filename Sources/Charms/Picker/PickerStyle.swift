import SwiftUI

/// Ink and paper are intentionally opaque. A character must stay readable
/// regardless of the document underneath, also with Reduce Transparency on.
struct PickerPalette {
    let scheme: ColorScheme
    let contrast: ColorSchemeContrast

    static let vermilion = Color(red: 1, green: 0.44, blue: 0.30)
    static let paper = Color(red: 0.98, green: 0.965, blue: 0.925)
    static let ink = Color(red: 0.13, green: 0.18, blue: 0.15)
    static let tray = Color(red: 0.12, green: 0.16, blue: 0.14)
    static let chalk = Color(red: 0.94, green: 0.95, blue: 0.90)

    var shell: Color {
        scheme == .dark ? Color(red: 0.18, green: 0.22, blue: 0.20) : Color(red: 0.91, green: 0.91, blue: 0.87)
    }

    var label: Color { scheme == .dark ? Self.chalk : Self.ink }
    var secondary: Color { label.opacity(contrast == .increased ? 1 : 0.70) }
    var rule: Color { label.opacity(contrast == .increased ? 0.7 : 0.18) }
}

/// Four open corners, like registration marks around a printed specimen.
/// The marks do not scale with the glyph or imply editable handles.
struct ProofRegistration: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 7
        var path = Path()
        for (x, y, dx, dy) in [
            (rect.minX, rect.minY, length, length),
            (rect.maxX, rect.minY, -length, length),
            (rect.minX, rect.maxY, length, -length),
            (rect.maxX, rect.maxY, -length, -length)
        ] {
            path.move(to: CGPoint(x: x, y: y + dy))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx, y: y))
        }
        return path
    }
}

struct PickerSurfaceView: View {
    @ObservedObject var model: PickerViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: PickerPalette { PickerPalette(scheme: scheme, contrast: contrast) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                // A tiny composing tray: four sorts, one lifted out.
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Rectangle().frame(width: 4, height: 4)
                        Rectangle().frame(width: 4, height: 4).offset(y: -1)
                    }
                    HStack(spacing: 2) {
                        Rectangle().frame(width: 4, height: 4)
                        Rectangle().frame(width: 4, height: 4)
                    }
                }
                .foregroundStyle(scheme == .dark ? PickerPalette.vermilion : palette.label)
                Text("CHARMS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                Spacer()
                Text("IMPRESSION")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(palette.secondary)
            }
            .foregroundStyle(palette.label)
            .padding(.horizontal, 19)
            .frame(height: PickerViewModel.mastheadHeight)
            .accessibilityHidden(true)

            // AppKit's real text field is laid over this aperture. Keeping
            // its field editor preserves IME, Undo and ordinary query editing.
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.leading, 12)
                Spacer()
                Text("esc")
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                    .padding(.trailing, 10)
            }
            .foregroundStyle(palette.secondary)
            .frame(height: PickerViewModel.searchHeight - 6)
            .background(palette.label.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(model.isNavigating ? palette.rule : palette.label.opacity(0.5), lineWidth: contrast == .increased ? 2 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .accessibilityHidden(true)

            PickerProofView(model: model)
                .frame(height: PickerViewModel.proofHeight)

            PickerGridView(model: model)
                .frame(maxHeight: .infinity)
                .background(PickerPalette.tray)

            PickerFooterView(model: model)
                .frame(height: PickerViewModel.footerHeight)
                .background(PickerPalette.tray)
        }
        .background(palette.shell)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(palette.rule, lineWidth: contrast == .increased ? 2 : 0.5)
                .allowsHitTesting(false)
        }
    }
}
