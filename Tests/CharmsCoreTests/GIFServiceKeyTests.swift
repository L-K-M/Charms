import XCTest
@testable import CharmsCore

final class GIFServiceKeyTests: XCTestCase {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CharmsGIFKeys-\(UUID().uuidString)", isDirectory: true)
    }

    private func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    func testKeysAreStoredPerProvider() throws {
        let directory = makeDirectory()
        defer { remove(directory) }
        let store = FileGIFServiceKeyStore(directory: directory)
        XCTAssertNil(store.key(for: .klipy))
        XCTAssertNil(store.key(for: .giphy))

        try store.setKey("  klipy-key-1  ", for: .klipy)
        XCTAssertEqual(store.key(for: .klipy), "klipy-key-1", "a key is trimmed")
        XCTAssertNil(store.key(for: .giphy))

        try store.setKey("giphy-key-2", for: .giphy)
        XCTAssertEqual(store.key(for: .klipy), "klipy-key-1")
        XCTAssertEqual(store.key(for: .giphy), "giphy-key-2")
    }

    func testEmptyKeyRemovesOnlyThatProvider() throws {
        let directory = makeDirectory()
        defer { remove(directory) }
        let store = FileGIFServiceKeyStore(directory: directory)
        try store.setKey("klipy-key-1", for: .klipy)
        try store.setKey("giphy-key-2", for: .giphy)

        try store.setKey(nil, for: .klipy)
        XCTAssertNil(store.key(for: .klipy))
        XCTAssertEqual(store.key(for: .giphy), "giphy-key-2")

        try store.setKey("   ", for: .giphy)
        XCTAssertNil(store.key(for: .giphy))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(FileGIFServiceKeyStore.fileName).path), "an emptied key file is deleted")
    }

    func testImplausibleKeysAreRefused() {
        let directory = makeDirectory()
        defer { remove(directory) }
        let store = FileGIFServiceKeyStore(directory: directory)
        for key in ["short", "has space key", "slash/../key", "ünïcode-key-1", String(repeating: "k", count: 200)] {
            XCTAssertThrowsError(try store.setKey(key, for: .klipy), key) {
                XCTAssertEqual($0 as? GIFServiceKeyError, .implausible)
            }
        }
        XCTAssertNil(store.key(for: .klipy))
    }

    func testIsolatedHomesKeepTheirOwnKeys() throws {
        let first = makeDirectory()
        let second = makeDirectory()
        defer { remove(first); remove(second) }
        let firstStore = FileGIFServiceKeyStore(directory: first)
        let secondStore = FileGIFServiceKeyStore(directory: second)

        try firstStore.setKey("klipy-key-1", for: .klipy)
        XCTAssertEqual(firstStore.key(for: .klipy), "klipy-key-1")
        XCTAssertNil(secondStore.key(for: .klipy), "one home cannot read another home's keys")

        try secondStore.setKey("klipy-key-2", for: .klipy)
        XCTAssertEqual(firstStore.key(for: .klipy), "klipy-key-1", "saving in one home leaves the other alone")
        XCTAssertEqual(secondStore.key(for: .klipy), "klipy-key-2")
    }

    func testKeyFileIsPrivate() throws {
        let directory = makeDirectory()
        defer { remove(directory) }
        let store = FileGIFServiceKeyStore(directory: directory)
        try store.setKey("klipy-key-1", for: .klipy)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(FileGIFServiceKeyStore.fileName).path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600), "the key file is readable only by this user")
    }

    func testFactoryKeepsAnIsolatedHomeOutOfTheKeychain() {
        let directory = makeDirectory()
        defer { remove(directory) }
        let store = GIFServiceKeyStores.make(supportDirectory: directory, isIsolated: true)
        XCTAssertTrue(store is FileGIFServiceKeyStore, "an isolated home must not touch the real Keychain")
    }

    func testAnIsolatedAliasCannotSelectTheRealKeychain() throws {
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Charms", isDirectory: true)
        let alias = makeDirectory()
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        defer { remove(alias) }
        // Inspect only the selected backend. Never access either credential.
        XCTAssertTrue(GIFServiceKeyStores.make(supportDirectory: alias, isIsolated: true) is FileGIFServiceKeyStore)
    }

    func testFactoryUsesTheKeychainInTheRealHome() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return XCTFail("no application-support directory")
        }
        let real = base.appendingPathComponent("Charms", isDirectory: true)
        XCTAssertTrue(GIFServiceKeyStores.make(supportDirectory: real, isIsolated: false) is KeychainGIFServiceKeyStore)
    }
}
