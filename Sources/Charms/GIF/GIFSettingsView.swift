import AppKit
import SwiftUI

struct GIFSettingsView: View {
    @ObservedObject var library: LocalGIFLibrary
    @ObservedObject var online: OnlineGIFSearch
    @State private var editing: URL?
    @State private var draft = ""

    var body: some View {
        Form {
            Section("My GIFs") {
                if let folder = library.folder {
                    Text(folder.path).textSelection(.enabled)
                }
                HStack {
                    Button("Choose Folder…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.directoryURL = library.folder
                        if panel.runModal() == .OK { library.setFolder(panel.url) }
                    }
                    if library.folder != nil {
                        Button("Stop Watching") { library.setFolder(nil) }
                    }
                }
                Text("Drop GIF files in this folder to find them by name or tag. Charms analyzes frames on your Mac and uses Apple Intelligence when available.")
                    .font(.callout)
                if let status = library.status { Text(status) }
                ForEach(library.entries, id: \.url) { entry in
                    HStack {
                        Text(entry.url.lastPathComponent).lineLimit(1)
                        Spacer()
                        Button("Edit Tags…") {
                            draft = entry.tags.joined(separator: ", ")
                            editing = entry.url
                        }
                        .accessibilityLabel("Edit tags for " + entry.url.lastPathComponent)
                    }
                }
            }
            GIFProviderSettingsView(service: online)
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            VStack(alignment: .leading) {
                Text(editing?.lastPathComponent ?? "").font(.headline)
                TextField("Tags, separated by commas", text: $draft)
                HStack {
                    Button("Cancel", role: .cancel) { editing = nil }
                    Spacer()
                    Button("Save Tags") {
                        if let editing {
                            library.setTags(draft.components(separatedBy: ","), for: editing)
                        }
                        editing = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding().frame(minWidth: 340)
        }
    }
}
