import Foundation

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
    }

    private func key(for url: URL) -> String {
        keyPrefix + url.standardizedFileURL.path
    }
}
