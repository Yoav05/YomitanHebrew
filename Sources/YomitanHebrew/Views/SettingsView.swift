import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var recorderValidationMessage: String?

    var body: some View {
        Form {
            Section("AnkiConnect") {
                TextField("Колода", text: $settings.deckName)
                TextField("Тип заметки", text: $settings.modelName)
                SecureField("API key (необязательно)", text: $settings.apiKey)
                Text("По умолчанию приложение использует локальный AnkiConnect на 127.0.0.1:8765. Ключ хранится в Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Горячая клавиша") {
                LabeledContent("Поиск выделенного слова") {
                    HotKeyRecorderView(
                        configuration: $settings.hotKey,
                        isRecording: $settings.isRecordingHotKey,
                        validationMessage: $recorderValidationMessage
                    )
                    .frame(minWidth: 175)
                }

                if let message = recorderValidationMessage ?? settings.hotKeyRegistrationError {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Нажмите на сочетание, затем введите новое. Escape отменяет запись.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Вернуть ⌥⌘H") {
                    recorderValidationMessage = nil
                    settings.hotKey = .default
                }
                .disabled(settings.hotKey == .default || settings.isRecordingHotKey)
            }
        }
        .formStyle(.grouped)
    }
}
