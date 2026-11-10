import AppKit
import Carbon.HIToolbox
import CharmsCore
import SwiftUI

/// The picker's window: a borderless panel that can take the keyboard
/// without activating Charms.
///
/// Measured on macOS 27: with the non-activating style this panel becomes
/// key about 10 ms after it is ordered front while the application being
/// typed in stays frontmost, and when the panel is ordered out the same
/// field has keyboard focus again within a few milliseconds. That is what
/// lets a character go back to where the user was typing.
final class PickerPanel: NSPanel {
    static let size = CGSize(width: 432, height: 472)

    /// Keys the search field never sees as commands: Command-Return,
    /// Command-D and Command-C. Returns true when the key was used.
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true
        )
        level = .floating
        // Join whichever Space is current, including another application's
        // full-screen Space, instead of pulling the user to a different one.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Charms is never the active application while the picker is open,
        // so hiding on deactivation would hide it at once.
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        setAccessibilityLabel("Charms")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// What the search field asks of its owner.
@MainActor
protocol PickerSearchDelegate: AnyObject {
    func searchTextChanged(_ text: String)
    /// A command key such as an arrow or Return. Returns true when handled.
    func searchCommand(_ command: PickerCommand, caretAtEnd: Bool) -> Bool
}

enum PickerCommand {
    case up, down, left, right
    case activate
    case contextMenu
    case cancel
    case tab, backTab
}

/// Lays out the search field, the grid and the footer.
@MainActor
final class PickerViewController: NSViewController, NSTextFieldDelegate {
    let searchField = NSTextField()
    weak var searchDelegate: PickerSearchDelegate?
    private let model: PickerViewModel

    init(model: PickerViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PickerViewController is created in code")
    }

    override func loadView() {
        let surface = NSView(frame: CGRect(origin: .zero, size: PickerPanel.size))
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 14
        surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 15)
        searchField.placeholderString = "Find arrows, symbols, emoji…"
        searchField.delegate = self
        searchField.usesSingleLineMode = true
        searchField.lineBreakMode = .byTruncatingHead
        searchField.cell?.isScrollable = true
        searchField.setAccessibilityLabel("Search characters")
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // One hosting coordinate space also makes keyboard context-menu
        // placement agree with the selected cell's reported frame.
        let content = NSHostingView(rootView: PickerSurfaceView(model: model))
        content.sizingOptions = []
        content.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(content)
        surface.addSubview(searchField)

        NSLayoutConstraint.activate([
            surface.widthAnchor.constraint(equalToConstant: PickerPanel.size.width),
            surface.heightAnchor.constraint(equalToConstant: PickerPanel.size.height),
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            content.topAnchor.constraint(equalTo: surface.topAnchor),
            content.bottomAnchor.constraint(equalTo: surface.bottomAnchor),

            searchField.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 44),
            searchField.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -54),
            searchField.centerYAnchor.constraint(equalTo: surface.topAnchor, constant: PickerViewModel.mastheadHeight + 20)
        ])
        view = surface
    }

    /// Shares the shell's ink with the real field editor, including the caret.
    /// Dynamic colors follow live system appearance changes without replacing
    /// the editor, its marked text, selection or Undo history.
    func applyTheme(_ theme: PickerTheme) {
        let colors = theme.colors
        searchField.textColor = NSColor(name: nil) { appearance in
            NSColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? colors.chalk : colors.ink)
        }
        updateEditorColors()
    }

    private func updateEditorColors() {
        guard let editor = searchField.currentEditor() as? NSTextView,
              let color = searchField.textColor else { return }
        editor.textColor = color
        editor.insertionPointColor = color
    }

    /// Puts the keyboard into the search field with the caret at the end.
    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
        updateEditorColors()
        searchField.currentEditor()?.selectedRange = NSRange(location: (searchField.stringValue as NSString).length, length: 0)
    }

    func setQuery(_ text: String) {
        searchField.stringValue = text
        searchField.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    /// Inserts text at a UTF-16 offset of the query, keeping the caret after
    /// what the user has typed in the picker.
    func insertIntoQuery(_ text: String, at offset: Int) {
        let current = searchField.stringValue as NSString
        let location = max(0, min(offset, current.length))
        let editor = searchField.currentEditor()
        let caret = editor?.selectedRange
        searchField.stringValue = current.replacingCharacters(in: NSRange(location: location, length: 0), with: text)
        if let editor, let caret {
            let added = (text as NSString).length
            let moved = caret.location >= location ? caret.location + added : caret.location
            editor.selectedRange = NSRange(location: moved, length: caret.length)
        }
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        searchDelegate?.searchTextChanged(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // While an input method is composing, Return, the arrows and Escape
        // belong to its candidate window, not to the picker.
        if textView.hasMarkedText() { return false }
        let caretAtEnd = textView.selectedRange.length == 0 && textView.selectedRange.location == (textView.string as NSString).length
        let command: PickerCommand
        switch selector {
        case #selector(NSResponder.moveUp(_:)): command = .up
        case #selector(NSResponder.moveDown(_:)): command = .down
        case #selector(NSResponder.moveLeft(_:)): command = .left
        case #selector(NSResponder.moveRight(_:)): command = .right
        case #selector(NSResponder.insertNewline(_:)): command = .activate
        case #selector(NSResponder.insertLineBreak(_:)): command = .contextMenu
        case #selector(NSResponder.cancelOperation(_:)): command = .cancel
        case #selector(NSResponder.insertTab(_:)): command = .tab
        case #selector(NSResponder.insertBacktab(_:)): command = .backTab
        default: return false
        }
        return searchDelegate?.searchCommand(command, caretAtEnd: caretAtEnd) ?? false
    }
}
