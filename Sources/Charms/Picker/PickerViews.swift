import CharmsCore
import SwiftUI

/// Reports the selected cell's frame so a menu opened from the keyboard can
/// appear next to it.
private struct SelectedCellFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// The composing tray. Position identities keep search updates from leaving
/// stale characters in cells; the proof above uses exact string identity.
struct PickerGridView: View {
    @ObservedObject var model: PickerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.pickerPalette) private var palette
    @Namespace private var selectionSaddle

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(PickerViewModel.cellSize), spacing: PickerViewModel.cellSpacing), count: PickerViewModel.columns)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        sectionView(section, index: sectionIndex)
                    }
                    if model.isLoading {
                        message("Loading characters…")
                    } else if !model.isQueryEmpty, !model.hasItems {
                        message("No matches. Keep looking.")
                    }
                }
                .padding(PickerViewModel.padding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onChange(of: model.selection) { _, position in
                guard let position else { return }
                proxy.scrollTo(position, anchor: nil)
            }
            .onPreferenceChange(SelectedCellFrameKey.self) { frame in
                model.selectedCellFrame = frame
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1)
        }
    }

    private func sectionView(_ section: PickerSection, index sectionIndex: Int) -> some View {
        let heading = section.kind == .results && section.items.contains(where: \.isSnippet) ? "RESULTS" : title(for: section.kind)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(heading)
                    .tracking(1.4)
                Spacer()
                Text(section.items.isEmpty ? "" : String(format: "%02d", section.items.count))
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(palette.chalk.opacity(contrast == .increased ? 1 : 0.75))
            .frame(height: PickerViewModel.sectionHeadingHeight)
            .accessibilityAddTraits(.isHeader)

            if section.items.isEmpty, let hint = emptyHint(for: section.kind) {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.chalk.opacity(contrast == .increased ? 1 : 0.75))
                    .frame(height: PickerViewModel.cellSize, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: PickerViewModel.cellSpacing) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { itemIndex, item in
                        cell(item, at: GridPosition(section: sectionIndex, index: itemIndex))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(heading)
            }
        }
        .padding(.top, sectionIndex == 0 ? 0 : 4)
    }

    private func cell(_ item: PickerItem, at position: GridPosition) -> some View {
        let isSelected = model.selection == position
        return PickerCell(
            item: item,
            isSelected: isSelected,
            isNavigating: model.isNavigating,
            isHovered: model.hover == position,
            isPressed: model.pressedItem?.id == item.id
        )
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7)
                    .fill(palette.accent)
                    .padding(-2)
                    .matchedGeometryEffect(id: "selection", in: selectionSaddle)
                    .animation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.84), value: model.selection)
                GeometryReader { geometry in
                    Color.clear.preference(key: SelectedCellFrameKey.self, value: geometry.frame(in: .global))
                }
            }
        }
        .id(position)
        .contentShape(Rectangle())
        .onTapGesture { model.onActivate?(position) }
        // A resting mouse cannot change the proof or what Return inserts.
        .onHover { inside in
            if inside {
                model.hover = position
            } else if model.hover == position {
                model.hover = nil
            }
        }
        .contextMenu { menu(model.menuActions?(position) ?? []) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.snippetShortcut.map { "Text snippet ::\($0). \(item.string)" } ?? item.codePoints)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.onActivate?(position) }
        .help("\(item.name)\n\(item.isSnippet ? item.string : item.codePoints)")
    }

    private func menu(_ actions: [PickerMenuAction]) -> some View {
        ForEach(actions) { action in
            if action.isSeparator {
                Divider()
            } else if !action.children.isEmpty {
                Menu(action.title) {
                    ForEach(action.children) { child in
                        Button(child.title) { child.perform?() }.disabled(!child.isEnabled)
                    }
                }
            } else {
                Button(action.title) { action.perform?() }.disabled(!action.isEnabled)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(palette.chalk)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
    }

    private func title(for kind: PickerSection.Kind) -> String {
        switch kind {
        case .favourites: return "FAVOURITES"
        case .recents: return "RECENT IMPRESSIONS"
        case .results: return "CHARACTERS"
        }
    }

    private func emptyHint(for kind: PickerSection.Kind) -> String? {
        switch kind {
        case .favourites: return "⌘D keeps a character here."
        case .recents: return "Your next character starts a collection."
        case .results: return nil
        }
    }
}

/// Shared with the non-interactive appearance preview in Settings.
struct PickerCell: View {
    let item: PickerItem
    let isSelected: Bool
    let isNavigating: Bool
    let isHovered: Bool
    let isPressed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.pickerPalette) private var palette

    var body: some View {
        face
            .foregroundStyle(isSelected ? palette.ink : palette.chalk)
            .opacity(item.preview.isExactly(item.string) ? 1 : 0.75)
            .frame(width: PickerViewModel.cellSize, height: PickerViewModel.cellSize)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? palette.paper : palette.block)
                    .overlay {
                        if !isPressed {
                            LinearGradient(colors: [.white.opacity(isHovered ? 0.12 : 0.05), .clear], startPoint: .top, endPoint: .bottom)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .shadow(color: .black.opacity(isPressed ? 0 : 0.5), radius: isHovered ? 2 : 0.5, y: isPressed ? 0 : 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? palette.ink.opacity(contrast == .increased ? 0.8 : 0.25) : palette.chalk.opacity(contrast == .increased ? 0.7 : 0.16), lineWidth: contrast == .increased ? 1.5 : 0.5)
            }
            .overlay(alignment: .bottom) {
                if isSelected, isNavigating {
                    Capsule().fill(palette.ink).frame(width: 10, height: 2).padding(.bottom, 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.isFavourite {
                    Circle()
                        .fill(isSelected ? palette.ink : palette.accent)
                        .frame(width: 3, height: 3)
                        .padding(4)
                }
            }
            .offset(y: reduceMotion ? 0 : isPressed ? 1 : isSelected ? -2 : isHovered ? -1.5 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: isPressed ? 0.06 : 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.8), value: isSelected)
    }

    @ViewBuilder private var face: some View {
        if let shortcut = item.snippetShortcut {
            VStack(spacing: 1) {
                Text("::").font(.system(size: 8, design: .monospaced))
                Text(shortcut)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 3)
        } else {
            Text(item.preview)
                .font(.system(size: item.isEmoji ? 26 : 25))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
    }
}

/// Actions stay literal even though the proof and tray use a physical idiom.
struct PickerFooterView: View {
    @ObservedObject var model: PickerViewModel
    @Environment(\.pickerPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.chalk)
                    .lineLimit(2)
                    .accessibilityAddTraits(.updatesFrequently)
            } else {
                Button {
                    if let selection = model.selection { model.onActivate?(selection) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "return")
                        Text(model.canInsert ? (model.selectedItem?.isSnippet == true ? "Insert text" : "Insert character")
                             : (model.selectedItem?.isSnippet == true ? "Copy text" : "Copy character"))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.chalk)
                }
                .buttonStyle(.plain)
                .disabled(model.selectedItem == nil)
                .help(model.canInsert ? "Insert into the original typing field" : "No insertion target. Copy instead.")

                Spacer(minLength: 4)
                if model.canInsert {
                    Button { model.onCopySelection?() } label: {
                        Text("⌘↵ Copy")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.chalk)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.selectedItem == nil)
                } else {
                    Text("COPY ONLY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .padding(.horizontal, 19)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.chalk.opacity(0.15)).frame(height: 0.5).padding(.horizontal, 19)
        }
    }
}
