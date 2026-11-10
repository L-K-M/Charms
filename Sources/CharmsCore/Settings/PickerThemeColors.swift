/// Opaque sRGB roles shared by the native editor and the composing surface.
/// Themes change presentation only; they never transform a character string.
extension PickerTheme {
    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        fileprivate init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public struct Colors: Sendable {
        public let paper: RGB
        public let ink: RGB
        public let tray: RGB
        public let chalk: RGB
        public let block: RGB
        public let accent: RGB
        public let proofAccent: RGB
        public let lightShell: RGB
        public let darkShell: RGB
    }

    public var colors: Colors {
        switch self {
        case .impression:
            return Colors(
                paper: RGB(0.98, 0.965, 0.925), ink: RGB(0.13, 0.18, 0.15),
                tray: RGB(0.12, 0.16, 0.14), chalk: RGB(0.94, 0.95, 0.90),
                block: RGB(0.21, 0.26, 0.23), accent: RGB(1, 0.44, 0.30),
                proofAccent: RGB(0.70, 0.21, 0.10),
                lightShell: RGB(0.91, 0.91, 0.87), darkShell: RGB(0.18, 0.22, 0.20)
            )
        case .blueprint:
            return Colors(
                paper: RGB(0.94, 0.97, 1), ink: RGB(0.09, 0.17, 0.29),
                tray: RGB(0.08, 0.13, 0.23), chalk: RGB(0.86, 0.94, 1),
                block: RGB(0.14, 0.22, 0.34), accent: RGB(0.38, 0.78, 1),
                proofAccent: RGB(0.05, 0.30, 0.55),
                lightShell: RGB(0.87, 0.92, 0.97), darkShell: RGB(0.12, 0.20, 0.31)
            )
        case .plum:
            return Colors(
                paper: RGB(1, 0.955, 0.94), ink: RGB(0.28, 0.12, 0.24),
                tray: RGB(0.19, 0.105, 0.18), chalk: RGB(0.99, 0.90, 0.96),
                block: RGB(0.30, 0.19, 0.28), accent: RGB(1, 0.68, 0.42),
                proofAccent: RGB(0.56, 0.18, 0.40),
                lightShell: RGB(0.95, 0.89, 0.93), darkShell: RGB(0.27, 0.16, 0.25)
            )
        }
    }
}
