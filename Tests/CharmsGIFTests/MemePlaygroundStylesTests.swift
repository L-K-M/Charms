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
        let initial = MemePlaygroundStyles.initial(for: .apple)
        XCTAssertTrue(allowed.contains(initial), "the preselection must be allowed")
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            XCTAssertTrue(allowed.contains(.externalProvider))
            XCTAssertNotEqual(initial, .externalProvider)
            // macOS hides an unconfigured provider unless it is preselected.
            XCTAssertTrue(MemePlaygroundEntry.offersExternalProvider)
            XCTAssertEqual(MemePlaygroundStyles.initial(for: .externalProvider), .externalProvider)
        }
        #endif
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            XCTAssertTrue(allowed.contains(.any))
            XCTAssertEqual(initial, .any)
        } else {
            XCTAssertEqual(initial, .illustration)
        }
        #endif
    }
}
#endif
