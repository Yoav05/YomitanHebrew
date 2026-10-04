import Foundation

/// Platform-independent modifier flags for a global keyboard shortcut.
public struct HotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
}

/// A persistable description of a global keyboard shortcut.
///
/// `keyCode` is the macOS hardware-independent virtual key code. `keyLabel` is
/// stored with it so the shortcut remains understandable without consulting the
/// current keyboard layout when it is displayed later.
public struct HotKeyConfiguration: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: HotKeyModifiers
    public var keyLabel: String

    public init(
        keyCode: UInt32,
        modifiers: HotKeyModifiers,
        keyLabel: String? = nil
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers

        if let keyLabel, !keyLabel.isEmpty {
            self.keyLabel = keyLabel
        } else {
            self.keyLabel = Self.keyLabel(for: keyCode)
        }
    }

    /// The shortcut used before a custom preference has been saved: ⌥⌘H.
    public static let `default` = Self(
        keyCode: 4,
        modifiers: [.option, .command],
        keyLabel: "H"
    )

    /// A compact representation matching the modifier order used in macOS menus.
    public var displayString: String {
        var result = ""

        if modifiers.contains(.control) {
            result += "⌃"
        }
        if modifiers.contains(.option) {
            result += "⌥"
        }
        if modifiers.contains(.shift) {
            result += "⇧"
        }
        if modifiers.contains(.command) {
            result += "⌘"
        }

        return result + keyLabel
    }

    /// Produces a user-facing key name without depending on AppKit or Carbon.
    ///
    /// Pass keyboard-layout-aware characters when they are available from an
    /// input event. Special keys are identified by key code; printable event
    /// characters take precedence over the US-layout fallback table.
    public static func keyLabel(
        for keyCode: UInt32,
        characters: String? = nil
    ) -> String {
        if let specialLabel = specialKeyLabels[keyCode] {
            return specialLabel
        }

        if let characters,
           let characterLabel = printableKeyLabel(from: characters) {
            return characterLabel
        }

        return printableKeyLabels[keyCode] ?? "Key \(keyCode)"
    }

    private static func printableKeyLabel(from characters: String) -> String? {
        guard let firstCharacter = characters.first else {
            return nil
        }

        let label = String(firstCharacter)
        let containsWhitespaceOrControl = label.unicodeScalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
        }
        guard !containsWhitespaceOrControl else {
            return nil
        }

        return label.uppercased()
    }

    // macOS virtual key codes. Keeping the values here makes YomitanCore usable
    // without linking either AppKit or Carbon.
    private static let printableKeyLabels: [UInt32: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        25: "9",
        26: "7",
        28: "8",
        29: "0",
        31: "O",
        32: "U",
        34: "I",
        35: "P",
        37: "L",
        38: "J",
        40: "K",
        45: "N",
        46: "M",
    ]

    private static let specialKeyLabels: [UInt32: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Esc",
        64: "F17",
        79: "F18",
        80: "F19",
        90: "F20",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        118: "F4",
        120: "F2",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
    ]
}
