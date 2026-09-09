import Foundation
import JieJuLanguage

enum AIConnectionState: Equatable {
    case idle
    case checking
    case ready(String)
    case modelMissing(String)
    case unavailable(String)
}

enum AIProviderChoice: String, CaseIterable, Identifiable {
    case mock
    case ollama
    case cloud

    var id: String { rawValue }
    var title: String {
        switch self {
        case .mock: "Mock（离线测试）"
        case .ollama: "Ollama（本地模型）"
        case .cloud: "云端 API（OpenAI 兼容）"
        }
    }
    static let defaultProvider: AIProviderChoice = .ollama
}

enum ExplanationPresentationMode: String, CaseIterable, Identifiable {
    case sidebar
    case popover

    var id: String { rawValue }
    var title: String { self == .sidebar ? "侧边栏" : "弹窗" }
}

enum FuriganaDisplayMode: String, CaseIterable, Identifiable {
    case hidden
    case kanji

    var id: String { rawValue }
    var title: String { self == .hidden ? "关闭" : "开启" }
}

@MainActor
final class AppSettings: ObservableObject {
    static let presetExplanationLanguages = ["Chinese", "English", "Japanese", "Korean", "French", "German"]

    static func localizedName(of language: String) -> String {
        switch language {
        case "Chinese": "中文"
        case "English": "English"
        case "Japanese": "日本語"
        case "Korean": "한국어"
        case "French": "Français"
        case "German": "Deutsch"
        default: language
        }
    }
    @Published private(set) var connectionState: AIConnectionState = .idle
    @Published var provider: AIProviderChoice {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }
    @Published var ollamaURL: String {
        didSet { defaults.set(ollamaURL, forKey: Keys.ollamaURL) }
    }
    @Published var modelName: String {
        didSet { defaults.set(modelName, forKey: Keys.modelName) }
    }
    @Published var cloudURL: String {
        didSet { defaults.set(cloudURL, forKey: Keys.cloudURL) }
    }
    @Published var cloudModelName: String {
        didSet { defaults.set(cloudModelName, forKey: Keys.cloudModelName) }
    }
    @Published var cloudAPIKey: String {
        didSet { _ = apiKeyStore.save(cloudAPIKey) }
    }
    @Published var explanationLanguage: String {
        didSet { defaults.set(explanationLanguage, forKey: Keys.explanationLanguage) }
    }
    @Published var explanationPresentationMode: ExplanationPresentationMode {
        didSet { defaults.set(explanationPresentationMode.rawValue, forKey: Keys.explanationPresentationMode) }
    }
    @Published var epubFontSize: Double { didSet { defaults.set(epubFontSize, forKey: Keys.epubFontSize) } }
    @Published var epubLineHeight: Double { didSet { defaults.set(epubLineHeight, forKey: Keys.epubLineHeight) } }
    @Published var epubHorizontalMargin: Double { didSet { defaults.set(epubHorizontalMargin, forKey: Keys.epubHorizontalMargin) } }
    @Published var epubReaderTheme: EPUBReaderTheme {
        didSet { defaults.set(epubReaderTheme.rawValue, forKey: Keys.epubReaderTheme) }
    }
    @Published var furiganaDisplayMode: FuriganaDisplayMode {
        didSet { defaults.set(furiganaDisplayMode.rawValue, forKey: Keys.furiganaDisplayMode) }
    }

    private let defaults: UserDefaults
    private let apiKeyStore: any APIKeyStoring

    init(defaults: UserDefaults = .standard, apiKeyStore: any APIKeyStoring = KeychainAPIKeyStore()) {
        self.defaults = defaults
        self.apiKeyStore = apiKeyStore
        let storedProvider = AIProviderChoice(rawValue: defaults.string(forKey: Keys.provider) ?? "")
        if defaults.bool(forKey: Keys.didMigrateToLocalModelDefault) {
            provider = storedProvider ?? .defaultProvider
        } else {
            // Earlier development builds defaulted to Mock and persisted that choice.
            // Migrate once so existing installations start using the real local model.
            provider = .defaultProvider
            defaults.set(AIProviderChoice.defaultProvider.rawValue, forKey: Keys.provider)
            defaults.set(true, forKey: Keys.didMigrateToLocalModelDefault)
        }
        ollamaURL = defaults.string(forKey: Keys.ollamaURL) ?? "http://127.0.0.1:11434"
        modelName = defaults.string(forKey: Keys.modelName) ?? OllamaDefaults.model
        cloudURL = defaults.string(forKey: Keys.cloudURL) ?? "https://api.openai.com/v1"
        cloudModelName = defaults.string(forKey: Keys.cloudModelName) ?? "gpt-4.1-mini"
        cloudAPIKey = apiKeyStore.load()
        explanationLanguage = defaults.string(forKey: Keys.explanationLanguage) ?? "Chinese"
        explanationPresentationMode = ExplanationPresentationMode(
            rawValue: defaults.string(forKey: Keys.explanationPresentationMode) ?? ""
        ) ?? .sidebar
        epubFontSize = defaults.object(forKey: Keys.epubFontSize) as? Double ?? 18
        epubLineHeight = defaults.object(forKey: Keys.epubLineHeight) as? Double ?? 1.75
        epubHorizontalMargin = defaults.object(forKey: Keys.epubHorizontalMargin) as? Double ?? 54
        epubReaderTheme = EPUBReaderTheme(rawValue: defaults.string(forKey: Keys.epubReaderTheme) ?? "") ?? .paper
        furiganaDisplayMode = FuriganaDisplayMode(rawValue: defaults.string(forKey: Keys.furiganaDisplayMode) ?? "") ?? .hidden
    }

    var providerSnapshot: any ReaderExplanationProviding {
        switch provider {
        case .mock: MockReaderExplanationProvider()
        case .ollama:
            OllamaReaderExplanationProvider(
                baseURL: URL(string: ollamaURL) ?? URL(string: "http://127.0.0.1:11434")!,
                model: modelName
            )
        case .cloud:
            OpenAICompatibleReaderExplanationProvider(
                baseURL: URL(string: cloudURL) ?? URL(string: "https://api.openai.com/v1")!,
                apiKey: cloudAPIKey,
                model: cloudModelName
            )
        }
    }

    var vocabularyProviderSnapshot: any ReaderVocabularyProviding {
        switch provider {
        case .mock: MockReaderVocabularyProvider()
        case .ollama:
            OllamaReaderExplanationProvider(
                baseURL: URL(string: ollamaURL) ?? URL(string: "http://127.0.0.1:11434")!,
                model: modelName
            )
        case .cloud:
            OpenAICompatibleReaderExplanationProvider(
                baseURL: URL(string: cloudURL) ?? URL(string: "https://api.openai.com/v1")!,
                apiKey: cloudAPIKey,
                model: cloudModelName
            )
        }
    }

    var activeModelName: String {
        switch provider {
        case .mock: "mock"
        case .ollama: modelName
        case .cloud: cloudModelName
        }
    }

    var providerConfigurationID: String {
        let credentialMarker = provider == .cloud ? cloudAPIKey.hashValue : 0
        return "\(provider.rawValue)-\(ollamaURL)-\(modelName)-\(cloudURL)-\(cloudModelName)-\(credentialMarker)-\(explanationLanguage)"
    }

    func checkConnection() async {
        guard provider != .mock else {
            connectionState = .ready("Mock 可用")
            return
        }
        if provider == .cloud {
            await checkCloudConnection()
            return
        }
        guard let url = URL(string: ollamaURL), let scheme = url.scheme,
              ["http", "https"].contains(scheme), url.host != nil else {
            connectionState = .unavailable("Ollama 地址无效")
            return
        }
        guard !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            connectionState = .modelMissing("模型名称不能为空")
            return
        }

        connectionState = .checking
        let diagnostic = await OllamaReadingAI(baseURL: url, model: modelName, timeout: 5).diagnose()
        switch diagnostic {
        case .ready(let model, let count):
            connectionState = .ready("已连接：\(model)（本地共 \(count) 个模型）")
        case .modelMissing(let required, _):
            connectionState = .modelMissing("未安装 \(required)，请运行 ollama pull \(required)")
        case .serviceUnavailable(let message):
            connectionState = .unavailable("无法连接 Ollama：\(message)")
        }
    }

    private func checkCloudConnection() async {
        guard let url = URL(string: cloudURL), let scheme = url.scheme,
              ["http", "https"].contains(scheme), url.host != nil else {
            connectionState = .unavailable("云端 API 地址无效")
            return
        }
        guard !cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            connectionState = .unavailable("请先输入 API Key")
            return
        }
        guard !cloudModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            connectionState = .modelMissing("云端模型名称不能为空")
            return
        }
        connectionState = .checking
        do {
            try await OpenAICompatibleReadingAI(
                baseURL: url, apiKey: cloudAPIKey, model: cloudModelName, timeout: 10
            ).checkAvailability()
            connectionState = .ready("云端 API 已连接：\(cloudModelName)")
        } catch {
            connectionState = .unavailable(error.localizedDescription)
        }
    }

    private enum Keys {
        static let provider = "ai.provider"
        static let ollamaURL = "ai.ollamaURL"
        static let modelName = "ai.modelName"
        static let cloudURL = "ai.cloudURL"
        static let cloudModelName = "ai.cloudModelName"
        static let explanationLanguage = "ai.explanationLanguage"
        static let didMigrateToLocalModelDefault = "ai.didMigrateToLocalModelDefault"
        static let explanationPresentationMode = "reader.explanationPresentationMode"
        static let epubFontSize = "reader.epub.fontSize"
        static let epubLineHeight = "reader.epub.lineHeight"
        static let epubHorizontalMargin = "reader.epub.horizontalMargin"
        static let epubReaderTheme = "reader.epub.theme"
        static let furiganaDisplayMode = "reader.japanese.furiganaDisplayMode"
    }
}
