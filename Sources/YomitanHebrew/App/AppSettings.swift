import Combine
import Foundation
import YomitanCore

@MainActor
final class AppSettings: ObservableObject {
    static let defaultDeckName = "Hebrew::Pealim"
    static let defaultModelName = "Hebrew Pealim"

    private enum Key {
        static let deckName = "anki.deckName"
        static let modelName = "anki.modelName"
        static let hotKey = "hotKey.configuration"
    }

    @Published var deckName: String {
        didSet { defaults.set(deckName, forKey: Key.deckName) }
    }

    @Published var modelName: String {
        didSet { defaults.set(modelName, forKey: Key.modelName) }
    }

    @Published var apiKey: String {
        didSet { KeychainStore.set(apiKey, account: "anki-connect-api-key") }
    }

    @Published var hotKey: HotKeyConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Key.hotKey)
            }
        }
    }

    /// Ephemeral UI state used to temporarily release the active system hotkey
    /// while the recorder is listening for a replacement.
    @Published var isRecordingHotKey = false
    @Published var hotKeyRegistrationError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deckName = defaults.string(forKey: Key.deckName) ?? Self.defaultDeckName
        modelName = defaults.string(forKey: Key.modelName) ?? Self.defaultModelName
        apiKey = KeychainStore.value(account: "anki-connect-api-key") ?? ""
        if let data = defaults.data(forKey: Key.hotKey),
           let savedHotKey = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) {
            hotKey = savedHotKey
        } else {
            hotKey = .default
        }
    }
}
