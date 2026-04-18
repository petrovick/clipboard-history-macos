import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Activates the app that was focused before the picker opened and posts Command+V.
@MainActor
final class AutoPasteController {
    enum AutoPasteError: LocalizedError {
        case missingTargetApplication
        case accessibilityPermissionRequired
        case activationRequestFailed
        case keyboardEventCreationFailed

        var errorDescription: String? {
            switch self {
            case .missingTargetApplication:
                return "OptionVClipboard could not find the app that was active before the history picker opened."
            case .accessibilityPermissionRequired:
                return "Auto-paste requires Accessibility permission. macOS should show a permission prompt; after enabling OptionVClipboard, try again."
            case .activationRequestFailed:
                return "OptionVClipboard could not activate the app that was active before the history picker opened."
            case .keyboardEventCreationFailed:
                return "OptionVClipboard could not create the keyboard event needed for auto-paste."
            }
        }
    }

    private struct PendingPaste {
        let processIdentifier: pid_t
        let observer: NSObjectProtocol
        let timeoutTask: Task<Void, Never>
    }

    private var pendingPaste: PendingPaste?

    deinit {
        MainActor.assumeIsolated {
            clearPendingPaste()
        }
    }

    func cancelPendingPaste() {
        clearPendingPaste()
    }

    func pasteIntoApplication(_ application: NSRunningApplication?) throws {
        guard let application else {
            throw AutoPasteError.missingTargetApplication
        }

        guard Self.requestAccessibilityPermissionIfNeeded() else {
            throw AutoPasteError.accessibilityPermissionRequired
        }

        clearPendingPaste()

        let processIdentifier = application.processIdentifier
        if application.isActive {
            try Self.postCommandV(to: processIdentifier)
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        let observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            let activatedProcessIdentifier = application.processIdentifier
            Task { @MainActor in
                self?.handleActivatedApplication(processIdentifier: activatedProcessIdentifier)
            }
        }

        let timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }

            self?.clearPendingPaste(for: processIdentifier)
        }

        pendingPaste = PendingPaste(
            processIdentifier: processIdentifier,
            observer: observer,
            timeoutTask: timeoutTask
        )

        guard activate(application) else {
            clearPendingPaste()
            throw AutoPasteError.activationRequestFailed
        }
    }

    private func handleActivatedApplication(processIdentifier: pid_t) {
        guard let pendingPaste,
              processIdentifier == pendingPaste.processIdentifier else {
            return
        }

        do {
            try Self.postCommandV(to: pendingPaste.processIdentifier)
        } catch {
            NSApp.presentError(error)
        }

        clearPendingPaste()
    }

    private func clearPendingPaste(for processIdentifier: pid_t? = nil) {
        guard let pendingPaste else {
            return
        }

        guard processIdentifier == nil || pendingPaste.processIdentifier == processIdentifier else {
            return
        }

        NSWorkspace.shared.notificationCenter.removeObserver(pendingPaste.observer)
        pendingPaste.timeoutTask.cancel()
        self.pendingPaste = nil
    }

    private func activate(_ application: NSRunningApplication) -> Bool {
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: application)
            return application.activate(from: .current, options: [])
        }

        return application.activate(options: [.activateIgnoringOtherApps])
    }

    private static func requestAccessibilityPermissionIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    private static func postCommandV(to processIdentifier: pid_t) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            throw AutoPasteError.keyboardEventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
    }
}
