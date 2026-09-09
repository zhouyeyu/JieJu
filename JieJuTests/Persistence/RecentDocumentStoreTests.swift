import XCTest
@testable import JieJu

private final class StubDocumentBookmarking: DocumentBookmarking {
    var stalePaths: Set<String> = []
    var invalidBookmarks: Set<Data> = []

    func bookmark(for url: URL) throws -> Data {
        Data(url.standardizedFileURL.path.utf8)
    }

    func resolve(_ data: Data) throws -> ResolvedDocumentBookmark {
        if invalidBookmarks.contains(data) { throw CocoaError(.fileReadCorruptFile) }
        guard let path = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return .init(url: URL(fileURLWithPath: path), isStale: stalePaths.contains(path))
    }
}

final class RecentDocumentStoreTests: XCTestCase {
    @MainActor
    func testPersistsDeduplicatesAndUpdatesReadingLocation() throws {
        let suite = "JieJuTests.RecentDocuments.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bookmarker = StubDocumentBookmarking()
        var time = Date(timeIntervalSince1970: 1_000)
        let store = RecentDocumentStore(defaults: defaults, bookmarking: bookmarker, now: { time })
        let firstURL = URL(fileURLWithPath: "/tmp/first.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/second.epub")

        let first = try store.recordOpened(firstURL, kind: .pdf, locationLabel: "3 / 20")
        time.addTimeInterval(10)
        _ = try store.recordOpened(secondURL, kind: .epub, locationLabel: "第 2 / 8 章")
        time.addTimeInterval(10)
        let reopened = try store.recordOpened(firstURL, kind: .pdf, locationLabel: nil)
        store.updateLocation(for: firstURL, label: "4 / 20")

        XCTAssertEqual(reopened.id, first.id)
        XCTAssertEqual(store.documents.map(\.displayName), ["first.pdf", "second.epub"])
        XCTAssertEqual(store.documents.first?.lastLocationLabel, "4 / 20")

        let restored = RecentDocumentStore(defaults: defaults, bookmarking: bookmarker)
        XCTAssertEqual(restored.documents, store.documents)
    }

    @MainActor
    func testCapsHistoryAndRelocationKeepsIdentity() throws {
        let suite = "JieJuTests.RecentDocuments.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bookmarker = StubDocumentBookmarking()
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let store = RecentDocumentStore(defaults: defaults, bookmarking: bookmarker, maximumCount: 2)
        let one = directory.appendingPathComponent("one.pdf")
        let two = directory.appendingPathComponent("two.pdf")
        let three = directory.appendingPathComponent("three.epub")
        let moved = directory.appendingPathComponent("moved.pdf")
        for url in [one, two, three, moved] { _ = fileManager.createFile(atPath: url.path, contents: Data()) }

        let first = try store.recordOpened(one, kind: .pdf, locationLabel: nil)
        _ = try store.recordOpened(two, kind: .pdf, locationLabel: nil)
        _ = try store.recordOpened(three, kind: .epub, locationLabel: nil)
        XCTAssertEqual(store.documents.count, 2)
        XCTAssertFalse(store.documents.contains { $0.id == first.id })

        let second = try XCTUnwrap(store.documents.first { $0.displayName == "two.pdf" })
        try store.relocate(second, to: moved)
        XCTAssertEqual(store.documents.first?.id, second.id)
        XCTAssertEqual(store.documents.first?.displayName, "moved.pdf")
        XCTAssertEqual(try store.resolve(store.documents[0]), moved.standardizedFileURL)

        store.remove(store.documents[0])
        XCTAssertEqual(store.documents.count, 1)
    }

    @MainActor
    func testMissingAndInvalidBookmarksHaveActionableErrors() throws {
        let suite = "JieJuTests.RecentDocuments.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bookmarker = StubDocumentBookmarking()
        let store = RecentDocumentStore(defaults: defaults, bookmarking: bookmarker)
        let missingURL = URL(fileURLWithPath: "/tmp/definitely-missing-\(UUID().uuidString).pdf")
        let document = try store.recordOpened(missingURL, kind: .pdf, locationLabel: nil)

        XCTAssertThrowsError(try store.resolve(document)) { error in
            XCTAssertEqual(error as? RecentDocumentStoreError, .fileUnavailable)
        }

        bookmarker.invalidBookmarks.insert(document.bookmarkData)
        XCTAssertThrowsError(try store.resolve(document)) { error in
            XCTAssertEqual(error as? RecentDocumentStoreError, .invalidBookmark)
        }
    }

    @MainActor
    func testReaderRecordsEPUBAndKeepsDetailedLocation() async throws {
        let suite = "JieJuTests.RecentReader.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let recentStore = RecentDocumentStore(defaults: defaults, bookmarking: StubDocumentBookmarking())
        let positionStore = ReadingPositionStore(defaults: defaults)
        let model = ReaderViewModel(positionStore: positionStore, recentDocumentStore: recentStore)
        let url = try XCTUnwrap(
            Bundle(for: RecentDocumentStoreTests.self).url(forResource: "minimal", withExtension: "epub")
        )

        model.open(url)
        for _ in 0..<200 {
            if case .loaded = model.documentState { break }
            await Task.yield()
        }
        guard case .loaded = model.documentState else {
            return XCTFail("EPUB did not finish loading")
        }

        XCTAssertEqual(recentStore.documents.count, 1)
        XCTAssertEqual(recentStore.documents.first?.displayName, "minimal.epub")
        model.updateEPUBPage(2, pageCount: 5)
        XCTAssertEqual(recentStore.documents.first?.lastLocationLabel, "第 1 / 2 章 · 本章 3 / 5 页")

        model.closeDocument()
        XCTAssertEqual(model.documentState, .empty)
        XCTAssertEqual(recentStore.documents.count, 1)
    }
}
