import Foundation
import Testing
@testable import OptionVClipboard

@Suite
struct HistoryStoreTests {
    private final class MockKeychainStore: HistoryKeychainStoring {
        let keyData: Data
        var loadCount = 0

        init(keyData: Data) {
            self.keyData = keyData
        }

        func loadOrCreateEncryptionKey() throws -> Data {
            loadCount += 1
            return keyData
        }
    }

    private func makeTemporarySupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSettings(maxItems: Int = 100, retentionDays: Int = 7, skipShortOneTimeCodes: Bool = true) -> SettingsStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.maxHistoryItems = maxItems
        settings.maxItemSizeBytes = 100 * 1024
        settings.retentionDays = retentionDays
        settings.skipShortOneTimeCodes = skipShortOneTimeCodes
        settings.isCapturePaused = false
        return settings
    }

    private func makeStore(
        settings: SettingsStore = SettingsStore(),
        supportDirectory: URL? = nil,
        keyData: Data = Data(repeating: 1, count: 32)
    ) throws -> (HistoryStore, MockKeychainStore, URL) {
        let fileManager = FileManager.default
        let applicationSupportDirectory: URL
        if let supportDirectory {
            applicationSupportDirectory = supportDirectory
        } else {
            applicationSupportDirectory = try makeTemporarySupportDirectory()
        }
        let keychainStore = MockKeychainStore(keyData: keyData)
        let store = HistoryStore(
            settings: settings,
            keychainStore: keychainStore,
            cryptoStore: CryptoStore(),
            fileManager: fileManager,
            applicationSupportDirectory: applicationSupportDirectory
        )

        return (store, keychainStore, applicationSupportDirectory)
    }

    @Test
    func addTextMovesDuplicateItemToTop() throws {
        let settings = makeSettings()
        let (store, _, supportDirectory) = try makeStore(settings: settings)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addText("one", source: "Notes")
        try store.addText("two", source: "Safari")
        try store.addText("one", source: nil)

        #expect(store.items.map(\.text) == ["one", "two"])
        #expect(store.items.first?.source == "Notes")
        #expect(store.items.count == 2)
    }

    @Test
    func markItemAsUsedMovesExistingItemToTop() throws {
        let settings = makeSettings()
        let (store, _, supportDirectory) = try makeStore(settings: settings)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addText("one", source: "Notes")
        try store.addText("two", source: "Safari")
        let olderItem = try #require(store.items.last)

        try store.markItemAsUsed(olderItem)

        #expect(store.items.map(\.text) == ["one", "two"])
        #expect(store.items.first?.id == olderItem.id)
        #expect(store.items.first?.source == "Notes")
    }

    @Test
    func addTextReusesCachedEncryptionKey() throws {
        let settings = makeSettings()
        let (store, keychainStore, supportDirectory) = try makeStore(settings: settings)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addText("one", source: nil)
        try store.addText("two", source: nil)

        #expect(keychainStore.loadCount == 1)
    }

    @Test
    func loadRoundTripsEncryptedHistory() throws {
        let settings = makeSettings()
        let (store, _, supportDirectory) = try makeStore(settings: settings)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addText("alpha", source: "Terminal")
        try store.addText("beta", source: nil)

        let reloadedStore = HistoryStore(
            settings: settings,
            keychainStore: MockKeychainStore(keyData: Data(repeating: 1, count: 32)),
            cryptoStore: CryptoStore(),
            fileManager: FileManager.default,
            applicationSupportDirectory: supportDirectory
        )

        try reloadedStore.load()

        #expect(reloadedStore.items.map(\.text) == ["beta", "alpha"])
        #expect(reloadedStore.items.first?.source == nil)
    }

    @Test
    func retentionAndCountAreEnforcedOnLoad() throws {
        let settings = makeSettings(maxItems: 2, retentionDays: 1)
        let supportDirectory = try makeTemporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let items = [
            ClipboardItem(text: "current-a", createdAt: now, source: nil),
            ClipboardItem(text: "current-b", createdAt: now.addingTimeInterval(-1), source: nil),
            ClipboardItem(text: "old", createdAt: oldDate, source: nil)
        ]
        let payload = try JSONEncoder().encode(items)
        let encrypted = try CryptoStore().encrypt(payload, using: Data(repeating: 2, count: 32))

        let storageDirectory = supportDirectory.appendingPathComponent("OptionVClipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try encrypted.write(to: storageDirectory.appendingPathComponent("history.enc"), options: [.atomic])

        let store = HistoryStore(
            settings: settings,
            keychainStore: MockKeychainStore(keyData: Data(repeating: 2, count: 32)),
            cryptoStore: CryptoStore(),
            fileManager: FileManager.default,
            applicationSupportDirectory: supportDirectory
        )

        try store.load()

        #expect(store.items.map(\.text) == ["current-a", "current-b"])
        #expect(store.items.count == 2)
    }

    @Test
    func clearPersistsEncryptedEmptyHistory() throws {
        let settings = makeSettings()
        let (store, _, supportDirectory) = try makeStore(settings: settings)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addText("secret", source: nil)
        try store.clear()

        #expect(store.items.isEmpty)

        let historyURL = supportDirectory
            .appendingPathComponent("OptionVClipboard", isDirectory: true)
            .appendingPathComponent("history.enc")
        let encryptedData = try Data(contentsOf: historyURL)
        #expect(String(decoding: encryptedData, as: UTF8.self).contains("secret") == false)

        let reloadedStore = HistoryStore(
            settings: settings,
            keychainStore: MockKeychainStore(keyData: Data(repeating: 1, count: 32)),
            cryptoStore: CryptoStore(),
            fileManager: FileManager.default,
            applicationSupportDirectory: supportDirectory
        )

        try reloadedStore.load()
        #expect(reloadedStore.items.isEmpty)
    }
}
