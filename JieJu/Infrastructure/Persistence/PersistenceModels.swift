import Foundation

struct PersistenceLibrary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var readingProgress: [ReadingProgress]
    var savedExplanations: [SavedExplanationRecord]
    var vocabularyEntries: [VocabularyEntry]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        readingProgress: [ReadingProgress] = [],
        savedExplanations: [SavedExplanationRecord] = [],
        vocabularyEntries: [VocabularyEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.readingProgress = readingProgress
        self.savedExplanations = savedExplanations
        self.vocabularyEntries = vocabularyEntries
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, readingProgress, savedExplanations, vocabularyEntries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        readingProgress = try container.decode([ReadingProgress].self, forKey: .readingProgress)
        savedExplanations = try container.decode([SavedExplanationRecord].self, forKey: .savedExplanations)
        vocabularyEntries = try container.decodeIfPresent([VocabularyEntry].self, forKey: .vocabularyEntries) ?? []
    }
}

struct DocumentIdentity: Codable, Equatable, Hashable, Sendable {
    let id: String
    var fileName: String
    var fingerprint: String?

    init(id: String, fileName: String, fingerprint: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.fingerprint = fingerprint
    }
}

struct ReadingProgress: Codable, Equatable, Sendable {
    var document: DocumentIdentity
    var pageIndex: Int
    var updatedAt: Date

    init(document: DocumentIdentity, pageIndex: Int, updatedAt: Date = Date()) {
        self.document = document
        self.pageIndex = pageIndex
        self.updatedAt = updatedAt
    }
}

struct PersistedExplanationRequest: Codable, Equatable, Sendable {
    var targetText: String
    var precedingContext: String?
    var followingContext: String?
    var sourceLanguage: String
    var explanationLanguage: String
}

struct PersistedGrammarPoint: Codable, Equatable, Sendable {
    var title: String
    var explanation: String
}

struct PersistedKeyPhrase: Codable, Equatable, Sendable {
    var text: String
    var meaning: String
    var example: String?
}

struct PersistedExplanation: Codable, Equatable, Sendable {
    var translation: String
    var sentenceCore: String
    var grammarPoints: [PersistedGrammarPoint]
    var keyPhrases: [PersistedKeyPhrase]
    var modelName: String?
}

struct SavedExplanationRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var document: DocumentIdentity
    var pageIndex: Int?
    var request: PersistedExplanationRequest
    var explanation: PersistedExplanation
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        document: DocumentIdentity,
        pageIndex: Int? = nil,
        request: PersistedExplanationRequest,
        explanation: PersistedExplanation,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.document = document
        self.pageIndex = pageIndex
        self.request = request
        self.explanation = explanation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct VocabularySense: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var meaning: String
    var explanationLanguage: String

    init(id: UUID = UUID(), meaning: String, explanationLanguage: String) {
        self.id = id
        self.meaning = meaning
        self.explanationLanguage = explanationLanguage
    }
}

struct VocabularySource: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var document: DocumentIdentity
    var pageIndex: Int?
    var sentence: String
    var surface: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        document: DocumentIdentity,
        pageIndex: Int? = nil,
        sentence: String,
        surface: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.document = document
        self.pageIndex = pageIndex
        self.sentence = sentence
        self.surface = surface
        self.createdAt = createdAt
    }
}

struct VocabularyEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var language: String
    var lemma: String
    var reading: String?
    var partOfSpeech: String?
    var surfaceForms: [String]
    var senses: [VocabularySense]
    var sources: [VocabularySource]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        language: String,
        lemma: String,
        reading: String? = nil,
        partOfSpeech: String? = nil,
        surfaceForms: [String],
        senses: [VocabularySense],
        sources: [VocabularySource],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.language = language
        self.lemma = lemma
        self.reading = reading
        self.partOfSpeech = partOfSpeech
        self.surfaceForms = surfaceForms
        self.senses = senses
        self.sources = sources
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
