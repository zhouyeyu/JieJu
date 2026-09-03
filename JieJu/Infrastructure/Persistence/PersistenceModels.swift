import Foundation

struct PersistenceLibrary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var readingProgress: [ReadingProgress]
    var savedExplanations: [SavedExplanationRecord]
    var vocabularyEntries: [VocabularyEntry]
    var reviewCards: [ReviewCard]
    var reviewLogs: [ReviewLog]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        readingProgress: [ReadingProgress] = [],
        savedExplanations: [SavedExplanationRecord] = [],
        vocabularyEntries: [VocabularyEntry] = [],
        reviewCards: [ReviewCard] = [],
        reviewLogs: [ReviewLog] = []
    ) {
        self.schemaVersion = schemaVersion
        self.readingProgress = readingProgress
        self.savedExplanations = savedExplanations
        self.vocabularyEntries = vocabularyEntries
        self.reviewCards = reviewCards
        self.reviewLogs = reviewLogs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, readingProgress, savedExplanations, vocabularyEntries, reviewCards, reviewLogs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        readingProgress = try container.decode([ReadingProgress].self, forKey: .readingProgress)
        savedExplanations = try container.decode([SavedExplanationRecord].self, forKey: .savedExplanations)
        vocabularyEntries = try container.decodeIfPresent([VocabularyEntry].self, forKey: .vocabularyEntries) ?? []
        reviewCards = try container.decodeIfPresent([ReviewCard].self, forKey: .reviewCards) ?? []
        reviewLogs = try container.decodeIfPresent([ReviewLog].self, forKey: .reviewLogs) ?? []
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

enum ReviewCardTemplate: String, Codable, CaseIterable, Sendable {
    case recognition
    case cloze
}

enum ReviewCardState: String, Codable, Sendable {
    case new
    case learning
    case review
    case suspended
}

enum ReviewRating: String, Codable, CaseIterable, Hashable, Sendable {
    case again
    case hard
    case good
    case easy

    var title: String {
        switch self {
        case .again: "没想起"
        case .hard: "有点模糊"
        case .good: "想起来了"
        case .easy: "很熟悉"
        }
    }
}

struct ReviewCard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let vocabularyEntryID: UUID
    var template: ReviewCardTemplate
    var state: ReviewCardState
    var dueAt: Date
    var intervalDays: Double
    var easeFactor: Double
    var repetitions: Int
    var lapses: Int
    var lastReviewedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        vocabularyEntryID: UUID,
        template: ReviewCardTemplate = .recognition,
        state: ReviewCardState = .new,
        dueAt: Date = Date(),
        intervalDays: Double = 0,
        easeFactor: Double = 2.5,
        repetitions: Int = 0,
        lapses: Int = 0,
        lastReviewedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.vocabularyEntryID = vocabularyEntryID
        self.template = template
        self.state = state
        self.dueAt = dueAt
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.lapses = lapses
        self.lastReviewedAt = lastReviewedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ReviewLog: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let cardID: UUID
    let vocabularyEntryID: UUID
    let rating: ReviewRating
    let reviewedAt: Date
    let previousState: ReviewCardState
    let previousIntervalDays: Double
    let scheduledIntervalDays: Double
    let scheduledDueAt: Date
    let schedulerVersion: String

    init(
        id: UUID = UUID(),
        cardID: UUID,
        vocabularyEntryID: UUID,
        rating: ReviewRating,
        reviewedAt: Date,
        previousState: ReviewCardState,
        previousIntervalDays: Double,
        scheduledIntervalDays: Double,
        scheduledDueAt: Date,
        schedulerVersion: String
    ) {
        self.id = id
        self.cardID = cardID
        self.vocabularyEntryID = vocabularyEntryID
        self.rating = rating
        self.reviewedAt = reviewedAt
        self.previousState = previousState
        self.previousIntervalDays = previousIntervalDays
        self.scheduledIntervalDays = scheduledIntervalDays
        self.scheduledDueAt = scheduledDueAt
        self.schedulerVersion = schedulerVersion
    }
}

protocol ReviewScheduling: Sendable {
    var version: String { get }
    func review(_ card: ReviewCard, rating: ReviewRating, at date: Date) -> (card: ReviewCard, log: ReviewLog)
    func preview(_ card: ReviewCard, rating: ReviewRating, at date: Date) -> Date
}

struct JieJuReviewScheduler: ReviewScheduling {
    let version = "jieju-interval-v1"

    func review(_ card: ReviewCard, rating: ReviewRating, at date: Date) -> (card: ReviewCard, log: ReviewLog) {
        let previousState = card.state
        let previousInterval = card.intervalDays
        var updated = card
        let schedule = scheduledValues(for: card, rating: rating, at: date)
        updated.state = schedule.state
        updated.dueAt = schedule.dueAt
        updated.intervalDays = schedule.intervalDays
        updated.easeFactor = schedule.easeFactor
        updated.repetitions = schedule.repetitions
        updated.lapses = schedule.lapses
        updated.lastReviewedAt = date
        updated.updatedAt = date
        return (updated, ReviewLog(
            cardID: card.id,
            vocabularyEntryID: card.vocabularyEntryID,
            rating: rating,
            reviewedAt: date,
            previousState: previousState,
            previousIntervalDays: previousInterval,
            scheduledIntervalDays: schedule.intervalDays,
            scheduledDueAt: schedule.dueAt,
            schedulerVersion: version
        ))
    }

    func preview(_ card: ReviewCard, rating: ReviewRating, at date: Date) -> Date {
        scheduledValues(for: card, rating: rating, at: date).dueAt
    }

    private func scheduledValues(
        for card: ReviewCard,
        rating: ReviewRating,
        at date: Date
    ) -> (state: ReviewCardState, dueAt: Date, intervalDays: Double, easeFactor: Double, repetitions: Int, lapses: Int) {
        let wasEstablished = card.state == .review && card.repetitions > 0
        switch rating {
        case .again:
            return (.learning, date.addingTimeInterval(10 * 60), 0,
                    max(1.3, card.easeFactor - 0.2), 0, card.lapses + (wasEstablished ? 1 : 0))
        case .hard:
            let interval = wasEstablished ? roundedDays(max(1, card.intervalDays * 1.2)) : 1
            return (.review, date.addingTimeInterval(interval * 86_400), interval,
                    max(1.3, card.easeFactor - 0.15), card.repetitions + 1, card.lapses)
        case .good:
            let interval = wasEstablished ? roundedDays(max(2, card.intervalDays * card.easeFactor)) : 2
            return (.review, date.addingTimeInterval(interval * 86_400), interval,
                    card.easeFactor, card.repetitions + 1, card.lapses)
        case .easy:
            let interval = wasEstablished ? roundedDays(max(4, card.intervalDays * card.easeFactor * 1.3)) : 4
            return (.review, date.addingTimeInterval(interval * 86_400), interval,
                    min(3, card.easeFactor + 0.15), card.repetitions + 1, card.lapses)
        }
    }

    private func roundedDays(_ value: Double) -> Double {
        value.rounded(.toNearestOrAwayFromZero)
    }
}
