import Foundation
import Testing
@testable import YomitanCore

@Suite("Hot-key configuration")
struct HotKeyConfigurationTests {
    @Test("Default shortcut is Option-Command-H")
    func defaultShortcut() {
        let configuration = HotKeyConfiguration.default

        #expect(configuration.keyCode == 4)
        #expect(configuration.modifiers == [.option, .command])
        #expect(configuration.keyLabel == "H")
        #expect(configuration.displayString == "⌥⌘H")
    }

    @Test("Display uses the macOS modifier order and glyphs")
    func displayString() {
        let configuration = HotKeyConfiguration(
            keyCode: 0,
            modifiers: [.command, .shift, .option, .control],
            keyLabel: "A"
        )

        #expect(configuration.displayString == "⌃⌥⇧⌘A")
    }

    @Test("Configuration and modifier flags survive a Codable round trip")
    func codableRoundTrip() throws {
        let original = HotKeyConfiguration(
            keyCode: 122,
            modifiers: [.control, .shift],
            keyLabel: "F1"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyConfiguration.self, from: data)

        #expect(decoded == original)
        #expect(decoded.modifiers.contains(.control))
        #expect(decoded.modifiers.contains(.shift))
        #expect(!decoded.modifiers.contains(.command))
    }

    @Test("Letters and digits have US-layout fallback labels")
    func printableFallbackLabels() {
        #expect(HotKeyConfiguration.keyLabel(for: 0) == "A")
        #expect(HotKeyConfiguration.keyLabel(for: 4) == "H")
        #expect(HotKeyConfiguration.keyLabel(for: 46) == "M")
        #expect(HotKeyConfiguration.keyLabel(for: 18) == "1")
        #expect(HotKeyConfiguration.keyLabel(for: 29) == "0")
    }

    @Test("Special keys have readable labels")
    func specialKeyLabels() {
        #expect(HotKeyConfiguration.keyLabel(for: 123) == "←")
        #expect(HotKeyConfiguration.keyLabel(for: 124) == "→")
        #expect(HotKeyConfiguration.keyLabel(for: 125) == "↓")
        #expect(HotKeyConfiguration.keyLabel(for: 126) == "↑")
        #expect(HotKeyConfiguration.keyLabel(for: 122) == "F1")
        #expect(HotKeyConfiguration.keyLabel(for: 90) == "F20")
        #expect(HotKeyConfiguration.keyLabel(for: 49) == "Space")
        #expect(HotKeyConfiguration.keyLabel(for: 48) == "Tab")
        #expect(HotKeyConfiguration.keyLabel(for: 36) == "Return")
        #expect(HotKeyConfiguration.keyLabel(for: 51) == "Delete")
        #expect(HotKeyConfiguration.keyLabel(for: 53) == "Esc")
    }

    @Test("Event characters respect the active keyboard layout")
    func eventCharacterLabel() {
        #expect(HotKeyConfiguration.keyLabel(for: 4, characters: "h") == "H")
        #expect(HotKeyConfiguration.keyLabel(for: 4, characters: "י") == "י")
        #expect(HotKeyConfiguration.keyLabel(for: 200, characters: "/") == "/")
        #expect(HotKeyConfiguration.keyLabel(for: 200, characters: "") == "Key 200")
        #expect(HotKeyConfiguration.keyLabel(for: 200, characters: "\n") == "Key 200")
    }

    @Test("An omitted label is derived from the key code")
    func derivedInitializerLabel() {
        let configuration = HotKeyConfiguration(
            keyCode: 13,
            modifiers: [.command]
        )

        #expect(configuration.keyLabel == "W")
        #expect(configuration.displayString == "⌘W")
    }
}
