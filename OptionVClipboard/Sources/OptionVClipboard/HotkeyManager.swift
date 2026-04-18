import AppKit
import Carbon.HIToolbox
import Foundation

private let optionVHotKeySignature = fourCharCode("OVCL")
private let optionVHotKeyID = EventHotKeyID(signature: optionVHotKeySignature, id: 1)

/// Registers the global Option+V hotkey without touching Command+V.
final class HotkeyManager {
    enum HotkeyError: LocalizedError {
        case eventHandlerRegistrationFailed(OSStatus)
        case hotKeyRegistrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .eventHandlerRegistrationFailed(status):
                return "Failed to install the hotkey event handler. OSStatus \(status)."
            case let .hotKeyRegistrationFailed(status):
                return "Failed to register Option+V. OSStatus \(status)."
            }
        }
    }

    private let lock = NSLock()
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?

    deinit {
        unregister()
    }

    func registerOptionV(handler: @escaping () -> Void) throws {
        unregister()

        let appTarget = GetApplicationEventTarget()
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            appTarget,
            optionVHotKeyCallback,
            1,
            &eventSpec,
            selfPointer,
            &eventHandler
        )

        guard handlerStatus == noErr else {
            throw HotkeyError.eventHandlerRegistrationFailed(handlerStatus)
        }

        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(optionKey),
            optionVHotKeyID,
            appTarget,
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            throw HotkeyError.hotKeyRegistrationFailed(hotKeyStatus)
        }

        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func unregister() {
        lock.lock()
        let eventHandler = self.eventHandler
        let hotKeyRef = self.hotKeyRef
        self.eventHandler = nil
        self.hotKeyRef = nil
        handler = nil
        lock.unlock()

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    fileprivate func invokeHandler() {
        let handler = readHandler()
        handler?()
    }

    private func readHandler() -> (() -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}

private let optionVHotKeyCallback: EventHandlerProcPtr = { _, eventRef, userData in
    guard let eventRef, let userData else {
        return noErr
    }

    var eventHotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &eventHotKeyID
    )

    guard status == noErr else {
        return status
    }

    guard eventHotKeyID.signature == optionVHotKeySignature,
          eventHotKeyID.id == optionVHotKeyID.id else {
        return noErr
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.invokeHandler()
    return noErr
}

private func fourCharCode(_ string: String) -> FourCharCode {
    precondition(string.utf8.count == 4, "FourCharCode requires exactly four ASCII characters.")

    return string.utf8.reduce(0) { partialResult, byte in
        (partialResult << 8) | FourCharCode(byte)
    }
}
