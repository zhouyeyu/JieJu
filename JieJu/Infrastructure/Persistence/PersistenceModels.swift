import Foundation

struct PersistenceLibrary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var readingProgress: [ReadingProgress]
    var savedExplanations: [SavedExplanationRecord]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        readingProgress: [ReadingProgress] = [],
        savedExplanations: [SavedExplanationRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.readingProgress = readingProgress
        self.savedExplanations = savedExplanations
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
