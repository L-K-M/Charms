import CharmsCore
import SwiftUI

/// Theme choices live here, never between a character and its destination.
struct AppearanceSettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @StateObject private var specimen = Self.makeSpecimen()

    private var palette: PickerPalette {
        PickerPalette(
            theme: preferences.value.pickerTheme,
            scheme: preferences.value.pickerAppearance.colorScheme(system: systemScheme),
            contrast: contrast
        )
    }

    var body: some View {
        Form {
            Section("Picker appearance") {
                Picker("Appearance", selection: Binding(
                    get: { preferences.value.pickerAppearance },
                    set: { appearance in preferences.update { $0.pickerAppearance = appearance } }
                )) {
                    Text("System").tag(PickerAppearance.system)
                    Text("Light").tag(PickerAppearance.light)
                    Text("Dark").tag(PickerAppearance.dark)
                }
                .pickerStyle(.segmented)

                Picker("Theme", selection: Binding(
                    get: { preferences.value.pickerTheme },
                    set: { theme in preferences.update { $0.pickerTheme = theme } }
                )) {
                    Text("Impression · warm paper, green tray, vermilion").tag(PickerTheme.impression)
                    Text("Blueprint · cool paper, navy tray, cyan").tag(PickerTheme.blueprint)
                    Text("Plum · rose paper, plum tray, apricot").tag(PickerTheme.plum)
                }
                .pickerStyle(.radioGroup)

                Text("Changes take effect immediately and are saved automatically. System follows your Mac’s light or dark appearance. Settings always follow macOS.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Preview") {
                VStack(spacing: 0) {
                    HStack {
                        Text("CHARMS").tracking(2)
                        Spacer()
                        Text("Aa → Bb")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.label)
                    .padding(12)
                    .background(palette.shell)

                    // This is the same proof component the picker uses, with
                    // a fixed example, not a query or a document excerpt.
                    PickerProofView(model: specimen)
                        .frame(height: PickerViewModel.proofHeight)
                        .background(palette.shell)
                    HStack(spacing: 6) {
                        ForEach(Array(specimen.sections[0].items.enumerated()), id: \.offset) { index, item in
                            PickerCell(item: item, isSelected: index == 0, isNavigating: false, isHovered: false, isPressed: false)
                                .background {
                                    if index == 0 {
                                        RoundedRectangle(cornerRadius: 7).fill(palette.accent).padding(-2)
                                    }
                                }
                        }
                        Spacer()
                    }
                    .font(.system(size: 24))
                    .padding(20)
                    .background(palette.tray)
                }
                .environment(\.pickerPalette, palette)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 432)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Theme preview: rightwards arrow on paper above the composing tray")

                Text("Every theme keeps the exact Unicode proof, keyboard controls and opaque surfaces. Reduce Motion and Increase Contrast are respected in all appearances.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Restore Default Appearance") {
                    preferences.update {
                        $0.pickerTheme = .impression
                        $0.pickerAppearance = .system
                    }
                }
                .disabled(preferences.value.pickerTheme == .impression && preferences.value.pickerAppearance == .system)
            }
        }
        .formStyle(.grouped)
    }

    private static func makeSpecimen() -> PickerViewModel {
        let model = PickerViewModel()
        model.sections = [PickerSection(kind: .results, items: [
            PickerItem(string: "→", name: "Rightwards arrow", isEmoji: false, isFavourite: false, variantBaseIndex: nil),
            PickerItem(string: "←", name: "Leftwards arrow", isEmoji: false, isFavourite: false, variantBaseIndex: nil),
            PickerItem(string: "↗", name: "North east arrow", isEmoji: false, isFavourite: false, variantBaseIndex: nil)
        ])]
        model.selection = GridPosition(section: 0, index: 0)
        return model
    }
}
