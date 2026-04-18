import Foundation

/// A plain-text clipboard entry retained in encrypted history.
struct ClipboardItem: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
    let source: String?

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), source: String? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.source = source
    }
}
