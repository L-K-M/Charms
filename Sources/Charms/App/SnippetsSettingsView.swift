import CharmsCore
import SwiftUI

struct SnippetsSettingsView: View {
    @ObservedObject var controller: SnippetController
    @State private var selection: UUID?
    @State private var draft: SnippetDraft?
    @State private var confirmRemoval = false

    private var selected: TextSnippet? { controller.library.snippets.first { $0.id == selection } }
    private var sorted: [TextSnippet] { controller.library.snippets.sorted { $0.shortcut < $1.shortcut } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type ::shrug, then Return. Or find a snippet with the usual Charms shortcut. Nothing expands automatically.")
                .font(.callout)
            List(sorted, selection: $selection) { snippet in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snippet.name).font(.body.weight(.medium))
                        Text("::" + snippet.shortcut).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(snippet.text).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                }
                .padding(.vertical, 3)
                .tag(snippet.id)
                .help(snippet.text)
                .onTapGesture(count: 2) { draft = SnippetDraft(snippet: snippet) }
            }
            .listStyle(.inset)
            .overlay { RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3)) }
            .onDeleteCommand { if selected != nil { confirmRemoval = true } }

            HStack {
                Button("New Snippet…") { draft = SnippetDraft() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(controller.isUnavailable || sorted.count >= SnippetLibrary.maximumCount)
                Button("Edit…") { if let selected { draft = SnippetDraft(snippet: selected) } }
                    .disabled(selected == nil || controller.isUnavailable)
                Button("Remove…") { confirmRemoval = true }
                    .disabled(selected == nil || controller.isUnavailable)
                Spacer()
                Text("\(sorted.count) snippets").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Add Missing Starters") { controller.addMissingStarters() }
                    .disabled(controller.isUnavailable)
                Text("Keeps your edits and existing shortcuts.").font(.caption).foregroundStyle(.secondary)
            }
            if let message = controller.message {
                Text(message).font(.callout).foregroundStyle(.red)
                if controller.isUnavailable { Button("Retry Loading") { controller.reload() } }
            }
            Text("Snippets you save are stored locally as plain text. Searches and surrounding typing are never saved. Favourites and recents keep their exact saved text, even after you edit or remove a snippet.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .sheet(item: $draft) { value in
            SnippetEditor(draft: value, controller: controller) { selection = $0 }
        }
        .alert("Remove this snippet?", isPresented: $confirmRemoval) {
            Button("Remove", role: .destructive) {
                if let selected, controller.remove(id: selected.id) { selection = nil }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It will stop matching its shortcut. Favourites and recents keep their saved copies.")
        }
    }
}

private struct SnippetDraft: Identifiable {
    let id: UUID
    var shortcut: String
    var name: String
    var text: String

    init(snippet: TextSnippet? = nil) {
        id = snippet?.id ?? UUID()
        shortcut = snippet?.shortcut ?? ""
        name = snippet?.name ?? ""
        text = snippet?.text ?? ""
    }

    func validated() throws -> TextSnippet {
        try TextSnippet(id: id, shortcut: shortcut, name: name, text: text)
    }
}

private struct SnippetEditor: View {
    @State var draft: SnippetDraft
    @ObservedObject var controller: SnippetController
    let onSaved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private var problem: String? {
        do {
            var copy = controller.library
            try copy.upsert(draft.validated())
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Text Snippet").font(.headline)
            Form {
                LabeledContent("Name") {
                    ExactTextField(text: $draft.name, label: "Snippet name", onSubmit: save, onCancel: { dismiss() })
                }
                LabeledContent("Shortcut") {
                    HStack(spacing: 3) {
                        Text("::").foregroundStyle(.secondary)
                        ExactTextField(text: $draft.shortcut, label: "Snippet shortcut", monospaced: true,
                                       onSubmit: save, onCancel: { dismiss() })
                    }
                }
                LabeledContent("Replacement text") {
                    ExactTextField(text: $draft.text, label: "Replacement text", monospaced: true,
                                   onSubmit: save, onCancel: { dismiss() })
                }
            }
            .onSubmit { save() }
            HStack {
                Text("Single line; spaces are preserved. No templates or scripts.")
                Spacer()
                Text("\(draft.text.utf16.count)/\(TextSnippet.maximumTextUnits) UTF-16 units")
            }
            .font(.caption).foregroundStyle(.secondary)
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.secondary)
            }
            if let message = controller.message {
                Text(message).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(problem != nil || controller.isUnavailable)
            }
        }
        .padding(24)
        .frame(width: 510)
    }

    private func save() {
        guard problem == nil, let snippet = try? draft.validated(), controller.save(snippet) else { return }
        onSaved(snippet.id)
        dismiss()
    }
}
