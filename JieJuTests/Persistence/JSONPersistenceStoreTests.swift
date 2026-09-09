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
        XCTAssertTrue(reloaded.vocabularyEntries.isEmpty)
    }

    func testMigratesV1LibraryToCurrentVersionAndPreservesExistingData() async throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let v1 = """
        {"schemaVersion":1,"readingProgress":[],"savedExplanations":[]}
        """
        try Data(v1.utf8).write(to: fileURL)

        let migrated = try await JSONPersistenceStore(fileURL: fileURL).load()

        XCTAssertEqual(migrated.schemaVersion, 5)
        XCTAssertTrue(migrated.vocabularyEntries.isEmpty)
        let disk = try JSONDecoder.iso8601.decode(PersistenceLibrary.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(disk.schemaVersion, 5)
    }

    func testMigratesV2VocabularyAndCreatesDueRecognitionCard() async throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entry = makeVocabularyEntry(surface: "continue", meaning: "继续", sentence: "They continue.")
        let oldLibrary = PersistenceLibrary(schemaVersion: 2, vocabularyEntries: [entry])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.iso8601.encode(oldLibrary)) as? [String: Any])
        object.removeValue(forKey: "reviewCards")
        object.removeValue(forKey: "reviewLogs")
        try JSONSerialization.data(withJSONObject: object).write(to: fileURL)
        let fixedTimestamp = timestamp
        let store = JSONPersistenceStore(fileURL: fileURL, now: { fixedTimestamp })

        let migrated = try await store.load()

        XCTAssertEqual(migrated.schemaVersion, 5)
        XCTAssertEqual(migrated.vocabularyEntries, [entry])
        XCTAssertEqual(migrated.reviewCards.count, 1)
        XCTAssertEqual(migrated.reviewCards.first?.vocabularyEntryID, entry.id)
        XCTAssertEqual(migrated.reviewCards.first?.dueAt, timestamp)
        XCTAssertTrue(migrated.reviewLogs.isEmpty)
    }

    func testVocabularyDeduplicatesAndMergesMeaningsAndSources() async throws {
        let fixedTimestamp = timestamp
        let store = JSONPersistenceStore(fileURL: fileURL, now: { fixedTimestamp })
        let first = makeVocabularyEntry(
            surface: "continued",
            meaning: "继续",
            sentence: "She continued."
        )
        let saved = try await store.saveVocabularyEntry(first)
        var second = makeVocabularyEntry(
            surface: "continue",
            meaning: "持续做某事",
            sentence: "They continue reading."
        )
        second.language = " english "
        second.lemma = "CONTINUE"
        second.reading = "kənˈtɪnjuː"
        second.updatedAt = timestamp.addingTimeInterval(60)

        let merged = try await store.saveVocabularyEntry(second)

        XCTAssertEqual(merged.id, saved.id)
        XCTAssertEqual(Set(merged.surfaceForms), Set(["continued", "continue"]))
        XCTAssertEqual(merged.reading, "kənˈtɪnjuː")
        XCTAssertEqual(merged.senses.count, 2)
        XCTAssertEqual(merged.sources.count, 2)
        let entriesAfterMerge = try await store.vocabularyEntries()
        XCTAssertEqual(entriesAfterMerge.count, 1)

        let cards = try await store.reviewCards()
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.vocabularyEntryID, merged.id)
        let reviewed = try await store.reviewCard(id: try XCTUnwrap(cards.first?.id), rating: .good, at: timestamp)
        XCTAssertEqual(reviewed.intervalDays, 2)
        let logsAfterReview = try await store.reviewLogs()
        XCTAssertEqual(logsAfterReview.count, 1)

        let didDelete = try await store.deleteVocabularyEntry(id: merged.id)
        XCTAssertTrue(didDelete)
        let entriesAfterDelete = try await store.vocabularyEntries()
        XCTAssertTrue(entriesAfterDelete.isEmpty)
        let cardsAfterDelete = try await store.reviewCards()
        let logsAfterDelete = try await store.reviewLogs()
        XCTAssertTrue(cardsAfterDelete.isEmpty)
        XCTAssertTrue(logsAfterDelete.isEmpty)
    }

    func testMigratesV3LibraryWithoutInventingSourceLocators() async throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let record = makeRecord(locator: nil)
        let entry = makeVocabularyEntry(surface: "continue", meaning: "继续", sentence: "They continue.", locator: nil)
        let oldLibrary = PersistenceLibrary(schemaVersion: 3, savedExplanations: [record], vocabularyEntries: [entry])
        try JSONEncoder.iso8601.encode(oldLibrary).write(to: fileURL)

        let migrated = try await JSONPersistenceStore(fileURL: fileURL).load()

        XCTAssertEqual(migrated.schemaVersion, 5)
        XCTAssertNil(migrated.savedExplanations.first?.locator)
        XCTAssertNil(migrated.vocabularyEntries.first?.sources.first?.locator)
    }

    func testSourceLocatorRoundTripsForExplanationAndVocabulary() async throws {
        let anchor = EPUBTextAnchor(textOffset: 42, textQuote: "selected sentence", progression: 0.4)
        let locator = DocumentLocator.epub(
            chapterHref: "OEBPS/chapter-2.xhtml",
            textAnchor: anchor,
            displayPageIndex: 3
        )
        let record = makeRecord(locator: locator)
        let entry = makeVocabularyEntry(surface: "continue", meaning: "继续", sentence: "They continue.", locator: locator)
        let store = JSONPersistenceStore(fileURL: fileURL)

        _ = try await store.saveExplanation(record)
        _ = try await store.saveVocabularyEntry(entry)
        let reloaded = try await JSONPersistenceStore(fileURL: fileURL).load()

        XCTAssertEqual(reloaded.savedExplanations.first?.locator, locator)
        XCTAssertEqual(reloaded.vocabularyEntries.first?.sources.first?.locator, locator)
        XCTAssertEqual(reloaded.savedExplanations.first?.locator?.epubTextAnchor, anchor)
    }

    func testDocumentLocatorCodingMatchesReaderBridgeContract() throws {
        let pdfData = try JSONEncoder().encode(DocumentLocator.pdf(pageIndex: 7))
        let pdf = try XCTUnwrap(JSONSerialization.jsonObject(with: pdfData) as? [String: Any])
        XCTAssertEqual(pdf["kind"] as? String, "pdf")
        XCTAssertEqual(pdf["pageIndex"] as? Int, 7)
        XCTAssertNil(pdf["chapterHref"])

        let epubData = try JSONEncoder().encode(DocumentLocator.epub(
            chapterHref: "Text/chapter.xhtml",
            textAnchor: .init(textOffset: 9, textQuote: "a quote", progression: 0.25),
            displayPageIndex: 2
        ))
        let epub = try XCTUnwrap(JSONSerialization.jsonObject(with: epubData) as? [String: Any])
        XCTAssertEqual(epub["kind"] as? String, "epub")
        XCTAssertEqual(epub["chapterHref"] as? String, "Text/chapter.xhtml")
        XCTAssertNotNil(epub["textAnchor"] as? String)
        XCTAssertNil(epub["pageIndex"])
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
        duplicate.locator = nil
        duplicate.updatedAt = timestamp.addingTimeInterval(60)
        let deduplicated = try await store.saveExplanation(duplicate)

        XCTAssertEqual(deduplicated.id, saved.id)
        XCTAssertEqual(deduplicated.createdAt, saved.createdAt)
        XCTAssertEqual(deduplicated.locator, saved.locator)
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

    private func makeRecord(id: UUID = UUID(), locator: DocumentLocator? = .pdf(pageIndex: 3)) -> SavedExplanationRecord {
        SavedExplanationRecord(
            id: id,
            document: document,
            pageIndex: 3,
            locator: locator,
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

    private func makeVocabularyEntry(
        surface: String,
        meaning: String,
        sentence: String,
        locator: DocumentLocator? = .pdf(pageIndex: 3)
    ) -> VocabularyEntry {
        VocabularyEntry(
            language: "English",
            lemma: "continue",
            surfaceForms: [surface],
            senses: [.init(meaning: meaning, explanationLanguage: "Chinese")],
            sources: [.init(
                document: document,
                pageIndex: 3,
                locator: locator,
                sentence: sentence,
                surface: surface,
                createdAt: timestamp
            )],
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

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
