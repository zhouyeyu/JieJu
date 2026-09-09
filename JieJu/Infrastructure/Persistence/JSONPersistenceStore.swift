import Foundation

enum PersistenceStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidPageIndex(Int)
    case recordNotFound(UUID)
    case vocabularyEntryNotFound(UUID)
}

actor JSONPersistenceStore {
    static let defaultFileName = "library.json"

    let fileURL: URL

    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let reviewScheduler: any ReviewScheduling
    private var cachedLibrary: PersistenceLibrary?

    init(
        fileURL: URL = JSONPersistenceStore.defaultFileURL(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        reviewScheduler: any ReviewScheduling = JieJuReviewScheduler()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
        self.reviewScheduler = reviewScheduler
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("JieJu", isDirectory: true)
            .appendingPathComponent(defaultFileName, isDirectory: false)
    }

    func load() throws -> PersistenceLibrary {
        if let cachedLibrary {
            return cachedLibrary
        }

        try ensureParentDirectoryExists()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let library = PersistenceLibrary()
            try write(library)
            cachedLibrary = library
            return library
        }

        do {
            let data = try Data(contentsOf: fileURL)
            var library = try Self.makeDecoder().decode(PersistenceLibrary.self, from: data)
            switch library.schemaVersion {
            case 1, 2, 3:
                library.schemaVersion = PersistenceLibrary.currentSchemaVersion
                addMissingRecognitionCards(to: &library, dueAt: now())
                try write(library)
            case PersistenceLibrary.currentSchemaVersion:
                break
            default:
                throw PersistenceStoreError.unsupportedSchemaVersion(library.schemaVersion)
            }
            cachedLibrary = library
            return library
        } catch let error as PersistenceStoreError {
            throw error
        } catch {
            try backupCorruptedFile()
            let recovered = PersistenceLibrary()
            try write(recovered)
            cachedLibrary = recovered
            return recovered
        }
    }

    func readingProgress(for documentID: String) throws -> ReadingProgress? {
        try load().readingProgress.first { $0.document.id == documentID }
    }

    @discardableResult
    func saveReadingProgress(_ progress: ReadingProgress) throws -> ReadingProgress {
        guard progress.pageIndex >= 0 else {
            throw PersistenceStoreError.invalidPageIndex(progress.pageIndex)
        }
        var library = try load()
        if let index = library.readingProgress.firstIndex(where: { $0.document.id == progress.document.id }) {
            library.readingProgress[index] = progress
        } else {
            library.readingProgress.append(progress)
        }
        try persist(library)
        return progress
    }

    @discardableResult
    func deleteReadingProgress(for documentID: String) throws -> Bool {
        var library = try load()
        let previousCount = library.readingProgress.count
        library.readingProgress.removeAll { $0.document.id == documentID }
        guard previousCount != library.readingProgress.count else { return false }
        try persist(library)
        return true
    }

    func savedExplanations() throws -> [SavedExplanationRecord] {
        try load().savedExplanations
    }

    func savedExplanation(id: UUID) throws -> SavedExplanationRecord? {
        try load().savedExplanations.first { $0.id == id }
    }

    @discardableResult
    func saveExplanation(_ record: SavedExplanationRecord) throws -> SavedExplanationRecord {
        var library = try load()
        if let index = library.savedExplanations.firstIndex(where: { Self.isDuplicate($0, record) }) {
            var updated = record
            updated = SavedExplanationRecord(
                id: library.savedExplanations[index].id,
                document: record.document,
                pageIndex: record.pageIndex,
                locator: record.locator ?? library.savedExplanations[index].locator,
                request: record.request,
                explanation: record.explanation,
                createdAt: library.savedExplanations[index].createdAt,
                updatedAt: record.updatedAt
            )
            library.savedExplanations[index] = updated
            try persist(library)
            return updated
        }
        library.savedExplanations.append(record)
        try persist(library)
        return record
    }

    @discardableResult
    func updateExplanation(_ record: SavedExplanationRecord) throws -> SavedExplanationRecord {
        var library = try load()
        guard let index = library.savedExplanations.firstIndex(where: { $0.id == record.id }) else {
            throw PersistenceStoreError.recordNotFound(record.id)
        }
        library.savedExplanations[index] = record
        try persist(library)
        return record
    }

    @discardableResult
    func deleteExplanation(id: UUID) throws -> Bool {
        var library = try load()
        let previousCount = library.savedExplanations.count
        library.savedExplanations.removeAll { $0.id == id }
        guard previousCount != library.savedExplanations.count else { return false }
        try persist(library)
        return true
    }

    func vocabularyEntries() throws -> [VocabularyEntry] {
        try load().vocabularyEntries
    }

    @discardableResult
    func saveVocabularyEntry(_ entry: VocabularyEntry) throws -> VocabularyEntry {
        var library = try load()
        if let index = library.vocabularyEntries.firstIndex(where: { Self.isDuplicate($0, entry) }) {
            let merged = Self.merging(library.vocabularyEntries[index], with: entry)
            library.vocabularyEntries[index] = merged
            addMissingRecognitionCard(for: merged, to: &library, dueAt: now())
            try persist(library)
            return merged
        }
        library.vocabularyEntries.append(entry)
        addMissingRecognitionCard(for: entry, to: &library, dueAt: now())
        try persist(library)
        return entry
    }

    @discardableResult
    func updateVocabularyEntry(_ entry: VocabularyEntry) throws -> VocabularyEntry {
        var library = try load()
        guard let index = library.vocabularyEntries.firstIndex(where: { $0.id == entry.id }) else {
            throw PersistenceStoreError.vocabularyEntryNotFound(entry.id)
        }
        library.vocabularyEntries[index] = entry
        try persist(library)
        return entry
    }

    @discardableResult
    func deleteVocabularyEntry(id: UUID) throws -> Bool {
        var library = try load()
        let previousCount = library.vocabularyEntries.count
        library.vocabularyEntries.removeAll { $0.id == id }
        guard previousCount != library.vocabularyEntries.count else { return false }
        let removedCardIDs = Set(library.reviewCards.filter { $0.vocabularyEntryID == id }.map(\.id))
        library.reviewCards.removeAll { $0.vocabularyEntryID == id }
        library.reviewLogs.removeAll { $0.vocabularyEntryID == id || removedCardIDs.contains($0.cardID) }
        try persist(library)
        return true
    }

    func reviewCards() throws -> [ReviewCard] {
        try load().reviewCards
    }

    func reviewLogs() throws -> [ReviewLog] {
        try load().reviewLogs
    }

    func dueReviewCards(at date: Date? = nil, limit: Int = 100) throws -> [ReviewCard] {
        let reference = date ?? now()
        return try load().reviewCards
            .filter { $0.state != .suspended && $0.dueAt <= reference }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt { return lhs.createdAt < rhs.createdAt }
                return lhs.dueAt < rhs.dueAt
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    @discardableResult
    func reviewCard(id: UUID, rating: ReviewRating, at date: Date? = nil) throws -> ReviewCard {
        var library = try load()
        guard let index = library.reviewCards.firstIndex(where: { $0.id == id }) else {
            throw PersistenceStoreError.recordNotFound(id)
        }
        let outcome = reviewScheduler.review(library.reviewCards[index], rating: rating, at: date ?? now())
        library.reviewCards[index] = outcome.card
        library.reviewLogs.append(outcome.log)
        try persist(library)
        return outcome.card
    }

    func reviewPreviews(for cardID: UUID, at date: Date? = nil) throws -> [ReviewRating: Date] {
        let library = try load()
        guard let card = library.reviewCards.first(where: { $0.id == cardID }) else {
            throw PersistenceStoreError.recordNotFound(cardID)
        }
        let reference = date ?? now()
        return Dictionary(uniqueKeysWithValues: ReviewRating.allCases.map {
            ($0, reviewScheduler.preview(card, rating: $0, at: reference))
        })
    }

    private func persist(_ library: PersistenceLibrary) throws {
        try write(library)
        cachedLibrary = library
    }

    private func write(_ library: PersistenceLibrary) throws {
        try ensureParentDirectoryExists()
        let data = try Self.makeEncoder().encode(library)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureParentDirectoryExists() throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func backupCorruptedFile() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let timestamp = Self.backupTimestampFormatter.string(from: now())
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName).corrupt-\(timestamp).json")
        try fileManager.moveItem(at: fileURL, to: uniqueBackupURL(startingAt: backupURL))
    }

    private func uniqueBackupURL(startingAt proposedURL: URL) -> URL {
        guard fileManager.fileExists(atPath: proposedURL.path) else { return proposedURL }
        let stem = proposedURL.deletingPathExtension().lastPathComponent
        let directory = proposedURL.deletingLastPathComponent()
        for suffix in 1...Int.max {
            let candidate = directory.appendingPathComponent("\(stem)-\(suffix).json")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(stem)-\(UUID().uuidString).json")
    }

    private static func isDuplicate(_ lhs: SavedExplanationRecord, _ rhs: SavedExplanationRecord) -> Bool {
        lhs.document.id == rhs.document.id
            && lhs.pageIndex == rhs.pageIndex
            && normalized(lhs.request.targetText) == normalized(rhs.request.targetText)
            && normalized(lhs.request.precedingContext) == normalized(rhs.request.precedingContext)
            && normalized(lhs.request.followingContext) == normalized(rhs.request.followingContext)
    }

    private static func isDuplicate(_ lhs: VocabularyEntry, _ rhs: VocabularyEntry) -> Bool {
        let lhsReading = normalized(lhs.reading)
        let rhsReading = normalized(rhs.reading)
        return normalized(lhs.language) == normalized(rhs.language)
            && normalized(lhs.lemma) == normalized(rhs.lemma)
            && (lhsReading.isEmpty || rhsReading.isEmpty || lhsReading == rhsReading)
    }

    private static func merging(_ existing: VocabularyEntry, with incoming: VocabularyEntry) -> VocabularyEntry {
        var merged = existing
        if merged.reading?.isEmpty != false { merged.reading = incoming.reading }
        if merged.partOfSpeech?.isEmpty != false { merged.partOfSpeech = incoming.partOfSpeech }
        for surface in incoming.surfaceForms where !merged.surfaceForms.contains(where: { normalized($0) == normalized(surface) }) {
            merged.surfaceForms.append(surface)
        }
        for sense in incoming.senses where !merged.senses.contains(where: {
            normalized($0.meaning) == normalized(sense.meaning)
                && normalized($0.explanationLanguage) == normalized(sense.explanationLanguage)
        }) {
            merged.senses.append(sense)
        }
        for source in incoming.sources {
            let matchingIndices = merged.sources.indices.filter { index in
                let existing = merged.sources[index]
                return existing.document.id == source.document.id
                    && existing.pageIndex == source.pageIndex
                    && normalized(existing.sentence) == normalized(source.sentence)
                    && normalized(existing.surface) == normalized(source.surface)
            }
            if matchingIndices.contains(where: { merged.sources[$0].locator == source.locator }) {
                continue
            } else if source.locator == nil, !matchingIndices.isEmpty {
                continue
            } else if let legacy = matchingIndices.first(where: { merged.sources[$0].locator == nil }) {
                merged.sources[legacy].locator = source.locator
            } else {
                merged.sources.append(source)
            }
        }
        merged.updatedAt = max(existing.updatedAt, incoming.updatedAt)
        return merged
    }

    private func addMissingRecognitionCards(to library: inout PersistenceLibrary, dueAt: Date) {
        for entry in library.vocabularyEntries {
            addMissingRecognitionCard(for: entry, to: &library, dueAt: dueAt)
        }
    }

    private func addMissingRecognitionCard(for entry: VocabularyEntry, to library: inout PersistenceLibrary, dueAt: Date) {
        guard !library.reviewCards.contains(where: {
            $0.vocabularyEntryID == entry.id && $0.template == .recognition
        }) else { return }
        library.reviewCards.append(.init(
            vocabularyEntryID: entry.id,
            dueAt: dueAt,
            createdAt: dueAt,
            updatedAt: dueAt
        ))
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter
    }()
}
