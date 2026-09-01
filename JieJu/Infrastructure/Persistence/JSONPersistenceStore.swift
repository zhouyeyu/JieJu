import Foundation

enum PersistenceStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidPageIndex(Int)
    case recordNotFound(UUID)
}

actor JSONPersistenceStore {
    static let defaultFileName = "library.json"

    let fileURL: URL

    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private var cachedLibrary: PersistenceLibrary?

    init(
        fileURL: URL = JSONPersistenceStore.defaultFileURL(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
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
            let library = try Self.makeDecoder().decode(PersistenceLibrary.self, from: data)
            guard library.schemaVersion == PersistenceLibrary.currentSchemaVersion else {
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
