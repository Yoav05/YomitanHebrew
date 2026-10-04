import AppKit
import Foundation
import YomitanCore

@MainActor
final class LookupViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case readingSelection
        case searching
        case results
        case empty
        case failed(String)
    }

    enum AnkiPhase: Equatable {
        case idle
        case working
        case added(AnkiNoteID)
        case editorOpened
        case failed(String)
    }

    @Published var query = ""
    @Published private(set) var results: [PealimSearchResult] = []
    @Published var selectedResultID: String?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var ankiPhase: AnkiPhase = .idle
    @Published var draftMeaning = ""
    @Published var draftTranscription = ""
    @Published var draftGrammar = ""
    @Published var showsSettings = false

    let settings: AppSettings
    private let pealim: PealimClient
    private var lookupGeneration = UUID()

    init(
        settings: AppSettings,
        pealim: PealimClient = PealimClient()
    ) {
        self.settings = settings
        self.pealim = pealim
    }

    var selectedResult: PealimSearchResult? {
        guard let selectedResultID else { return results.first }
        return results.first { $0.id == selectedResultID }
    }

    func beginReadingSelection() {
        lookupGeneration = UUID()
        phase = .readingSelection
        showsSettings = false
    }

    func show(error: Error) {
        lookupGeneration = UUID()
        results = []
        selectedResultID = nil
        phase = .failed(error.localizedDescription)
    }

    func lookup(_ text: String? = nil) async {
        if let text {
            query = String(text.prefix(160))
        }

        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            phase = .failed("Введите слово на иврите.")
            return
        }

        phase = .searching
        showsSettings = false
        let generation = UUID()
        lookupGeneration = generation
        do {
            let response = try await pealim.search(normalized)
            guard lookupGeneration == generation else { return }
            results = response.results
            selectedResultID = response.results.first?.id
            if let first = response.results.first {
                loadDraft(from: first)
            }
            phase = response.results.isEmpty ? .empty : .results
        } catch {
            guard lookupGeneration == generation else { return }
            results = []
            selectedResultID = nil
            phase = .failed("Pealim недоступен: \(error.localizedDescription)")
        }
    }

    func select(_ result: PealimSearchResult) {
        selectedResultID = result.id
        loadDraft(from: result)
    }

    func openSelectedResult() {
        guard let selectedResult else { return }
        NSWorkspace.shared.open(selectedResult.sourceURL)
    }

    func addToAnki(openEditor: Bool) async {
        guard let result = selectedResult, ankiPhase != .working else { return }
        let snapshot = AnkiCardSnapshot(
            result: result,
            query: query,
            meaning: draftMeaning,
            transcription: draftTranscription,
            grammar: draftGrammar,
            deckName: settings.deckName,
            modelName: settings.modelName
        )
        ankiPhase = .working

        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = AnkiClient(apiKey: key.isEmpty ? nil : key)

        do {
            let version = try await client.version()
            guard version >= 6 else {
                throw AnkiSetupError.unsupportedVersion(version)
            }

            _ = try await client.createDeck(snapshot.deckName)
            let models = try await client.modelNames()
            if !models.contains(snapshot.modelName) {
                guard snapshot.modelName == AppSettings.defaultModelName else {
                    throw AnkiSetupError.missingModel(snapshot.modelName)
                }
                _ = try await client.createModel(Self.pealimModel(named: snapshot.modelName))
            }

            let fieldNames = try await client.modelFieldNames(snapshot.modelName)
            let note = try makeNote(from: snapshot, fieldNames: fieldNames)
            if openEditor {
                _ = try await client.guiAddCards(note)
                ankiPhase = selectedResult?.id == snapshot.result.id && query == snapshot.query
                    ? .editorOpened
                    : .idle
            } else {
                let noteID = try await client.addNote(note)
                ankiPhase = selectedResult?.id == snapshot.result.id && query == snapshot.query
                    ? .added(noteID)
                    : .idle
            }
        } catch {
            ankiPhase = .failed(Self.ankiMessage(for: error))
        }
    }

    private func loadDraft(from result: PealimSearchResult) {
        draftMeaning = result.meaning
        draftTranscription = result.transcription ?? ""
        draftGrammar = [result.partOfSpeech, result.root.map { "корень: \($0)" }]
            .compactMap { $0 }
            .joined(separator: "; ")
        if ankiPhase != .working {
            ankiPhase = .idle
        }
    }

    private func makeNote(
        from snapshot: AnkiCardSnapshot,
        fieldNames: [String]
    ) throws -> AnkiNoteDraft {
        guard !fieldNames.isEmpty else { throw AnkiSetupError.modelHasNoFields }

        let result = snapshot.result
        let dictionaryHebrew = HebrewText.withoutNiqqud(result.lemma)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = HebrewText.withoutNiqqud(snapshot.query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedForm = HebrewText.containsHebrew(snapshot.query) && normalizedQuery != dictionaryHebrew
            ? snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let knownValues: [String: String] = [
            "EntryKey": result.sourceURL.absoluteString,
            "SelectedForm": selectedForm.htmlEscaped,
            "Hebrew": dictionaryHebrew.htmlEscaped,
            "Nikud": result.lemma.htmlEscaped,
            "Transliteration": snapshot.transcription.htmlEscaped,
            "Russian": snapshot.meaning.htmlEscaped,
            "Grammar": snapshot.grammar.htmlEscaped,
            "Examples": "",
            "SourceURL": result.sourceURL.absoluteString.htmlEscaped
        ]

        var fields = Dictionary(uniqueKeysWithValues: fieldNames.map { ($0, "") })
        let matchingKnownFields = fieldNames.filter { knownValues[$0] != nil }
        if matchingKnownFields.count >= 2 {
            for field in matchingKnownFields {
                fields[field] = knownValues[field]
            }
        } else {
            guard fieldNames.count >= 2 else {
                throw AnkiSetupError.modelNeedsTwoFields
            }
            fields[fieldNames[0]] = result.lemma.htmlEscaped
            fields[fieldNames[1]] = """
            <div>\(snapshot.meaning.htmlEscaped)</div>
            <div style="margin-top:8px;color:#666">\(snapshot.transcription.htmlEscaped)</div>
            <div style="margin-top:8px;color:#666">\(snapshot.grammar.htmlEscaped)</div>
            <div style="margin-top:10px"><a href="\(result.sourceURL.absoluteString.htmlEscaped)">Pealim</a></div>
            """
        }

        return AnkiNoteDraft(
            deckName: snapshot.deckName,
            modelName: snapshot.modelName,
            fields: fields,
            tags: ["hebrew", "pealim", "yomitan-hebrew"],
            allowDuplicate: false
        )
    }

    private static func ankiMessage(for error: Error) -> String {
        if case AnkiClientError.transport = error {
            return "Не удалось подключиться к AnkiConnect. Запустите Anki и установите дополнение 2055492159."
        }
        return error.localizedDescription
    }

    private static func pealimModel(named name: String) -> AnkiModelDraft {
        AnkiModelDraft(
            modelName: name,
            inOrderFields: [
                "EntryKey",
                "SelectedForm",
                "Hebrew",
                "Nikud",
                "Transliteration",
                "Russian",
                "Grammar",
                "Examples",
                "SourceURL"
            ],
            css: """
            .card {
              font-family: -apple-system, BlinkMacSystemFont, "Arial", sans-serif;
              font-size: 20px;
              text-align: center;
              color: #202124;
              background: #fff;
            }
            .hebrew { direction: rtl; font-size: 42px; line-height: 1.4; }
            .lemma { direction: rtl; font-size: 28px; margin-top: 12px; }
            .transcription, .grammar, .source, .label { color: #687078; margin-top: 10px; }
            .meaning { font-size: 25px; margin: 16px 0; }
            .nightMode .card { color: #f2f2f2; background: #242424; }
            """,
            cardTemplates: [
                AnkiCardTemplateDraft(
                    name: "Hebrew → Russian",
                    front: """
                    {{#SelectedForm}}<div class="hebrew">{{SelectedForm}}</div>{{/SelectedForm}}
                    {{^SelectedForm}}{{#Nikud}}<div class="hebrew">{{Nikud}}</div>{{/Nikud}}{{/SelectedForm}}
                    {{^SelectedForm}}{{^Nikud}}<div class="hebrew">{{Hebrew}}</div>{{/Nikud}}{{/SelectedForm}}
                    """,
                    back: """
                    {{FrontSide}}
                    <hr id="answer">
                    <div class="meaning">{{Russian}}</div>
                    {{#Transliteration}}<div class="transcription">{{Transliteration}}</div>{{/Transliteration}}
                    {{#SelectedForm}}<div class="label">Словарная форма</div><div class="lemma">{{Nikud}}</div>{{/SelectedForm}}
                    {{#Grammar}}<div class="grammar">{{Grammar}}</div>{{/Grammar}}
                    {{#Examples}}<div class="examples">{{Examples}}</div>{{/Examples}}
                    {{#SourceURL}}<div class="source"><a href="{{SourceURL}}">Pealim</a></div>{{/SourceURL}}
                    """
                )
            ]
        )
    }
}

private struct AnkiCardSnapshot {
    let result: PealimSearchResult
    let query: String
    let meaning: String
    let transcription: String
    let grammar: String
    let deckName: String
    let modelName: String
}

private enum AnkiSetupError: LocalizedError {
    case unsupportedVersion(Int)
    case missingModel(String)
    case modelHasNoFields
    case modelNeedsTwoFields

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Нужен AnkiConnect API 6, найден API \(version)."
        case .missingModel(let name):
            return "В Anki нет типа заметки «\(name)». Выберите существующий тип в настройках или создайте его."
        case .modelHasNoFields:
            return "У выбранного типа заметки Anki нет полей."
        case .modelNeedsTwoFields:
            return "Для карточки нужен тип заметки минимум с двумя полями."
        }
    }
}
