import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case reader
    case records
    case settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .reader: "阅读"
        case .records: "学习记录"
        case .settings: "设置"
        }
    }
    var icon: String {
        switch self {
        case .reader: "book"
        case .records: "text.badge.checkmark"
        case .settings: "gearshape"
        }
    }
}

struct AppShellView: View {
    @State private var selection: AppSection? = .reader
    @StateObject private var settings = AppSettings()
    @StateObject private var library = LearningLibraryModel()

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationTitle("JieJu")
        } detail: {
            switch selection ?? .reader {
            case .reader:
                ReaderView(
                    explanationProvider: settings.providerSnapshot,
                    saveHandler: { payload in
                        Task { await library.save(payload, modelName: settings.provider == .ollama ? settings.modelName : "mock") }
                    }
                )
                .id("\(settings.provider.rawValue)-\(settings.ollamaURL)-\(settings.modelName)")
            case .records:
                LearningRecordsView(model: library)
            case .settings:
                AISettingsView(settings: settings)
            }
        }
        .task { await library.reload() }
    }
}

private struct LearningRecordsView: View {
    @ObservedObject var model: LearningLibraryModel

    var body: some View {
        Group {
            if model.records.isEmpty {
                ContentUnavailableView("还没有学习记录", systemImage: "text.badge.plus", description: Text("在 PDF 中选择一句话并保存解释。"))
            } else {
                List(model.records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.request.targetText).font(.headline)
                        Text(record.explanation.translation).foregroundStyle(.secondary)
                        Text(record.document.fileName).font(.caption).foregroundStyle(.tertiary)
                    }
                    .contextMenu { Button("删除", role: .destructive) { Task { await model.delete(record) } } }
                }
            }
        }
        .navigationTitle("学习记录")
    }
}

private struct AISettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("解释服务", selection: $settings.provider) {
                ForEach(AIProviderChoice.allCases) { Text($0.title).tag($0) }
            }
            TextField("Ollama 地址", text: $settings.ollamaURL)
                .disabled(settings.provider != .ollama)
            TextField("模型名称", text: $settings.modelName)
                .disabled(settings.provider != .ollama)
            HStack {
                Button("检查连接") { Task { await settings.checkConnection() } }
                    .disabled(settings.connectionState == .checking)
                    .accessibilityIdentifier("settings.checkAI")
                connectionStatus
            }
            Text("默认模型：qwen2.5:0.5b-instruct")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("设置")
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch settings.connectionState {
        case .idle:
            Text("尚未检查").foregroundStyle(.secondary)
        case .checking:
            ProgressView().controlSize(.small)
            Text("正在检查…").foregroundStyle(.secondary)
        case .ready(let message):
            Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .modelMissing(let message):
            Label(message, systemImage: "arrow.down.circle").foregroundStyle(.orange)
        case .unavailable(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
