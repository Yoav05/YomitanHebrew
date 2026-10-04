import SwiftUI
import YomitanCore

struct LookupView: View {
    @ObservedObject var model: LookupViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.showsSettings {
                SettingsView(settings: model.settings)
                    .padding(20)
            } else {
                content
            }
        }
        .frame(minWidth: 620, minHeight: 430)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.book.closed")
                .font(.title2)
                .foregroundStyle(.tint)

            TextField("Слово на иврите", text: $model.query)
                .font(.system(size: 20))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.lookup() } }

            Button("Найти") {
                Task { await model.lookup() }
            }
            .keyboardShortcut(.return, modifiers: [])

            Button {
                model.showsSettings.toggle()
            } label: {
                Image(systemName: model.showsSettings ? "xmark" : "gearshape")
            }
            .help(model.showsSettings ? "Закрыть настройки" : "Настройки")
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            placeholder(
                icon: "selection.pin.in.out",
                title: "Выделите слово в любом приложении",
                message: "Нажмите \(model.settings.hotKey.displayString), чтобы найти его в Pealim."
            )
        case .readingSelection:
            progress("Читаю выделенный текст…")
        case .searching:
            progress("Ищу «\(model.query)» в Pealim…")
        case .empty:
            placeholder(
                icon: "questionmark.circle",
                title: "Ничего не найдено",
                message: "Проверьте написание или попробуйте словарную форму."
            )
        case .failed(let message):
            placeholder(icon: "exclamationmark.triangle", title: "Не получилось", message: message)
        case .results:
            results
        }
    }

    private var results: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.results) { result in
                        ResultRow(
                            result: result,
                            isSelected: result.id == model.selectedResult?.id
                        ) {
                            model.select(result)
                        }
                    }
                }
                .padding(12)
            }
            .frame(minWidth: 265, idealWidth: 290)

            Divider()

            if let result = model.selectedResult {
                ResultDetail(
                    result: result,
                    query: model.query,
                    meaning: $model.draftMeaning,
                    transcription: $model.draftTranscription,
                    grammar: $model.draftGrammar,
                    ankiPhase: model.ankiPhase,
                    openSource: model.openSelectedResult,
                    addToAnki: { openEditor in
                        Task { await model.addToAnki(openEditor: openEditor) }
                    }
                )
                .frame(minWidth: 310, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func progress(_ title: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ResultRow: View {
    let result: PealimSearchResult
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.lemma)
                        .font(.title3)
                        .environment(\.layoutDirection, .rightToLeft)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                Text(result.meaning)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(result.partOfSpeech)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ResultDetail: View {
    let result: PealimSearchResult
    let query: String
    @Binding var meaning: String
    @Binding var transcription: String
    @Binding var grammar: String
    let ankiPhase: LookupViewModel.AnkiPhase
    let openSource: () -> Void
    let addToAnki: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.lemma)
                    .font(.system(size: 34, weight: .semibold))
                    .environment(\.layoutDirection, .rightToLeft)
                Spacer()
                if let transcription = result.transcription {
                    Text(transcription)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Перевод", text: $meaning)
                .font(.title3)

            TextField("Транскрипция", text: $transcription)
                .textFieldStyle(.roundedBorder)

            Divider()

            TextField("Грамматика", text: $grammar)
                .textFieldStyle(.roundedBorder)
            if query != result.lemma {
                LabeledContent("Запрос", value: query)
            }

            Spacer()

            ankiStatus

            HStack {
                Button("Открыть Pealim", action: openSource)
                Spacer()
                Button("Редактировать в Anki") {
                    addToAnki(true)
                }
                .disabled(ankiPhase == .working)

                Button("Добавить") {
                    addToAnki(false)
                }
                .buttonStyle(.borderedProminent)
                .disabled(ankiPhase == .working || meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private var ankiStatus: some View {
        switch ankiPhase {
        case .idle:
            EmptyView()
        case .working:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("Связываюсь с Anki…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .added:
            Label("Карточка добавлена в Anki", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .editorOpened:
            Label("Окно добавления открыто в Anki", systemImage: "rectangle.on.rectangle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
