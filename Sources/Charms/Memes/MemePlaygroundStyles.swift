/// Which of the composer's buttons opened the system sheet.
enum MemePlaygroundEntry {
    case apple
    /// ChatGPT, through the system. Measured on macOS 27.0.1: until it is set
    /// up the style menu omits it, and only preselecting it shows the setup.
    case externalProvider

    static var offersExternalProvider: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }
}

#if canImport(ImagePlayground)
import ImagePlayground

/// The styles the system sheet may offer.
@available(macOS 15.4, *)
enum MemePlaygroundStyles {
    static var allowed: [ImagePlaygroundStyle] {
        var styles: [ImagePlaygroundStyle] = [.illustration, .animation, .sketch]
        // `.any` is new in the macOS 27 SDK, which ships with Swift 6.4.
        #if compiler(>=6.4)
        if #available(macOS 27, *) { styles.insert(.any, at: 0) }
        #endif
        // Likewise the macOS 26 SDK and Swift 6.2.
        #if compiler(>=6.2)
        if #available(macOS 26, *) { styles.append(.externalProvider) }
        #endif
        return styles
    }

    /// The sheet starts generating with this style as soon as it opens with
    /// a description, so another provider is preselected only when asked for.
    static func initial(for entry: MemePlaygroundEntry) -> ImagePlaygroundStyle {
        #if compiler(>=6.2)
        if entry == .externalProvider, #available(macOS 26, *) { return .externalProvider }
        #endif
        #if compiler(>=6.4)
        if #available(macOS 27, *) { return .any }
        #endif
        return .illustration
    }
}
#endif
