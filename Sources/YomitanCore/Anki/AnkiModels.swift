import Foundation

public typealias AnkiDeckID = Int64
public typealias AnkiModelID = Int64
public typealias AnkiNoteID = Int64

public struct AnkiCardTemplateDraft: Codable, Equatable, Sendable {
    public var name: String
    public var front: String
    public var back: String

    public init(name: String, front: String, back: String) {
        self.name = name
        self.front = front
        self.back = back
    }

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case front = "Front"
        case back = "Back"
    }
}

/// The inputs accepted by AnkiConnect's `createModel` action.
public struct AnkiModelDraft: Codable, Equatable, Sendable {
    public var modelName: String
    public var inOrderFields: [String]
    public var css: String?
    public var isCloze: Bool
    public var cardTemplates: [AnkiCardTemplateDraft]

    public init(
        modelName: String,
        inOrderFields: [String],
        css: String? = nil,
        isCloze: Bool = false,
        cardTemplates: [AnkiCardTemplateDraft]
    ) {
        self.modelName = modelName
        self.inOrderFields = inOrderFields
        self.css = css
        self.isCloze = isCloze
        self.cardTemplates = cardTemplates
    }
}

/// The editable field and tag content that the app presents as an Anki card.
///
/// AnkiConnect ultimately creates a note, which can generate one or more cards.
/// Keeping this smaller draft separate lets callers map any Anki note type without
/// hard-coding field names in the networking layer.
public struct AnkiCardDraft: Codable, Equatable, Sendable {
    public var fields: [String: String]
    public var tags: [String]

    public init(
        fields: [String: String],
        tags: [String] = []
    ) {
        self.fields = fields
        self.tags = tags
    }
}

public struct AnkiDuplicateScopeOptions: Codable, Equatable, Sendable {
    public var deckName: String?
    public var checkChildren: Bool?
    public var checkAllModels: Bool?

    public init(
        deckName: String? = nil,
        checkChildren: Bool? = nil,
        checkAllModels: Bool? = nil
    ) {
        self.deckName = deckName
        self.checkChildren = checkChildren
        self.checkAllModels = checkAllModels
    }
}

/// Options shared by AnkiConnect's `addNote` and `guiAddCards` payloads.
/// Unsupported options are omitted instead of being sent as `null`.
public struct AnkiNoteOptions: Codable, Equatable, Sendable {
    public var allowDuplicate: Bool?
    public var duplicateScope: String?
    public var duplicateScopeOptions: AnkiDuplicateScopeOptions?
    public var closeAfterAdding: Bool?

    public init(
        allowDuplicate: Bool? = nil,
        duplicateScope: String? = nil,
        duplicateScopeOptions: AnkiDuplicateScopeOptions? = nil,
        closeAfterAdding: Bool? = nil
    ) {
        self.allowDuplicate = allowDuplicate
        self.duplicateScope = duplicateScope
        self.duplicateScopeOptions = duplicateScopeOptions
        self.closeAfterAdding = closeAfterAdding
    }
}

/// An API-ready Anki note with arbitrary model fields.
public struct AnkiNote: Codable, Equatable, Sendable {
    public var deckName: String
    public var modelName: String
    public var fields: [String: String]
    public var tags: [String]
    public var options: AnkiNoteOptions?

    public init(
        deckName: String,
        modelName: String,
        fields: [String: String],
        tags: [String] = [],
        options: AnkiNoteOptions? = nil
    ) {
        self.deckName = deckName
        self.modelName = modelName
        self.fields = fields
        self.tags = tags
        self.options = options
    }

    public init(
        deckName: String,
        modelName: String,
        fields: [String: String],
        tags: [String] = [],
        allowDuplicate: Bool
    ) {
        self.init(
            deckName: deckName,
            modelName: modelName,
            fields: fields,
            tags: tags,
            options: AnkiNoteOptions(allowDuplicate: allowDuplicate)
        )
    }

    public init(
        deckName: String,
        modelName: String,
        card: AnkiCardDraft,
        options: AnkiNoteOptions? = nil
    ) {
        self.init(
            deckName: deckName,
            modelName: modelName,
            fields: card.fields,
            tags: card.tags,
            options: options
        )
    }

    public var card: AnkiCardDraft {
        get {
            AnkiCardDraft(fields: fields, tags: tags)
        }
        set {
            fields = newValue.fields
            tags = newValue.tags
        }
    }
}

/// Explicit draft spelling for call sites that distinguish editable and saved notes.
public typealias AnkiNoteDraft = AnkiNote
