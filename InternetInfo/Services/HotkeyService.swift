import Carbon
import Foundation

final class HotkeyService: @unchecked Sendable {
    static let signature: OSType = 0x49494E46 // 'IINF'
    static let toggleID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var keyCode: UInt32
    private var modifiers: UInt32
    private let identifier: UInt32
    private let onPressed: @MainActor () -> Void

    private static nonisolated(unsafe) var instances: [UInt32: HotkeyService] = [:]
    private static nonisolated(unsafe) var handlerRef: EventHandlerRef?

    init(identifier: UInt32, keyCode: UInt32, modifiers: UInt32, onPressed: @escaping @MainActor () -> Void) {
        self.identifier = identifier
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.onPressed = onPressed
        HotkeyService.instances[identifier] = self
    }

    deinit {
        unregister()
        HotkeyService.instances[identifier] = nil
    }

    func register(keyCode: UInt32? = nil, modifiers: UInt32? = nil) {
        unregister()
        if let keyCode { self.keyCode = keyCode }
        if let modifiers { self.modifiers = modifiers }

        Self.installHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            self.keyCode,
            self.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
        HotkeyService.instances[identifier] = self
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private static func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHandler,
            1,
            &eventType,
            nil,
            &ref
        )
        if status == noErr {
            handlerRef = ref
        }
    }

    private static let carbonHandler: EventHandlerUPP = { _, event, _ in
        var hotKeyID = EventHotKeyID()
        let err = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard err == noErr, let service = HotkeyService.instances[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            service.onPressed()
        }
        return noErr
    }
}
