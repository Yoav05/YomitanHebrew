import Carbon.HIToolbox
import Foundation
import YomitanCore

/// A system-wide hot key backed by Carbon's event API.
///
/// Carbon is old, but this small API remains the least invasive way to register
/// a global shortcut: unlike an event tap it does not monitor all keyboard input.
@MainActor
final class GlobalHotKey {
    enum RegistrationError: LocalizedError {
        case eventHandler(OSStatus)
        case hotKey(OSStatus)

        var errorDescription: String? {
            switch self {
            case .eventHandler(let status):
                return "Не удалось установить обработчик горячей клавиши (код \(status))."
            case .hotKey(let status):
                return "Не удалось зарегистрировать горячую клавишу (код \(status))."
            }
        }
    }

    private static let signature: OSType = 0x5948_4252 // "YHBR"
    private static let identifier: UInt32 = 1

    private let action: @MainActor () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    init(
        configuration: HotKeyConfiguration,
        action: @escaping @MainActor () -> Void
    ) throws {
        self.action = action
        try install(
            keyCode: configuration.keyCode,
            modifiers: configuration.modifiers.carbonFlags
        )
    }

    func invalidate() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func install(keyCode: UInt32, modifiers: UInt32) throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                var eventID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventID
                )
                guard status == noErr,
                      eventID.signature == GlobalHotKey.signature,
                      eventID.id == GlobalHotKey.identifier else {
                    return OSStatus(eventNotHandledErr)
                }

                let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    owner.action()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw RegistrationError.eventHandler(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard hotKeyStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            throw RegistrationError.hotKey(hotKeyStatus)
        }
    }
}

private extension HotKeyModifiers {
    var carbonFlags: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}
