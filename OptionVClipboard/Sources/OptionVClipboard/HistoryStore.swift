import Foundation

/// Stores encrypted clipboard history and applies retention and deduplication rules.
final class HistoryStore {
    /// Errors thrown by history storage operations.
    private enum Error: Swift.Error {
        case emptyHistoryFile
    }

    private let settings: SettingsStore
    private let keychainStore: HistoryKeychainStoring
    private let cryptoStore: HistoryCrypting
    private let fileManager: FileManager
    private let historyFileName = "history.enc"
    private let blobDirectoryName = "items"
    private let lock = NSLock()
    private var cachedEncryptionKeyData: Data?

    /// The directory that contains the encrypted history file.
    let storageDirectoryURL: URL

    /// The clipboard history items, newest first.
    private(set) var items: [ClipboardItem] = []

    /// Creates a history store with explicit dependencies for testing and app wiring.
    init(
        settings: SettingsStore,
        keychainStore: HistoryKeychainStoring,
        cryptoStore: HistoryCrypting,
        fileManager: FileManager,
        applicationSupportDirectory: URL
    ) {
        self.settings = settings
        self.keychainStore = keychainStore
        self.cryptoStore = cryptoStore
        self.fileManager = fileManager
        self.storageDirectoryURL = applicationSupportDirectory.appendingPathComponent("OptionVClipboard", isDirectory: true)
    }

    /// Creates a history store with the default keychain, crypto, and application support locations.
    convenience init(settings: SettingsStore) {
        let fileManager = FileManager.default
        let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        self.init(
            settings: settings,
            keychainStore: KeychainStore(),
            cryptoStore: CryptoStore(),
            fileManager: fileManager,
            applicationSupportDirectory: applicationSupportDirectory
        )
    }

    /// The URL of the encrypted history file on disk.
    private var historyFileURL: URL {
        storageDirectoryURL.appendingPathComponent(historyFileName, isDirectory: false)
    }

    /// The directory that contains encrypted per-item pasteboard payload blobs.
    private var blobDirectoryURL: URL {
        storageDirectoryURL.appendingPathComponent(blobDirectoryName, isDirectory: true)
    }

    /// Loads and decrypts the history file into memory.
    func load() throws {
        lock.lock()
        defer { lock.unlock() }

        let historyURL = historyFileURL
        guard fileManager.fileExists(atPath: historyURL.path) else {
            items = []
            return
        }

        let encryptedData = try Data(contentsOf: historyURL)
        guard encryptedData.isEmpty == false else {
            throw Error.emptyHistoryFile
        }

        let keyData = try encryptionKeyData()
        let decryptedData = try cryptoStore.decrypt(encryptedData, using: keyData)
        let decodedHistory = try decodeHistory(from: decryptedData, using: keyData)
        let decodedItems = decodedHistory.items
        let normalizedItems = normalize(decodedItems, currentDate: Date())
        items = normalizedItems

        if decodedHistory.requiresMigration || normalizedItems != decodedItems {
            try persistLocked()
        }
    }

    /// Adds a plain-text clipboard item, moving exact duplicates to the top.
    @discardableResult
    func addText(_ text: String, source: String?) throws -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else {
            return false
        }

        return try addItem(ClipboardItem(text: text, source: source))
    }

    /// Adds a clipboard item, moving exact duplicates to the top.
    @discardableResult
    func addItem(_ item: ClipboardItem) throws -> Bool {
        guard shouldStore(item) else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        let originalItems = items
        var updatedItems = items
        let now = Date()

        if let existingIndex = updatedItems.firstIndex(where: { $0.hasSamePayload(as: item) }) {
            let existingItem = updatedItems.remove(at: existingIndex)
            updatedItems.insert(existingItem.movedToTop(createdAt: now, source: item.source), at: 0)
        } else {
            updatedItems.insert(item.movedToTop(createdAt: now, source: item.source), at: 0)
        }

        updatedItems = normalize(updatedItems, currentDate: now)
        items = updatedItems

        do {
            try persistLocked()
            return true
        } catch {
            items = originalItems
            throw error
        }
    }

    /// Moves an existing item to the top after the user copies or pastes it from history.
    @discardableResult
    func markItemAsUsed(_ item: ClipboardItem) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let originalItems = items
        var updatedItems = items
        let now = Date()
        let existingIndex = updatedItems.firstIndex { candidate in
            candidate.id == item.id
        } ?? updatedItems.firstIndex { candidate in
            candidate.hasSamePayload(as: item)
        }

        guard let existingIndex else {
            return false
        }

        let existingItem = updatedItems.remove(at: existingIndex)
        updatedItems.insert(existingItem.movedToTop(createdAt: now, source: existingItem.source), at: 0)

        items = normalize(updatedItems, currentDate: now)

        do {
            try persistLocked()
            return true
        } catch {
            items = originalItems
            throw error
        }
    }

    /// Clears in-memory history and persists an encrypted empty history file.
    func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        let originalItems = items
        items = []

        do {
            try persistLocked()
        } catch {
            items = originalItems
            throw error
        }
    }

    private func normalize(_ candidates: [ClipboardItem], currentDate: Date) -> [ClipboardItem] {
        let retentionThreshold = Calendar.current.date(byAdding: .day, value: -settings.retentionDays, to: currentDate) ?? currentDate
        var seenTexts = Set<String>()
        var normalizedItems: [ClipboardItem] = []
        var storedDataSize = 0
        normalizedItems.reserveCapacity(min(candidates.count, settings.maxHistoryItems))

        for item in candidates {
            guard item.createdAt >= retentionThreshold else {
                continue
            }

            if item.contentKind == .text {
                guard seenTexts.insert(item.text).inserted else {
                    continue
                }
            } else {
                guard normalizedItems.contains(where: { $0.hasSamePayload(as: item) }) == false else {
                    continue
                }
            }

            let nextStoredDataSize = storedDataSize + item.storedDataSize
            guard nextStoredDataSize <= settings.maxStorageSizeBytes else {
                continue
            }

            normalizedItems.append(item)
            storedDataSize = nextStoredDataSize

            if normalizedItems.count == settings.maxHistoryItems {
                break
            }
        }

        return normalizedItems
    }

    private func shouldStore(_ item: ClipboardItem) -> Bool {
        if item.contentKind == .text {
            let trimmedText = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedText.isEmpty == false else {
                return false
            }

            guard SecretFilter(skipShortOneTimeCodes: settings.skipShortOneTimeCodes).shouldReject(item.text) == false else {
                return false
            }
        }

        return item.storedDataSize <= settings.maxItemSizeBytes
            && item.storedDataSize <= settings.maxStorageSizeBytes
    }

    private func persistLocked() throws {
        try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: blobDirectoryURL, withIntermediateDirectories: true)

        let keyData = try encryptionKeyData()
        let persistedItems = try persistBlobs(for: items, using: keyData)
        let plaintextData = try JSONEncoder().encode(PersistedHistory(items: persistedItems))
        let encryptedData = try cryptoStore.encrypt(plaintextData, using: keyData)

        let temporaryURL = storageDirectoryURL.appendingPathComponent(".history.enc.\(UUID().uuidString)", isDirectory: false)
        try encryptedData.write(to: temporaryURL, options: [.atomic])

        let historyURL = historyFileURL
        if fileManager.fileExists(atPath: historyURL.path) {
            do {
                _ = try fileManager.replaceItemAt(historyURL, withItemAt: temporaryURL, backupItemName: nil, options: [])
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        } else {
            do {
                try fileManager.moveItem(at: temporaryURL, to: historyURL)
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        }

        try removeStaleBlobs(keeping: Set(persistedItems.map(\.blobFileName)))
    }

    private func decodeHistory(from data: Data, using keyData: Data) throws -> DecodedHistory {
        if let persistedHistory = try? JSONDecoder().decode(PersistedHistory.self, from: data) {
            var didDropUnrecoverableItem = false
            let items = persistedHistory.items.compactMap { persistedItem in
                do {
                    return try makeClipboardItem(from: persistedItem, using: keyData)
                } catch {
                    didDropUnrecoverableItem = true
                    NSLog(
                        "OptionVClipboard dropped history item with unreadable payload blob %@: %@",
                        persistedItem.blobFileName,
                        error.localizedDescription
                    )
                    return nil
                }
            }
            return DecodedHistory(items: items, requiresMigration: didDropUnrecoverableItem)
        }

        let legacyItems = try JSONDecoder().decode([ClipboardItem].self, from: data)
        return DecodedHistory(items: legacyItems, requiresMigration: true)
    }

    private func makeClipboardItem(from persistedItem: PersistedClipboardItem, using keyData: Data) throws -> ClipboardItem {
        let blobURL = blobDirectoryURL.appendingPathComponent(persistedItem.blobFileName, isDirectory: false)
        let encryptedBlobData = try Data(contentsOf: blobURL)
        let blobData = try cryptoStore.decrypt(encryptedBlobData, using: keyData)
        let pasteboardItems = try JSONDecoder().decode([ClipboardItem.StoredPasteboardItem].self, from: blobData)

        return ClipboardItem(
            id: persistedItem.id,
            text: persistedItem.text,
            createdAt: persistedItem.createdAt,
            source: persistedItem.source,
            contentKind: persistedItem.contentKind,
            pasteboardItems: pasteboardItems
        )
    }

    private func persistBlobs(for items: [ClipboardItem], using keyData: Data) throws -> [PersistedClipboardItem] {
        try items.map { item in
            let blobFileName = "\(item.id.uuidString).blob"
            try writeBlobIfNeeded(named: blobFileName, for: item, using: keyData)

            return PersistedClipboardItem(
                id: item.id,
                text: item.text,
                createdAt: item.createdAt,
                source: item.source,
                contentKind: item.contentKind,
                blobFileName: blobFileName,
                storedDataSize: item.storedDataSize
            )
        }
    }

    private func writeBlobIfNeeded(named blobFileName: String, for item: ClipboardItem, using keyData: Data) throws {
        let blobURL = blobDirectoryURL.appendingPathComponent(blobFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: blobURL.path) == false else {
            return
        }

        let blobData = try JSONEncoder().encode(item.pasteboardItems)
        let encryptedBlobData = try cryptoStore.encrypt(blobData, using: keyData)
        try replaceBlob(named: blobFileName, with: encryptedBlobData)
    }

    private func replaceBlob(named blobFileName: String, with encryptedBlobData: Data) throws {
        let blobURL = blobDirectoryURL.appendingPathComponent(blobFileName, isDirectory: false)
        let temporaryURL = blobDirectoryURL.appendingPathComponent(".\(blobFileName).\(UUID().uuidString)", isDirectory: false)
        try encryptedBlobData.write(to: temporaryURL, options: [.atomic])

        if fileManager.fileExists(atPath: blobURL.path) {
            do {
                _ = try fileManager.replaceItemAt(blobURL, withItemAt: temporaryURL, backupItemName: nil, options: [])
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        } else {
            do {
                try fileManager.moveItem(at: temporaryURL, to: blobURL)
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        }
    }

    private func removeStaleBlobs(keeping retainedBlobFileNames: Set<String>) throws {
        guard fileManager.fileExists(atPath: blobDirectoryURL.path) else {
            return
        }

        let blobURLs = try fileManager.contentsOfDirectory(
            at: blobDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for blobURL in blobURLs where retainedBlobFileNames.contains(blobURL.lastPathComponent) == false {
            try fileManager.removeItem(at: blobURL)
        }
    }

    private func encryptionKeyData() throws -> Data {
        if let cachedEncryptionKeyData {
            return cachedEncryptionKeyData
        }

        let keyData = try keychainStore.loadOrCreateEncryptionKey()
        cachedEncryptionKeyData = keyData
        return keyData
    }
}

private struct DecodedHistory {
    let items: [ClipboardItem]
    let requiresMigration: Bool
}

private struct PersistedHistory: Codable, Equatable {
    let version: Int
    let items: [PersistedClipboardItem]

    init(version: Int = 2, items: [PersistedClipboardItem]) {
        self.version = version
        self.items = items
    }
}

private struct PersistedClipboardItem: Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    let source: String?
    let contentKind: ClipboardItem.ContentKind
    let blobFileName: String
    let storedDataSize: Int
}
