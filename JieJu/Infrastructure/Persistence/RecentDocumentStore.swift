import Combine
import Foundation

struct RecentDocument: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case pdf
        case epub

        var title: String { rawValue.uppercased() }
        var systemImage: String { self == .pdf ? "doc.richtext" : "book.closed" }
    }

    let id: UUID
    var displayName: String
    var kind: Kind
    var bookmarkData: Data
    var fallbackPath: String
    var lastLocationLabel: String?
    var lastOpenedAt: Date
}

struct ResolvedDocumentBookmark: Equatable, Sendable {
    let url: URL
    let isStale: Bool
}

protocol DocumentBookmarking {
    func bookmark(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> ResolvedDocumentBookmark
}

struct SecurityScopedDocumentBookmarking: DocumentBookmarking {
    func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: [.contentModificationDateKey],
            relativeTo: nil
        )
    }

    func resolve(_ data: Data) throws -> ResolvedDocumentBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return .init(url: url, isStale: isStale)
    }
}

enum RecentDocumentStoreError: LocalizedError, Equatable {
    case invalidBookmark
    case fileUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidBookmark:
            "无法读取这本书的访问授权，请重新定位文件。"
        case .fileUnavailable:
            "文件似乎已被移动或删除，请重新定位。"
        }
    }
}

@MainActor
final class RecentDocumentStore: ObservableObject {
    @Published private(set) var documents: [RecentDocument]

    private let defaults: UserDefaults
    private let bookmarking: any DocumentBookmarking
    private let maximumCount: Int
    private let now: () -> Date
    private let storageKey = "recentDocuments.v1"

    init(
        defaults: UserDefaults = .standard,
        bookmarking: any DocumentBookmarking = SecurityScopedDocumentBookmarking(),
        maximumCount: Int = 12,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.bookmarking = bookmarking
        self.maximumCount = max(1, maximumCount)
        self.now = now
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([RecentDocument].self, from: data) {
            documents = Array(decoded.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.prefix(self.maximumCount))
        } else {
            documents = []
        }
    }

    @discardableResult
    func recordOpened(
        _ url: URL,
        kind: RecentDocument.Kind,
        locationLabel: String?
    ) throws -> RecentDocument {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path
        let bookmark = try bookmarking.bookmark(for: standardizedURL)
        let existing = documents.first { $0.fallbackPath == path }
        let item = RecentDocument(
            id: existing?.id ?? UUID(),
            displayName: standardizedURL.lastPathComponent,
            kind: kind,
            bookmarkData: bookmark,
            fallbackPath: path,
            lastLocationLabel: locationLabel ?? existing?.lastLocationLabel,
            lastOpenedAt: now()
        )
        documents.removeAll { $0.id == item.id || $0.fallbackPath == path }
        documents.insert(item, at: 0)
        documents = Array(documents.prefix(maximumCount))
        persist()
        return item
    }

    func updateLocation(for url: URL, label: String) {
        let path = url.standardizedFileURL.path
        guard let index = documents.firstIndex(where: { $0.fallbackPath == path }) else { return }
        documents[index].lastLocationLabel = label
        persist()
    }

    func resolve(_ document: RecentDocument) throws -> URL {
        let resolved: ResolvedDocumentBookmark
        do {
            resolved = try bookmarking.resolve(document.bookmarkData)
        } catch {
            throw RecentDocumentStoreError.invalidBookmark
        }
        let startedAccess = resolved.url.startAccessingSecurityScopedResource()
        defer {
            if startedAccess { resolved.url.stopAccessingSecurityScopedResource() }
        }
        guard FileManager.default.fileExists(atPath: resolved.url.path) else {
            throw RecentDocumentStoreError.fileUnavailable
        }
        if resolved.isStale {
            try relocate(document, to: resolved.url)
        }
        return resolved.url
    }

    func relocate(_ document: RecentDocument, to url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RecentDocumentStoreError.fileUnavailable
        }
        let standardizedURL = url.standardizedFileURL
        let bookmark = try bookmarking.bookmark(for: standardizedURL)
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        var relocated = documents.remove(at: index)
        relocated.displayName = standardizedURL.lastPathComponent
        relocated.fallbackPath = standardizedURL.path
        relocated.bookmarkData = bookmark
        relocated.lastOpenedAt = now()
        documents.insert(relocated, at: 0)
        persist()
    }

    func remove(_ document: RecentDocument) {
        documents.removeAll { $0.id == document.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
