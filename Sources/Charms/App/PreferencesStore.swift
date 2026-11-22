import CharmsCore
import Combine
import Foundation
import SwiftUI

/// The user's settings, observable by the interface and by the services
/// that depend on them.
@MainActor
final class PreferencesStore: ObservableObject {
    @Published private(set) var value: Preferences

    private let save: (Data) -> Void

    init(paths: AppPaths, defaults: UserDefaults = .standard) {
        if paths.isIsolated {
            let file = paths.preferencesFile
            value = Preferences.decoded(from: try? Data(contentsOf: file))
            save = { data in
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
        } else {
            value = Preferences.decoded(from: defaults.data(forKey: Preferences.storageKey))
            save = { data in defaults.set(data, forKey: Preferences.storageKey) }
        }
    }

    func update(_ change: (inout Preferences) -> Void) {
        var copy = value
        change(&copy)
        guard copy != value else { return }
        value = copy
        save(copy.encoded())
    }

    /// A control's two-way connection to one stored setting.
    func binding<Value>(_ setting: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { self.value[keyPath: setting] },
            set: { value in self.update { $0[keyPath: setting] = value } }
        )
    }
}
