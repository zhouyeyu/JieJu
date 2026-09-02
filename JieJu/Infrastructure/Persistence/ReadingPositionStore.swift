import Foundation

struct EPUBReadingPosition: Codable, Equatable, Sendable {
    let chapterIndex: Int
    let pageIndex: Int
}

/// 保存每个文档的最近阅读页码（按文档路径存储），重启 App 后自动恢复。
final class ReadingPositionStore {
    private let defaults: UserDefaults
    private let keyPrefix = "readingPosition.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 返回该文档上次阅读的页码（0 起），从未打开过则返回 nil。
    func position(for url: URL) -> Int? {
        defaults.object(forKey: key(for: url)) as? Int
    }

    func save(_ page: Int, for url: URL) {
        guard page >= 0 else { return }
        defaults.set(page, forKey: key(for: url))
    }

    func clear(for url: URL) {
        defaults.removeObject(forKey: key(for: url))
        defaults.removeObject(forKey: epubKey(for: url))
    }

    func epubPosition(for url: URL) -> EPUBReadingPosition? {
        guard let data = defaults.data(forKey: epubKey(for: url)) else { return nil }
        return try? JSONDecoder().decode(EPUBReadingPosition.self, from: data)
    }

    func saveEPUB(chapterIndex: Int, pageIndex: Int, for url: URL) {
        guard chapterIndex >= 0, pageIndex >= 0,
              let data = try? JSONEncoder().encode(EPUBReadingPosition(
                chapterIndex: chapterIndex, pageIndex: pageIndex
              )) else { return }
        defaults.set(data, forKey: epubKey(for: url))
    }

    private func key(for url: URL) -> String {
        keyPrefix + url.standardizedFileURL.path
    }

    private func epubKey(for url: URL) -> String {
        "readingPosition.epub.v1." + url.standardizedFileURL.path
    }
}
