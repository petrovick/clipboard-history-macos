import AppKit
import Foundation

/// A clipboard entry retained in encrypted history.
struct ClipboardItem: Codable, Equatable, Identifiable {
    /// The broad content category used for display, filtering, and validation.
    enum ContentKind: String, Codable {
        case text
        case image
        case fileURLs
    }

    /// One concrete pasteboard representation for a single pasteboard item.
    struct PasteboardRepresentation: Codable, Equatable {
        let type: String
        let data: Data

        init(type: String, data: Data) {
            self.type = type
            self.data = data
        }
    }

    /// The serializable contents of one `NSPasteboardItem`.
    struct StoredPasteboardItem: Codable, Equatable {
        let representations: [PasteboardRepresentation]

        init(representations: [PasteboardRepresentation]) {
            self.representations = representations
        }
    }

    let id: UUID
    let text: String
    let createdAt: Date
    let source: String?
    let contentKind: ContentKind
    let pasteboardItems: [StoredPasteboardItem]

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        source: String? = nil,
        contentKind: ContentKind = .text,
        pasteboardItems: [StoredPasteboardItem]? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.source = source
        self.contentKind = contentKind
        self.pasteboardItems = pasteboardItems ?? [
            StoredPasteboardItem(
                representations: [
                    PasteboardRepresentation(
                        type: NSPasteboard.PasteboardType.string.rawValue,
                        data: Data(text.utf8)
                    )
                ]
            )
        ]
    }

    /// The total number of raw pasteboard bytes stored for this history item.
    var storedDataSize: Int {
        pasteboardItems.reduce(0) { itemTotal, item in
            itemTotal + item.representations.reduce(0) { representationTotal, representation in
                representationTotal + representation.data.count
            }
        }
    }

    /// A displayable image built from the first stored image representation.
    var previewImage: NSImage? {
        guard contentKind == .image else {
            return nil
        }

        for representation in pasteboardItems.flatMap(\.representations) {
            if let image = NSImage(data: representation.data) {
                return image
            }
        }

        return nil
    }

    /// Returns whether the item's pasteboard payload matches another item's payload.
    func hasSamePayload(as other: ClipboardItem) -> Bool {
        contentKind == other.contentKind && pasteboardItems == other.pasteboardItems
    }

    /// Returns a copy of this item moved to a new history date/source.
    func movedToTop(createdAt: Date, source: String?) -> ClipboardItem {
        ClipboardItem(
            id: id,
            text: text,
            createdAt: createdAt,
            source: source ?? self.source,
            contentKind: contentKind,
            pasteboardItems: pasteboardItems
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt
        case source
        case contentKind
        case pasteboardItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        contentKind = try container.decodeIfPresent(ContentKind.self, forKey: .contentKind) ?? .text
        pasteboardItems = try container.decodeIfPresent([StoredPasteboardItem].self, forKey: .pasteboardItems) ?? [
            StoredPasteboardItem(
                representations: [
                    PasteboardRepresentation(
                        type: NSPasteboard.PasteboardType.string.rawValue,
                        data: Data(text.utf8)
                    )
                ]
            )
        ]
    }
}
