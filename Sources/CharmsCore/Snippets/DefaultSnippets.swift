import Foundation

/// Conventional text faces researched on the public web. Provenance and the
/// exact variants chosen are recorded in docs/snippets.md; no runtime fetches.
public enum DefaultSnippets {
    public static let library: SnippetLibrary = {
        let entries: [(shortcut: String, name: String, text: String)] = [
            ("shrug", "Shrug", #"¯\_(ツ)_/¯"#),
            ("tableflip", "Table flip", "(╯°□°)╯︵ ┻━┻"),
            ("unflip", "Put the table back", "┬─┬ノ( º _ ºノ)"),
            ("lenny", "Lenny face", "( ͡° ͜ʖ ͡°)"),
            ("disapproval", "Look of disapproval", "ಠ_ಠ"),
            ("joy", "Joy", "(≧∇≦)/"),
            ("happy", "Happy", "( ﾟヮﾟ)"),
            ("sad", "Sad", "T_T"),
            ("cry", "Crying", "(ಥ﹏ಥ)"),
            ("surprise", "Surprised", "(°◇°)"),
            ("cheer", "Cheering", #"\o/"#),
            ("party", "Confetti", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧"),
            ("laugh", "Laughing", "(＾▽＾)"),
            ("angry", "Angry", "(＃ﾟДﾟ)"),
            ("kiss", "Blowing a kiss", "(*^3^)/~☆"),
            ("bear", "Bear", "ʕ•ᴥ•ʔ"),
            ("cat", "Cat", "(=^･ω･^=)"),
            ("dizzy", "Dizzy", "(@_@)"),
            ("dance", "Dancing", "ᕕ( ᐛ )ᕗ"),
            ("peace", "Peace of mind", "ヽ(´ー｀)ﾉ")
        ]
        // Stable IDs let a restored starter update existing entries without
        // creating duplicates. Invalid built-ins are a programming error.
        let snippets = entries.enumerated().map { index, entry in
            let id = UUID(uuidString: String(format: "43686172-6D73-4000-8000-%012d", index + 1))!
            return try! TextSnippet(id: id, shortcut: entry.shortcut, name: entry.name, text: entry.text)
        }
        return try! SnippetLibrary(snippets: snippets)
    }()
}
