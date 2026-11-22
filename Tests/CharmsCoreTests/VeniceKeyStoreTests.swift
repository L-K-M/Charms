import XCTest
@testable import CharmsCore

final class VeniceKeyStoreTests: XCTestCase {
    private let key = "venice-test-key-0123456789"
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CharmsVeniceKey-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private var file: URL { directory.appendingPathComponent(VeniceKeyStore.fileName) }

    func testIsolatedHomeKeepsThePrivateKeyInItsOwnFile() throws {
        let store = VeniceKeyStore.make(supportDirectory: directory, isIsolated: true)
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(try store.key())

        try store.setKey(" \(key)\n")
        XCTAssertTrue(store.hasKey)
        XCTAssertEqual(try store.key(), key)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(FileGIFServiceKeyStore.fileName).path))

        try store.setKey(nil)
        XCTAssertFalse(store.hasKey)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testKeysThatCouldAlterAHeaderAreRefused() {
        let store = VeniceKeyStore.make(supportDirectory: directory, isIsolated: true)
        for bad in ["short", "has a space 0123456789", "line\r\nInjected: header-0123456789", "ünïcode-key-0123456789", String(repeating: "k", count: 513)] {
            XCTAssertThrowsError(try store.setKey(bad), bad) {
                XCTAssertEqual($0 as? VeniceKeyError, .implausible)
            }
        }
        XCTAssertFalse(store.hasKey)
    }

    func testAnUnreadableStoreIsAnErrorRatherThanAMissingKey() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        let store = VeniceKeyStore.make(supportDirectory: directory, isIsolated: true)
        XCTAssertThrowsError(try store.key())
        XCTAssertThrowsError(try store.setKey(key)) {
            XCTAssertEqual($0 as? VeniceKeyError, .storage)
        }
        XCTAssertEqual(try Data(contentsOf: file), Data("not json".utf8), "an unreadable file is left alone")
    }

    func testGIFKeysSavedByTheLastReleaseStillRead() throws {
        // The document format FileGIFServiceKeyStore wrote in 0.2.0.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"keys":{"klipy":"klipy-key-1"}}"#.utf8).write(to: directory.appendingPathComponent("gif-service-keys.json"))
        XCTAssertEqual(FileGIFServiceKeyStore(directory: directory).key(for: .klipy), "klipy-key-1")
        XCTAssertEqual(KeychainGIFServiceKeyStore.service, "ch.lkmc.Charms.gif-service-key")
    }

    func testVeniceIsOffByDefaultAndForPreferencesFromEarlierVersions() throws {
        XCTAssertFalse(Preferences().veniceImagesEnabled)
        let older = Preferences.decoded(from: Data(#"{"typedTriggerEnabled":true}"#.utf8))
        XCTAssertTrue(older.typedTriggerEnabled)
        XCTAssertFalse(older.veniceImagesEnabled)
        XCTAssertEqual(older.veniceModel, .zImageTurbo)
        XCTAssertEqual(older.veniceQuality, .low)

        let damaged = Preferences.decoded(from: Data(#"{"typedTriggerEnabled":true,"veniceImagesEnabled":"yes","veniceModel":"retired","veniceQuality":"ultra"}"#.utf8))
        XCTAssertTrue(damaged.typedTriggerEnabled, "one bad field costs nothing else")
        XCTAssertFalse(damaged.veniceImagesEnabled)
        XCTAssertEqual(damaged.veniceModel, .zImageTurbo)
        XCTAssertEqual(damaged.veniceQuality, .low)

        let chosen = Preferences(veniceImagesEnabled: true, veniceModel: .gptImageFlare, veniceQuality: .high)
        XCTAssertEqual(Preferences.decoded(from: chosen.encoded()), chosen)
    }
}
