import AppKit
import CharmsCore
import SwiftUI

extension NSTextView {
    /// Search identifiers and explicitly saved text are not prose. On macOS
    /// 27, automatic text processing also consumed the first Escape after
    /// "shrug" before the field delegate saw it. This leaves native IME
    /// composition and ordinary editing intact, but never rewrites the text.
    func disableAutomaticTextProcessing() {
        isAutomaticTextCompletionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
    }
}

/// A native single-line editor with no smart quotes, substitutions or spelling
/// correction. Updates never replace an equal-scalar string, preserving the
/// current field editor's selection and Undo history.
struct ExactTextField: NSViewRepresentable {
    @Binding var text: String
    let label: String
    var monospaced = false
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.font = monospaced ? .monospacedSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 13)
        field.setAccessibilityLabel(label)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if !field.stringValue.isExactly(text) { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        fileprivate var parent: ExactTextField
        fileprivate init(_ parent: ExactTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            ((notification.object as? NSTextField)?.currentEditor() as? NSTextView)?.disableAutomaticTextProcessing()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }
}
