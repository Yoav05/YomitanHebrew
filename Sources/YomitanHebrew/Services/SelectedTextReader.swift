import AppKit
@preconcurrency import ApplicationServices
import Foundation

struct SelectedTextReader {
    enum SelectionError: LocalizedError {
        case accessibilityPermissionRequired
        case noSelection

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                return "Разрешите приложению управление компьютером в Системных настройках → Конфиденциальность и безопасность → Универсальный доступ."
            case .noSelection:
                return "Не удалось прочитать выделенный текст. Выделите слово и повторите горячую клавишу."
            }
        }
    }

    func readSelection(promptForPermission: Bool = true) async throws -> String {
        guard isTrusted(prompt: promptForPermission) else {
            throw SelectionError.accessibilityPermissionRequired
        }

        if let directSelection = accessibilitySelection(), !directSelection.isEmpty {
            return directSelection
        }

        if let copiedSelection = await clipboardSelection(), !copiedSelection.isEmpty {
            return copiedSelection
        }

        throw SelectionError.noSelection
    }

    private func isTrusted(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func accessibilitySelection() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else {
            return nil
        }

        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success else {
            return nil
        }

        return normalized(selectedValue as? String)
    }

    /// Fallback for apps (notably some web/electron views) that do not expose
    /// `AXSelectedText`. The existing clipboard contents are restored afterwards.
    @MainActor
    private func clipboardSelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let marker = "yomitan-hebrew-\(UUID().uuidString)"

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        let markerChangeCount = pasteboard.changeCount

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            snapshot.restore(to: pasteboard)
            return nil
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        for _ in 0..<10 {
            guard pasteboard.changeCount == markerChangeCount else { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        let copied = pasteboard.string(forType: .string)
        snapshot.restore(to: pasteboard)

        guard copied != marker else { return nil }
        return normalized(copied)
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let surroundingPunctuation = CharacterSet(charactersIn: ".,!?;:…“”\"'()[]{}<>")
        let value = text.trimmingCharacters(
            in: .whitespacesAndNewlines.union(surroundingPunctuation)
        )
        guard !value.isEmpty else { return nil }
        return value
    }
}

private struct PasteboardSnapshot {
    private struct Item {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    private let items: [Item]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            let values = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return Item(values: values)
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { item -> NSPasteboardItem in
            let restored = NSPasteboardItem()
            for value in item.values {
                restored.setData(value.data, forType: value.type)
            }
            return restored
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
