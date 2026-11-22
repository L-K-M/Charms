import CharmsCore
import XCTest
@testable import Charms

@MainActor
final class VeniceArtworkServiceTests: XCTestCase {
    private let key = "venice-test-key-0123456789"
    private var directory: URL!
    private var preferences: PreferencesStore!
    private var secrets: RecordingSecrets!
    private var client: RecordingClient!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CharmsVenice-\(UUID().uuidString)", isDirectory: true)
        preferences = PreferencesStore(paths: AppPaths(supportDirectory: directory, isIsolated: true))
        secrets = RecordingSecrets()
        client = RecordingClient()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeService() -> VeniceArtworkService {
        VeniceArtworkService(preferences: preferences, keys: VeniceKeyStore(secrets: secrets), client: client)
    }

    private func assertFailure(_ expected: VeniceImageError, _ service: VeniceArtworkService, description: String = "a cat") async {
        do {
            _ = try await service.generate(description: description)
            XCTFail("expected \(expected)")
        } catch {
            XCTAssertEqual(error as? VeniceImageError, expected)
        }
        XCTAssertEqual(client.count, 0)
    }

    func testSwitchedOffMeansNoKeyReadAndNoRequest() async {
        secrets.value = key
        await assertFailure(.turnedOff, makeService())
        XCTAssertEqual(secrets.reads, 0)
    }

    func testSavingAKeyDoesNotSwitchVeniceOn() {
        let service = makeService()
        XCTAssertNil(service.setKey(key))
        XCTAssertTrue(service.hasKey)
        XCTAssertFalse(preferences.value.veniceImagesEnabled)
    }

    func testCheckingForAKeyNeverReadsIt() {
        secrets.value = key
        let service = makeService()
        XCTAssertEqual(secrets.reads, 0, "nothing is read at launch")
        service.refreshKeyPresence()
        XCTAssertTrue(service.hasKey)
        XCTAssertEqual(secrets.reads, 0)
    }

    func testRemovingTheKeySwitchesVeniceOff() {
        let service = makeService()
        XCTAssertNil(service.setKey(key))
        preferences.update { $0.veniceImagesEnabled = true }
        XCTAssertNil(service.setKey(nil))
        XCTAssertFalse(service.hasKey)
        XCTAssertFalse(preferences.value.veniceImagesEnabled)
    }

    func testGenerateSendsTheChosenModelOnce() async throws {
        secrets.value = key
        preferences.update {
            $0.veniceImagesEnabled = true
            $0.veniceModel = .gptImageFlare
            $0.veniceQuality = .medium
        }
        let data = try await makeService().generate(description: "a cat")
        XCTAssertEqual(data, RecordingClient.image)
        XCTAssertEqual(client.count, 1)
        XCTAssertEqual(client.lastRequest?.model, .gptImageFlare)
        XCTAssertEqual(client.lastRequest?.quality, .medium)
        XCTAssertEqual(client.lastKey, key)
    }

    func testNothingIsSentWithoutAKeyOrADescription() async {
        preferences.update { $0.veniceImagesEnabled = true }
        await assertFailure(.missingKey, makeService())
        secrets.value = key
        await assertFailure(.emptyDescription, makeService(), description: "  ")
    }

    func testADeniedKeychainReadIsReportedAndSendsNothing() async {
        preferences.update { $0.veniceImagesEnabled = true }
        secrets.failure = .keychain(errSecUserCanceled)
        await assertFailure(.keyUnreadable, makeService())
    }

    func testSwitchingOffWhileTheKeychainAsksSendsNothing() async {
        secrets.value = key
        preferences.update { $0.veniceImagesEnabled = true }
        let preferences = preferences!
        secrets.whileReading = {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { preferences.update { $0.veniceImagesEnabled = false } }
            }
        }
        await assertFailure(.turnedOff, makeService())
    }
}

private final class RecordingSecrets: SecretStoring, @unchecked Sendable {
    var value: String?
    var failure: SecretStoreError?
    var whileReading: (() -> Void)?
    private(set) var reads = 0

    func secret(for account: String) throws -> String? {
        reads += 1
        whileReading?()
        if let failure { throw failure }
        return value
    }

    func containsSecret(for account: String) -> Bool { value != nil }
    func setSecret(_ secret: String?, for account: String) throws { value = secret }
}

private final class RecordingClient: VeniceImageGenerating, @unchecked Sendable {
    static let image = Data([1, 2, 3])
    private(set) var count = 0
    private(set) var lastRequest: VeniceImageRequest?
    private(set) var lastKey: String?

    func image(for request: VeniceImageRequest, key: String) async throws -> Data {
        count += 1
        lastRequest = request
        lastKey = key
        return Self.image
    }
}
