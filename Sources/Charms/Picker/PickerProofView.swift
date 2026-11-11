import CharmsCore
import SwiftUI

/// Two optical scales of the same catalogue preview, never a reading of the
/// source document. The specimen is not an insertion target or a receipt.
struct PickerProofView: View {
    @ObservedObject var model: PickerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.pickerPalette) private var palette

    private var item: PickerItem? { model.pressedItem ?? model.selectedItem }
    private var isPressed: Bool { model.pressedItem != nil }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.ink.opacity(0.14))
                .offset(y: 3)
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.paper)

            if let item {
                // Keep the new proof visible from the first frame. Replacing
                // identity with an opacity transition left blank paper during
                // rapid queries in the recorded prototype. Only its pressure
                // moves now; ExactString also distinguishes U+212B and U+00C5.
                Group {
                    if item.isSnippet { snippetSpecimen(item) } else { specimen(item) }
                }
                    // Phase animation moves the sheet, not the old and new
                    // glyphs together. Suppress implicit text/font crossfades.
                    .transaction { $0.animation = nil }
                    .phaseAnimator([false, true], trigger: item.id) { content, lifted in
                        content.offset(y: reduceMotion ? 0 : lifted ? -3 : 0)
                    } animation: { lifted in
                        reduceMotion ? nil : .easeOut(duration: lifted ? 0.04 : 0.14)
                    }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "character.magnify")
                        .font(.system(size: 30, weight: .light))
                    Text(model.isLoading ? "Preparing your characters…" : "A place for the right character.")
                        .font(.system(size: 13, design: .serif))
                    Text(model.isQueryEmpty ? "Search, or choose a favourite below." : "Try another name or a code point.")
                        .font(.system(size: 11))
                }
                .foregroundStyle(palette.ink)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.07), value: isPressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item?.isSnippet == true ? "Text snippet proof" : "Character proof")
        .accessibilityValue(proofDescription)
        .accessibilityAddTraits(.isStaticText)
    }

    private func specimen(_ item: PickerItem) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 16) {
                Text(item.preview)
                    .font(.system(size: item.isEmoji ? 68 : 76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .foregroundStyle(palette.ink)
                    .frame(width: 108, height: 88)
                    .scaleEffect(isPressed && !reduceMotion ? 0.94 : 1)
                    .offset(y: isPressed && !reduceMotion ? 2 : 0)
                    .background(alignment: .bottom) {
                        Rectangle()
                            .fill(palette.ink.opacity(0.12))
                            .frame(height: 0.5)
                            .padding(.bottom, 15)
                    }
                    .overlay {
                        ProofRegistration()
                            .stroke(palette.ink.opacity(contrast == .increased ? 0.8 : 0.3), lineWidth: 0.75)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isPressed ? palette.ink : palette.proofAccent)
                            .frame(width: 4, height: 4)
                        Text(isPressed ? "IN THE PRESS" : "CHARACTER PROOF")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.2)
                    }
                    Text(item.name)
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(item.name)
                    // A long ZWJ sequence is never abbreviated to one scalar.
                    ViewThatFits(in: .horizontal) {
                        scalarLabel(item)
                        HStack(spacing: 5) {
                            ScrollView(.horizontal) { scalarLabel(item) }
                                .scrollIndicators(.hidden)
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 9))
                        }
                    }
                    .frame(height: 15)
                    .help(item.codePoints + ". Scroll horizontally for the complete sequence.")
                }
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("IN TEXT")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("Aa").foregroundStyle(palette.proofSecondary)
                    Text(item.preview)
                    Text("Bb").foregroundStyle(palette.proofSecondary)
                }
                .font(.system(size: 16))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                Text(usesGuide(item) ? "Preview guide only" : "Exact Unicode")
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundStyle(palette.ink)
            .padding(.top, 5)
            .overlay(alignment: .top) {
                Rectangle().fill(palette.ink.opacity(0.17)).frame(height: 0.5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .offset(y: isPressed && !reduceMotion ? 1 : 0)
    }

    private func snippetSpecimen(_ item: PickerItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(isPressed ? "IN THE PRESS" : "TEXT SNIPPET")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                Spacer(minLength: 8)
                Text("::" + (item.snippetShortcut ?? ""))
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
            }
            Text(item.name)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .lineLimit(1)
            Text(item.string)
                .font(.system(size: 17, design: .monospaced))
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(y: isPressed && !reduceMotion ? 1 : 0)
    }

    private func scalarLabel(_ item: PickerItem) -> some View {
        Text(item.codePoints)
            .font(.system(size: 10, design: .monospaced))
            .fixedSize()
            .padding(.bottom, 2)
    }

    private func usesGuide(_ item: PickerItem) -> Bool {
        !item.preview.isExactly(item.string)
    }

    private var proofDescription: String {
        guard let item else { return model.isLoading ? "Loading characters" : "No character selected" }
        if let shortcut = item.snippetShortcut { return "\(item.name). Text snippet ::\(shortcut). \(item.string)" }
        let guide = usesGuide(item) ? ". The visible guide is not inserted" : ""
        return "\(item.name). \(item.codePoints)\(guide)"
    }
}
