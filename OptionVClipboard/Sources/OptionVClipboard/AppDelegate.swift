import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private lazy var historyStore = HistoryStore(settings: settingsStore)
    private lazy var clipboardWatcher = ClipboardWatcher(settings: settingsStore) { [weak self] text in
        self?.handleCapturedText(text)
    }
    private lazy var hotkeyManager = HotkeyManager()
    private lazy var historyWindowController = HistoryWindowController()
    private lazy var autoPasteController = AutoPasteController()

    private var statusItem: NSStatusItem?
    private weak var pauseResumeMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        loadHistory()
        startCaptureIfNeeded()
        registerHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardWatcher.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusBarImage()
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "OptionVClipboard"

        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(NSMenuItem(title: "Open History", action: #selector(openHistory(_:)), keyEquivalent: ""))

        let pauseResumeItem = NSMenuItem(title: captureToggleTitle, action: #selector(toggleCapture(_:)), keyEquivalent: "")
        menu.addItem(pauseResumeItem)
        pauseResumeMenuItem = pauseResumeItem

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Storage Folder", action: #selector(openStorageFolder(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp(_:)), keyEquivalent: ""))

        for menuItem in menu.items {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
        updateCaptureMenuTitle()
    }

    private func statusBarImage() -> NSImage? {
        if let imageURL = Bundle.main.url(forResource: "MenuBarLogo", withExtension: "png"),
           let image = NSImage(contentsOf: imageURL) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        let fallbackImage = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "OptionVClipboard")
        fallbackImage?.isTemplate = true
        return fallbackImage
    }

    private func loadHistory() {
        do {
            try historyStore.load()
        } catch {
            presentErrorAlert(
                title: "Unable to Load History",
                message: error.localizedDescription
            )
        }
    }

    private func startCaptureIfNeeded() {
        guard settingsStore.isCapturePaused == false else {
            return
        }

        clipboardWatcher.start()
    }

    private func registerHotkey() {
        do {
            try hotkeyManager.registerOptionV { [weak self] in
                DispatchQueue.main.async {
                    self?.openHistory(nil)
                }
            }
        } catch {
            presentErrorAlert(
                title: "Hotkey Registration Failed",
                message: error.localizedDescription
            )
        }
    }

    private func handleCapturedText(_ text: String) {
        do {
            _ = try historyStore.addText(text, source: nil)
        } catch {
            return
        }
    }

    private var captureToggleTitle: String {
        settingsStore.isCapturePaused ? "Resume Capture" : "Pause Capture"
    }

    private func updateCaptureMenuTitle() {
        pauseResumeMenuItem?.title = captureToggleTitle
    }

    @objc private func openHistory(_ sender: Any?) {
        let targetApplication = currentPasteTargetApplication()

        historyWindowController.show(items: historyStore.items) { [weak self] item in
            guard let self else {
                return false
            }

            return self.copyToPasteboard(item)
        } onPaste: { [weak self] item in
            guard let self else {
                return false
            }

            guard self.copyToPasteboard(item) else {
                return false
            }

            do {
                try self.autoPasteController.pasteIntoApplication(targetApplication)
                return true
            } catch {
                self.presentErrorAlert(
                    title: "Unable to Auto-Paste",
                    message: error.localizedDescription
                )
                return true
            }
        }
    }

    private func copyToPasteboard(_ item: ClipboardItem) -> Bool {
        autoPasteController.cancelPendingPaste()

        guard clipboardWatcher.writeToPasteboard(item.text) else {
            presentErrorAlert(
                title: "Unable to Copy Item",
                message: "OptionVClipboard could not write the selected item to the clipboard."
            )
            return false
        }

        do {
            _ = try historyStore.markItemAsUsed(item)
        } catch {
            NSLog("OptionVClipboard could not promote copied history item: \(error.localizedDescription)")
        }

        return true
    }

    private func currentPasteTargetApplication() -> NSRunningApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        return application
    }

    @objc private func toggleCapture(_ sender: Any?) {
        settingsStore.isCapturePaused.toggle()

        if settingsStore.isCapturePaused {
            clipboardWatcher.stop()
        } else {
            clipboardWatcher.start()
        }

        updateCaptureMenuTitle()
    }

    @objc private func clearHistory(_ sender: Any?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This removes the saved items from the encrypted history store."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try historyStore.clear()
            historyWindowController.closePicker()
        } catch {
            presentErrorAlert(
                title: "Unable to Clear History",
                message: error.localizedDescription
            )
        }
    }

    @objc private func openStorageFolder(_ sender: Any?) {
        do {
            try FileManager.default.createDirectory(
                at: historyStore.storageDirectoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(historyStore.storageDirectoryURL)
        } catch {
            presentErrorAlert(
                title: "Unable to Open Storage Folder",
                message: error.localizedDescription
            )
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
