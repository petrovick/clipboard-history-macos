import AppKit
import Foundation
import Testing
@testable import OptionVClipboard

@Suite
@MainActor
struct ClipboardWatcherTests {
    private func makeSettings() -> SettingsStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.maxItemSizeBytes = 10 * 1024 * 1024
        settings.isCapturePaused = false
        return settings
    }

    @Test
    func writeToPasteboardRestoresImageRepresentation() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }

        let imageData = Data([1, 2, 3, 4])
        let item = ClipboardItem(
            text: "Image",
            contentKind: .image,
            pasteboardItems: [
                ClipboardItem.StoredPasteboardItem(
                    representations: [
                        ClipboardItem.PasteboardRepresentation(type: NSPasteboard.PasteboardType.png.rawValue, data: imageData)
                    ]
                )
            ]
        )
        let watcher = ClipboardWatcher(settings: makeSettings(), pasteboard: pasteboard) { _ in }

        #expect(watcher.writeToPasteboard(item))

        let restoredData = try #require(pasteboard.pasteboardItems?.first?.data(forType: .png))
        #expect(restoredData == imageData)
    }

    @Test
    func writeToPasteboardRestoresFileURLRepresentation() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }

        let fileURLString = URL(fileURLWithPath: "/tmp/example.txt").absoluteString
        let fileURLData = Data(fileURLString.utf8)
        let item = ClipboardItem(
            text: "File: example.txt",
            contentKind: .fileURLs,
            pasteboardItems: [
                ClipboardItem.StoredPasteboardItem(
                    representations: [
                        ClipboardItem.PasteboardRepresentation(
                            type: NSPasteboard.PasteboardType.fileURL.rawValue,
                            data: fileURLData
                        )
                    ]
                )
            ]
        )
        let watcher = ClipboardWatcher(settings: makeSettings(), pasteboard: pasteboard) { _ in }

        #expect(watcher.writeToPasteboard(item))

        let restoredData = try #require(pasteboard.pasteboardItems?.first?.data(forType: .fileURL))
        #expect(restoredData == fileURLData)
    }

    @Test
    func pollPasteboardSkipsConcealedBinaryItemsBeforeCapture() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }

        var capturedItem: ClipboardItem?
        let watcher = ClipboardWatcher(settings: makeSettings(), pasteboard: pasteboard) { item in
            capturedItem = item
        }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Data([1, 2, 3]), forType: .png)
        pasteboardItem.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))

        pasteboard.clearContents()
        pasteboard.writeObjects([pasteboardItem])
        watcher.pollPasteboard()

        #expect(capturedItem == nil)
    }

    @Test
    func pollPasteboardCapturesPromisedFileURLRepresentation() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }

        let promisedFileURLType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        let fileURL = URL(fileURLWithPath: "/tmp/promised.txt")
        var capturedItem: ClipboardItem?
        let watcher = ClipboardWatcher(settings: makeSettings(), pasteboard: pasteboard) { item in
            capturedItem = item
        }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Data(fileURL.absoluteString.utf8), forType: promisedFileURLType)

        pasteboard.clearContents()
        pasteboard.writeObjects([pasteboardItem])
        watcher.pollPasteboard()

        let item = try #require(capturedItem)
        #expect(item.contentKind == .fileURLs)
        #expect(item.text == "[File] promised.txt")
        #expect(item.pasteboardItems.first?.representations.first?.type == promisedFileURLType.rawValue)
    }
}
