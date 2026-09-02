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

    var id: String { rawValue }
    var title: String { self == .mock ? "Mock（离线测试）" : "Ollama（本地模型）" }
    static let defaultProvider: AIProviderChoice = .ollama
}

enum ExplanationPresentationMode: String, CaseIterable, Identifiable {
    case sidebar
    case popover

    var id: String { rawValue }
    var title: String { self == .sidebar ? "侧边栏" : "弹窗" }
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
    @Published var explanationLanguage: String {
        didSet { defaults.set(explanationLanguage, forKey: Keys.explanationLanguage) }
    }
    @Published var explanationPresentationMode: ExplanationPresentationMode {
        didSet { defaults.set(explanationPresentationMode.rawValue, forKey: Keys.explanationPresentationMode) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        explanationLanguage = defaults.string(forKey: Keys.explanationLanguage) ?? "Chinese"
        explanationPresentationMode = ExplanationPresentationMode(
            rawValue: defaults.string(forKey: Keys.explanationPresentationMode) ?? ""
        ) ?? .sidebar
    }

    var providerSnapshot: any ReaderExplanationProviding {
        switch provider {
        case .mock: MockReaderExplanationProvider()
        case .ollama:
            OllamaReaderExplanationProvider(
                baseURL: URL(string: ollamaURL) ?? URL(string: "http://127.0.0.1:11434")!,
                model: modelName
            )
        }
    }

    func checkConnection() async {
        guard provider == .ollama else {
            connectionState = .ready("Mock 可用")
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

    private enum Keys {
        static let provider = "ai.provider"
        static let ollamaURL = "ai.ollamaURL"
        static let modelName = "ai.modelName"
        static let explanationLanguage = "ai.explanationLanguage"
        static let didMigrateToLocalModelDefault = "ai.didMigrateToLocalModelDefault"
        static let explanationPresentationMode = "reader.explanationPresentationMode"
    }
}
