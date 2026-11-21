import XCTest
@testable import CharmsCore

final class GIFMediaPolicyTests: XCTestCase {
    func testAcceptsGIFServiceMediaHosts() {
        for address in [
            "https://media2.giphy.com/media/x/giphy.gif",
            "https://i.giphy.com/x.webp",
            "https://static.klipy.com/a/b.gif",
            "https://static2.klipy.com/ii/a/md.gif",
            "https://giphy.com/x.gif",
            "https://KLIPY.COM/abc.gif",
        ] {
            XCTAssertNotNil(GIFMediaPolicy.mediaURL(address), address)
        }
    }

    func testResultsStayWithTheSelectedProvider() {
        let media = URL(string: "https://static.klipy.com/image.gif")!
        XCTAssertTrue(GIFMediaPolicy.isServiceMedia(media, provider: .klipy))
        XCTAssertFalse(GIFMediaPolicy.isServiceMedia(media, provider: .giphy))
    }

    func testRejectsEverythingElse() {
        for address in [
            "http://media.giphy.com/abc.gif",           // not HTTPS
            "https://tracker.example/p.gif",            // not a GIF service
            "https://notgiphy.com/x.gif",               // lookalike domain
            "https://giphy.com.evil.example/x.gif",     // service name as a label
            "https://media.giphy.com:8443/abc.gif",     // odd port
            "https://user:pw@media.giphy.com/abc.gif",  // credentials
            "/files/local.gif",                         // relative path
            "javascript:alert(1)",
            "",
        ] {
            XCTAssertNil(GIFMediaPolicy.mediaURL(address), address)
        }
        XCTAssertNil(GIFMediaPolicy.mediaURL("https://media.giphy.com/" + String(repeating: "a", count: GIFMediaPolicy.maximumURLLength)))
    }

    func testPreviewBoundsAreBounded() {
        XCTAssertLessThanOrEqual(GIFMediaPolicy.maximumPreviewBytes, GIFMediaPolicy.maximumMediaBytes)
        XCTAssertGreaterThan(GIFMediaPolicy.maximumPreviewCacheBytes, GIFMediaPolicy.maximumPreviewBytes)
    }
}
