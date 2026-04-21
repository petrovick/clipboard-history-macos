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

    private func makeSettings(
        maxItems: Int = 100,
        maxItemSizeBytes: Int = 100 * 1024,
        maxStorageSizeBytes: Int = 500 * 1024 * 1024,
        retentionDays: Int = 7,
        skipShortOneTimeCodes: Bool = true
    ) -> SettingsStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.maxHistoryItems = maxItems
        settings.maxItemSizeBytes = maxItemSizeBytes
        settings.maxStorageSizeBytes = maxStorageSizeBytes
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

    private func makeImageItem(
        id: UUID = UUID(),
        data: Data = Data([0x89, 0x50, 0x4E, 0x47]),
        createdAt: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            text: "Image",
            createdAt: createdAt,
            source: nil,
            contentKind: .image,
            pasteboardItems: [
                ClipboardItem.StoredPasteboardItem(
                    representations: [
                        ClipboardItem.PasteboardRepresentation(type: "public.png", data: data)
                    ]
                )
            ]
        )
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
    func addItemMovesDuplicateImagePayloadToTop() throws {
        let settings = makeSettings()
        let (store, _, supportDirectory) = try makeStore(settings: settings)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addText("text", source: nil)
        try store.addItem(makeImageItem(data: Data([1, 2, 3])))
        try store.addItem(makeImageItem(data: Data([1, 2, 3])))

        #expect(store.items.count == 2)
        #expect(store.items.first?.contentKind == .image)
        #expect(store.items.first?.pasteboardItems.first?.representations.first?.data == Data([1, 2, 3]))
    }

    @Test
    func addItemEvictsOlderEntriesOverStorageSizeLimit() throws {
        let settings = makeSettings(maxItemSizeBytes: 100, maxStorageSizeBytes: 4)
        let (store, _, supportDirectory) = try makeStore(settings: settings)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addItem(makeImageItem(data: Data([1, 2, 3])))
        try store.addItem(makeImageItem(data: Data([4, 5, 6])))

        #expect(store.items.count == 1)
        #expect(store.items.first?.pasteboardItems.first?.representations.first?.data == Data([4, 5, 6]))
    }

    @Test
    func addItemSkipsItemsLargerThanStorageSizeLimit() throws {
        let settings = makeSettings(maxItemSizeBytes: 100, maxStorageSizeBytes: 2)
        let (store, _, supportDirectory) = try makeStore(settings: settings)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let didStore = try store.addItem(makeImageItem(data: Data([1, 2, 3])))

        #expect(didStore == false)
        #expect(store.items.isEmpty)
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
    func markItemAsUsedPreservesStoredPayload() throws {
        let settings = makeSettings()
        let (store, _, supportDirectory) = try makeStore(settings: settings)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addText("text", source: nil)
        try store.addItem(makeImageItem(data: Data([4, 5, 6])))
        let imageItem = try #require(store.items.first)

        try store.markItemAsUsed(imageItem)

        #expect(store.items.first?.contentKind == .image)
        #expect(store.items.first?.pasteboardItems == imageItem.pasteboardItems)
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
    func addItemPersistsPayloadInEncryptedBlobOutsideHistoryMetadata() throws {
        let settings = makeSettings()
        let keyData = Data(repeating: 4, count: 32)
        let (store, _, supportDirectory) = try makeStore(settings: settings, keyData: keyData)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addItem(makeImageItem(data: Data([1, 2, 3])))

        let storageDirectory = supportDirectory.appendingPathComponent("OptionVClipboard", isDirectory: true)
        let historyURL = storageDirectory.appendingPathComponent("history.enc")
        let decryptedHistory = try CryptoStore().decrypt(Data(contentsOf: historyURL), using: keyData)
        let metadata = String(decoding: decryptedHistory, as: UTF8.self)
        let blobURLs = try FileManager.default.contentsOfDirectory(
            at: storageDirectory.appendingPathComponent("items", isDirectory: true),
            includingPropertiesForKeys: nil
        )

        #expect(metadata.contains("blobFileName"))
        #expect(metadata.contains("pasteboardItems") == false)
        #expect(metadata.contains("AQID") == false)
        #expect(blobURLs.count == 1)
        #expect(try Data(contentsOf: blobURLs[0]).range(of: Data([1, 2, 3])) == nil)
    }

    @Test
    func markItemAsUsedDoesNotRewriteExistingBlob() throws {
        let settings = makeSettings()
        let keyData = Data(repeating: 5, count: 32)
        let (store, _, supportDirectory) = try makeStore(settings: settings, keyData: keyData)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        try store.addItem(makeImageItem(data: Data([7, 8, 9])))
        let imageItem = try #require(store.items.first)
        let blobURL = supportDirectory
            .appendingPathComponent("OptionVClipboard", isDirectory: true)
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent("\(imageItem.id.uuidString).blob")
        let originalBlobData = try Data(contentsOf: blobURL)

        try store.markItemAsUsed(imageItem)

        let promotedBlobData = try Data(contentsOf: blobURL)
        #expect(promotedBlobData == originalBlobData)
    }

    @Test
    func loadSkipsItemsWithMissingPayloadBlob() throws {
        let settings = makeSettings()
        let keyData = Data(repeating: 6, count: 32)
        let (store, _, supportDirectory) = try makeStore(settings: settings, keyData: keyData)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let missingItem = makeImageItem(id: UUID(), data: Data([1, 2, 3]))
        let keptItem = makeImageItem(id: UUID(), data: Data([4, 5, 6]))

        try store.addItem(missingItem)
        try store.addItem(keptItem)

        let storageDirectory = supportDirectory.appendingPathComponent("OptionVClipboard", isDirectory: true)
        let missingBlobURL = storageDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent("\(missingItem.id.uuidString).blob")
        try FileManager.default.removeItem(at: missingBlobURL)

        let reloadedStore = HistoryStore(
            settings: settings,
            keychainStore: MockKeychainStore(keyData: keyData),
            cryptoStore: CryptoStore(),
            fileManager: FileManager.default,
            applicationSupportDirectory: supportDirectory
        )

        try reloadedStore.load()

        let reloadedItem = try #require(reloadedStore.items.first)
        #expect(reloadedStore.items.count == 1)
        #expect(reloadedItem.id == keptItem.id)
        #expect(reloadedItem.pasteboardItems.first?.representations.first?.data == Data([4, 5, 6]))

        let historyURL = storageDirectory.appendingPathComponent("history.enc")
        let decryptedHistory = try CryptoStore().decrypt(Data(contentsOf: historyURL), using: keyData)
        let metadata = String(decoding: decryptedHistory, as: UTF8.self)
        #expect(metadata.contains(keptItem.id.uuidString))
        #expect(metadata.contains(missingItem.id.uuidString) == false)
    }

    @Test
    func loadMigratesLegacyTextHistory() throws {
        struct LegacyClipboardItem: Codable {
            let id: UUID
            let text: String
            let createdAt: Date
            let source: String?
        }

        let settings = makeSettings()
        let supportDirectory = try makeTemporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let legacyItems = [
            LegacyClipboardItem(id: UUID(), text: "legacy", createdAt: Date(), source: nil)
        ]
        let payload = try JSONEncoder().encode(legacyItems)
        let encrypted = try CryptoStore().encrypt(payload, using: Data(repeating: 3, count: 32))

        let storageDirectory = supportDirectory.appendingPathComponent("OptionVClipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try encrypted.write(to: storageDirectory.appendingPathComponent("history.enc"), options: [.atomic])

        let store = HistoryStore(
            settings: settings,
            keychainStore: MockKeychainStore(keyData: Data(repeating: 3, count: 32)),
            cryptoStore: CryptoStore(),
            fileManager: FileManager.default,
            applicationSupportDirectory: supportDirectory
        )

        try store.load()

        let item = try #require(store.items.first)
        #expect(item.text == "legacy")
        #expect(item.contentKind == .text)
        #expect(item.pasteboardItems.first?.representations.first?.type == "public.utf8-plain-text")

        let historyURL = storageDirectory.appendingPathComponent("history.enc")
        let decryptedHistory = try CryptoStore().decrypt(Data(contentsOf: historyURL), using: Data(repeating: 3, count: 32))
        let metadata = String(decoding: decryptedHistory, as: UTF8.self)
        #expect(metadata.contains("blobFileName"))
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
