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
        let decodedItems = try JSONDecoder().decode([ClipboardItem].self, from: decryptedData)
        let normalizedItems = normalize(decodedItems, currentDate: Date())
        items = normalizedItems

        if normalizedItems != decodedItems {
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

        guard text.utf8.count <= settings.maxItemSizeBytes else {
            return false
        }

        guard SecretFilter(skipShortOneTimeCodes: settings.skipShortOneTimeCodes).shouldReject(text) == false else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        let originalItems = items
        var updatedItems = items
        let now = Date()

        if let existingIndex = updatedItems.firstIndex(where: { $0.text == text }) {
            let existingItem = updatedItems.remove(at: existingIndex)
            let replacementItem = ClipboardItem(
                id: existingItem.id,
                text: existingItem.text,
                createdAt: now,
                source: source ?? existingItem.source
            )
            updatedItems.insert(replacementItem, at: 0)
        } else {
            updatedItems.insert(ClipboardItem(text: text, createdAt: now, source: source), at: 0)
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
            candidate.text == item.text
        }

        guard let existingIndex else {
            return false
        }

        let existingItem = updatedItems.remove(at: existingIndex)
        updatedItems.insert(
            ClipboardItem(
                id: existingItem.id,
                text: existingItem.text,
                createdAt: now,
                source: existingItem.source
            ),
            at: 0
        )

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
        normalizedItems.reserveCapacity(min(candidates.count, settings.maxHistoryItems))

        for item in candidates {
            guard item.createdAt >= retentionThreshold else {
                continue
            }

            guard seenTexts.insert(item.text).inserted else {
                continue
            }

            normalizedItems.append(item)

            if normalizedItems.count == settings.maxHistoryItems {
                break
            }
        }

        return normalizedItems
    }

    private func persistLocked() throws {
        try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)

        let plaintextData = try JSONEncoder().encode(items)
        let keyData = try encryptionKeyData()
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
