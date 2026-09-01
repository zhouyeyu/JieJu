import Foundation

enum AIProviderChoice: String, CaseIterable, Identifiable {
    case mock
    case ollama

    var id: String { rawValue }
    var title: String { self == .mock ? "Mock（离线测试）" : "Ollama（本地模型）" }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var provider: AIProviderChoice {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }
    @Published var ollamaURL: String {
        didSet { defaults.set(ollamaURL, forKey: Keys.ollamaURL) }
    }
    @Published var modelName: String {
        didSet { defaults.set(modelName, forKey: Keys.modelName) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = AIProviderChoice(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .mock
        ollamaURL = defaults.string(forKey: Keys.ollamaURL) ?? "http://127.0.0.1:11434"
        modelName = defaults.string(forKey: Keys.modelName) ?? "qwen2.5:0.5b-instruct"
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

    private enum Keys {
        static let provider = "ai.provider"
        static let ollamaURL = "ai.ollamaURL"
        static let modelName = "ai.modelName"
    }
}

