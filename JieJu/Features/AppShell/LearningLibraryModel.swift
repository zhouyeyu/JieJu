import Foundation

@MainActor
final class LearningLibraryModel: ObservableObject {
    @Published private(set) var records: [SavedExplanationRecord] = []
    @Published private(set) var errorMessage: String?

    private let store: JSONPersistenceStore

    init(store: JSONPersistenceStore = JSONPersistenceStore()) {
        self.store = store
    }

    func reload() async {
        do {
            records = try await store.savedExplanations().sorted { $0.updatedAt > $1.updatedAt }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ payload: ReaderSavePayload, modelName: String?) async {
        let record = SavedExplanationRecord(
            document: DocumentIdentity(id: payload.documentURL.standardizedFileURL.path, fileName: payload.documentURL.lastPathComponent),
            pageIndex: payload.pageIndex,
            request: PersistedExplanationRequest(
                targetText: payload.selection.targetText,
                precedingContext: payload.selection.precedingContext,
                followingContext: payload.selection.followingContext,
                sourceLanguage: "English",
                explanationLanguage: "Chinese"
            ),
            explanation: PersistedExplanation(
                translation: payload.explanation.translation,
                sentenceCore: payload.explanation.sentenceCore,
                grammarPoints: payload.explanation.grammarPoints.map { .init(title: $0, explanation: $0) },
                keyPhrases: payload.explanation.keyPhrases.map { .init(text: $0, meaning: $0, example: nil) },
                modelName: modelName
            )
        )
        do {
            _ = try await store.saveExplanation(record)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
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
}

