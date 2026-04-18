import Foundation

/// Stores privacy-oriented user preferences for capture and retention.
final class SettingsStore {
    private enum Key {
        static let isCapturePaused = "isCapturePaused"
        static let maxHistoryItems = "maxHistoryItems"
        static let maxItemSizeBytes = "maxItemSizeBytes"
        static let retentionDays = "retentionDays"
        static let skipShortOneTimeCodes = "skipShortOneTimeCodes"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var isCapturePaused: Bool {
        get { defaults.bool(forKey: Key.isCapturePaused) }
        set { defaults.set(newValue, forKey: Key.isCapturePaused) }
    }

    var maxHistoryItems: Int {
        get { defaults.integer(forKey: Key.maxHistoryItems) }
        set { defaults.set(max(1, newValue), forKey: Key.maxHistoryItems) }
    }

    var maxItemSizeBytes: Int {
        get { defaults.integer(forKey: Key.maxItemSizeBytes) }
        set { defaults.set(max(1, newValue), forKey: Key.maxItemSizeBytes) }
    }

    var retentionDays: Int {
        get { defaults.integer(forKey: Key.retentionDays) }
        set { defaults.set(max(1, newValue), forKey: Key.retentionDays) }
    }

    var skipShortOneTimeCodes: Bool {
        get { defaults.bool(forKey: Key.skipShortOneTimeCodes) }
        set { defaults.set(newValue, forKey: Key.skipShortOneTimeCodes) }
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.isCapturePaused: false,
            Key.maxHistoryItems: 100,
            Key.maxItemSizeBytes: 100 * 1024,
            Key.retentionDays: 7,
            Key.skipShortOneTimeCodes: true
        ])
    }
}
