import XCTest
@testable import JieJu

final class JSONPersistenceStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JieJuPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = temporaryDirectory.appendingPathComponent("nested/library.json")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testFirstLoadCreatesVersionedEmptyLibrary() async throws {
        let store = JSONPersistenceStore(fileURL: fileURL)

        let library = try await store.load()

        XCTAssertEqual(library, PersistenceLibrary())
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let persisted = try JSONDecoder.iso8601.decode(PersistenceLibrary.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(persisted.schemaVersion, PersistenceLibrary.currentSchemaVersion)
    }

    func testRoundTripAcrossStoreInstances() async throws {
        let store = JSONPersistenceStore(fileURL: fileURL)
        let progress = ReadingProgress(document: document, pageIndex: 8, updatedAt: timestamp)
        let record = makeRecord()
        try await store.saveReadingProgress(progress)
        let saved = try await store.saveExplanation(record)

        let reloadedStore = JSONPersistenceStore(fileURL: fileURL)
        let reloaded = try await reloadedStore.load()

        XCTAssertEqual(reloaded.readingProgress, [progress])
        XCTAssertEqual(reloaded.savedExplanations, [saved])
    }

    func testCorruptFileIsBackedUpAndRecovered() async throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: fileURL)
        let fixedTimestamp = timestamp
        let store = JSONPersistenceStore(fileURL: fileURL, now: { fixedTimestamp })

        let recovered = try await store.load()

        XCTAssertEqual(recovered, PersistenceLibrary())
        let files = try FileManager.default.contentsOfDirectory(
            at: fileURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        let backup = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("library.corrupt-20240102T030405.000Z") })
        XCTAssertEqual(try Data(contentsOf: backup), corruptData)
        XCTAssertNoThrow(try JSONDecoder.iso8601.decode(PersistenceLibrary.self, from: Data(contentsOf: fileURL)))
    }

    func testReadingProgressCRUD() async throws {
        let store = JSONPersistenceStore(fileURL: fileURL)
        let first = ReadingProgress(document: document, pageIndex: 2, updatedAt: timestamp)
        try await store.saveReadingProgress(first)
        let savedFirst = try await store.readingProgress(for: document.id)
        XCTAssertEqual(savedFirst, first)

        let updated = ReadingProgress(document: document, pageIndex: 12, updatedAt: timestamp.addingTimeInterval(60))
        try await store.saveReadingProgress(updated)
        let savedUpdate = try await store.readingProgress(for: document.id)
        XCTAssertEqual(savedUpdate, updated)
        let didDelete = try await store.deleteReadingProgress(for: document.id)
        XCTAssertTrue(didDelete)
        let deletedProgress = try await store.readingProgress(for: document.id)
        XCTAssertNil(deletedProgress)
        let didDeleteAgain = try await store.deleteReadingProgress(for: document.id)
        XCTAssertFalse(didDeleteAgain)
    }

    func testExplanationCRUDAndDeduplication() async throws {
        let store = JSONPersistenceStore(fileURL: fileURL)
        let original = makeRecord()
        let saved = try await store.saveExplanation(original)

        var duplicate = makeRecord(id: UUID())
        duplicate.request.targetText = "  THE   cat sleeps. "
        duplicate.explanation.translation = "猫正在睡觉。"
        duplicate.updatedAt = timestamp.addingTimeInterval(60)
        let deduplicated = try await store.saveExplanation(duplicate)

        XCTAssertEqual(deduplicated.id, saved.id)
        XCTAssertEqual(deduplicated.createdAt, saved.createdAt)
        let afterDeduplication = try await store.savedExplanations()
        XCTAssertEqual(afterDeduplication.count, 1)
        let deduplicatedRecord = try await store.savedExplanation(id: saved.id)
        XCTAssertEqual(deduplicatedRecord?.explanation.translation, "猫正在睡觉。")

        var explicitlyUpdated = deduplicated
        explicitlyUpdated.explanation.sentenceCore = "cat sleeps"
        let updated = try await store.updateExplanation(explicitlyUpdated)
        let storedUpdate = try await store.savedExplanation(id: saved.id)
        XCTAssertEqual(storedUpdate, updated)

        let didDelete = try await store.deleteExplanation(id: saved.id)
        XCTAssertTrue(didDelete)
        let remainingRecords = try await store.savedExplanations()
        XCTAssertTrue(remainingRecords.isEmpty)
        let didDeleteAgain = try await store.deleteExplanation(id: saved.id)
        XCTAssertFalse(didDeleteAgain)
    }

    func testNegativePageIndexIsRejected() async throws {
        let store = JSONPersistenceStore(fileURL: fileURL)
        let invalid = ReadingProgress(document: document, pageIndex: -1, updatedAt: timestamp)

        do {
            try await store.saveReadingProgress(invalid)
            XCTFail("Expected invalid page index error")
        } catch {
            XCTAssertEqual(error as? PersistenceStoreError, .invalidPageIndex(-1))
        }
    }

    private let timestamp = Date(timeIntervalSince1970: 1_704_164_645)
    private let document = DocumentIdentity(id: "document-1", fileName: "Sample.pdf", fingerprint: "abc123")

    private func makeRecord(id: UUID = UUID()) -> SavedExplanationRecord {
        SavedExplanationRecord(
            id: id,
            document: document,
            pageIndex: 3,
            request: PersistedExplanationRequest(
                targetText: "The cat sleeps.",
                precedingContext: "It is quiet.",
                followingContext: "Nobody moves.",
                sourceLanguage: "en",
                explanationLanguage: "zh-Hans"
            ),
            explanation: PersistedExplanation(
                translation: "猫睡着了。",
                sentenceCore: "The cat / sleeps",
                grammarPoints: [.init(title: "Simple present", explanation: "Describes a current state.")],
                keyPhrases: [.init(text: "fall asleep", meaning: "入睡", example: nil)],
                modelName: "qwen2.5:0.5b-instruct"
            ),
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
