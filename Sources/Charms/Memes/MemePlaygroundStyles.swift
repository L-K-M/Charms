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
        // No check for a configured provider: the system runs that setup.
        if #available(macOS 26, *) { styles.append(.externalProvider) }
        return styles
    }

    /// Never the external provider, which is the user's choice to make.
    static var initial: ImagePlaygroundStyle {
        #if compiler(>=6.4)
        if #available(macOS 27, *) { return .any }
        #endif
        return .illustration
    }
}
#endif
