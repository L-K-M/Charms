#if canImport(ImagePlayground)
import ImagePlayground
import XCTest
@testable import Charms

final class MemePlaygroundStylesTests: XCTestCase {
    func testOffersWhatThisSystemHasAndNeverPreselectsAnotherProvider() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("styles need macOS 15.4") }
        let allowed = MemePlaygroundStyles.allowed
        XCTAssertTrue(allowed.contains(.illustration) && allowed.contains(.animation) && allowed.contains(.sketch))
        XCTAssertFalse(allowed.contains(.emoji), "Genmoji returns a glyph, not artwork")
        XCTAssertTrue(allowed.contains(MemePlaygroundStyles.initial), "the preselection must be allowed")
        if #available(macOS 26, *) {
            XCTAssertTrue(allowed.contains(.externalProvider))
            XCTAssertNotEqual(MemePlaygroundStyles.initial, .externalProvider)
        }
        if #available(macOS 27, *) {
            XCTAssertTrue(allowed.contains(.any))
            XCTAssertEqual(MemePlaygroundStyles.initial, .any)
        } else {
            XCTAssertEqual(MemePlaygroundStyles.initial, .illustration)
        }
    }
}
#endif
