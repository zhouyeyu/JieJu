import Foundation

@MainActor
final class LearningLibraryModel: ObservableObject {
    @Published private(set) var records: [SavedExplanationRecord] = []
    @Published private(set) var vocabularyEntries: [VocabularyEntry] = []
    @Published private(set) var dueReviewItems: [ReviewQueueItem] = []
    @Published private(set) var reviewLogs: [ReviewLog] = []
    @Published private(set) var errorMessage: String?

    private let store: JSONPersistenceStore

    init(store: JSONPersistenceStore = JSONPersistenceStore()) {
        self.store = store
    }

    func reload() async {
        do {
            records = try await store.savedExplanations().sorted { $0.updatedAt > $1.updatedAt }
            vocabularyEntries = try await store.vocabularyEntries().sorted { $0.updatedAt > $1.updatedAt }
            let dueCards = try await store.dueReviewCards(limit: 50)
            let entriesByID = Dictionary(uniqueKeysWithValues: vocabularyEntries.map { ($0.id, $0) })
            dueReviewItems = dueCards.compactMap { card in
                entriesByID[card.vocabularyEntryID].map { ReviewQueueItem(card: card, entry: $0) }
            }
            reviewLogs = try await store.reviewLogs()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ payload: ReaderSavePayload, modelName: String?) async throws {
        let record = SavedExplanationRecord(
            document: DocumentIdentity(id: payload.documentURL.standardizedFileURL.path, fileName: payload.documentURL.lastPathComponent),
            pageIndex: payload.pageIndex,
            request: PersistedExplanationRequest(
                targetText: payload.selection.targetText,
                precedingContext: payload.selection.precedingContext,
                followingContext: payload.selection.followingContext,
                sourceLanguage: payload.sourceLanguage,
                explanationLanguage: payload.explanationLanguage
            ),
            explanation: PersistedExplanation(
                translation: payload.explanation.translation,
                sentenceCore: payload.explanation.sentenceCore,
                grammarPoints: payload.explanation.grammarPoints.map { .init(title: $0, explanation: $0) },
                keyPhrases: payload.explanation.keyPhrases.map { .init(text: $0.text, meaning: $0.meaning, example: nil) },
                modelName: modelName
            )
        )
        do {
            _ = try await store.saveExplanation(record)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func saveVocabulary(_ payload: ReaderVocabularySavePayload) async throws {
        let timestamp = Date()
        let entry = VocabularyEntry(
            language: payload.sourceLanguage,
            lemma: payload.candidate.lemma,
            reading: payload.candidate.reading,
            partOfSpeech: payload.candidate.partOfSpeech,
            surfaceForms: [payload.candidate.surface],
            senses: [.init(meaning: payload.candidate.meaning, explanationLanguage: payload.explanationLanguage)],
            sources: [.init(
                document: DocumentIdentity(
                    id: payload.documentURL.standardizedFileURL.path,
                    fileName: payload.documentURL.lastPathComponent
                ),
                pageIndex: payload.pageIndex,
                sentence: payload.sentence,
                surface: payload.candidate.surface,
                createdAt: timestamp
            )],
            createdAt: timestamp,
            updatedAt: timestamp
        )
        do {
            _ = try await store.saveVocabularyEntry(entry)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func delete(_ record: SavedExplanationRecord) async {
        do {
            _ = try await store.deleteExplanation(id: record.id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteVocabulary(_ entry: VocabularyEntry) async {
        do {
            _ = try await store.deleteVocabularyEntry(id: entry.id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func review(_ item: ReviewQueueItem, rating: ReviewRating) async {
        do {
            _ = try await store.reviewCard(id: item.card.id, rating: rating)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var reviewedTodayCount: Int {
        let calendar = Calendar.current
        return reviewLogs.filter { calendar.isDateInToday($0.reviewedAt) }.count
    }
}

struct ReviewQueueItem: Identifiable, Equatable {
    let card: ReviewCard
    let entry: VocabularyEntry
    var id: UUID { card.id }
}
