import Foundation

/// EPUB 正文中的稳定位置。`textOffset` 使用 WebKit/JavaScript 的 UTF-16 文本偏移，
/// `textQuote` 用于内容轻微变化后的校验和邻近重定位，`progression` 是最终回退。
struct EPUBTextAnchor: Codable, Equatable, Sendable {
    let textOffset: Int
    let textQuote: String
    let progression: Double?

    init(textOffset: Int, textQuote: String, progression: Double? = nil) {
        self.textOffset = max(0, textOffset)
        self.textQuote = textQuote
        self.progression = progression.map { min(1, max(0, $0)) }
    }
}

struct EPUBReadingPosition: Codable, Equatable, Sendable {
    let chapterIndex: Int
    let pageIndex: Int
    let chapterID: String?
    let chapterHref: String?
    let textAnchor: EPUBTextAnchor?

    init(
        chapterIndex: Int,
        pageIndex: Int,
        chapterID: String? = nil,
        chapterHref: String? = nil,
        textAnchor: EPUBTextAnchor? = nil
    ) {
        self.chapterIndex = chapterIndex
        self.pageIndex = pageIndex
        self.chapterID = chapterID
        self.chapterHref = chapterHref
        self.textAnchor = textAnchor
    }
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
        saveEPUB(.init(chapterIndex: chapterIndex, pageIndex: pageIndex), for: url)
    }

    func saveEPUB(_ position: EPUBReadingPosition, for url: URL) {
        guard position.chapterIndex >= 0, position.pageIndex >= 0,
              let data = try? JSONEncoder().encode(position) else { return }
        defaults.set(data, forKey: epubKey(for: url))
    }

    private func key(for url: URL) -> String {
        keyPrefix + url.standardizedFileURL.path
    }

    private func epubKey(for url: URL) -> String {
        "readingPosition.epub.v1." + url.standardizedFileURL.path
    }
}
