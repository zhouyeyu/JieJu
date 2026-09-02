import SwiftUI
import JieJuLanguage

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
            ZStack {
                // Reader 必须始终留在视图树中，否则切到设置时其 StateObject 会连同文档一起释放。
                readerView
                    .opacity(activeSection == .reader ? 1 : 0)
                    .allowsHitTesting(activeSection == .reader)
                    .disabled(activeSection != .reader)
                    .accessibilityHidden(activeSection != .reader)

                if activeSection == .records {
                    LearningRecordsView(model: library)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                } else if activeSection == .settings {
                    AISettingsView(settings: settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                }
            }
        }
        .task { await library.reload() }
    }

    private var activeSection: AppSection { selection ?? .reader }

    private var readerView: some View {
        ReaderView(
            explanationProvider: settings.providerSnapshot,
            saveHandler: { payload in
                Task { await library.save(payload, modelName: settings.provider == .ollama ? settings.modelName : "mock") }
            },
            explanationLanguage: settings.explanationLanguage,
            configurationID: "\(settings.provider.rawValue)-\(settings.ollamaURL)-\(settings.modelName)-\(settings.explanationLanguage)",
            explanationPresentationMode: settings.explanationPresentationMode,
            furiganaDisplayMode: settings.furiganaDisplayMode,
            epubReadingStyle: EPUBReadingStyle(
                fontSize: settings.epubFontSize,
                lineHeight: settings.epubLineHeight,
                horizontalMargin: settings.epubHorizontalMargin,
                showsFurigana: settings.furiganaDisplayMode == .kanji,
                theme: settings.epubReaderTheme
            )
        )
    }
}

private struct LearningRecordsView: View {
    @ObservedObject var model: LearningLibraryModel

    var body: some View {
        Group {
            if model.records.isEmpty {
                ContentUnavailableView("还没有学习记录", systemImage: "text.badge.plus", description: Text("在 PDF 或 EPUB 中选择一句话并保存解释。"))
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
    @State private var editingCustomLanguage = false
    private static let customTag = "__custom__"

    var body: some View {
        Form {
            Picker("解释服务", selection: $settings.provider) {
                ForEach(AIProviderChoice.allCases) { Text($0.title).tag($0) }
            }
            TextField("Ollama 地址", text: $settings.ollamaURL)
                .disabled(settings.provider != .ollama)
            TextField("模型名称", text: $settings.modelName)
                .disabled(settings.provider != .ollama)
            Picker("解释语言", selection: languageBinding) {
                ForEach(AppSettings.presetExplanationLanguages, id: \.self) { language in
                    Text(AppSettings.localizedName(of: language)).tag(language)
                }
                Text("自定义…").tag(Self.customTag)
            }
            Picker("解句显示方式", selection: $settings.explanationPresentationMode) {
                ForEach(ExplanationPresentationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.explanationPresentationMode")
            Picker("日语汉字注音", selection: $settings.furiganaDisplayMode) {
                ForEach(FuriganaDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.furiganaDisplayMode")
            Section("EPUB 排版") {
                Picker("阅读背景", selection: $settings.epubReaderTheme) {
                    ForEach(EPUBReaderTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.epubReaderTheme")
                LabeledContent("字号 \(Int(settings.epubFontSize))") {
                    Slider(value: $settings.epubFontSize, in: 14...28, step: 1)
                }
                LabeledContent("行距 \(settings.epubLineHeight, format: .number.precision(.fractionLength(2)))") {
                    Slider(value: $settings.epubLineHeight, in: 1.3...2.2, step: 0.05)
                }
                LabeledContent("页边距 \(Int(settings.epubHorizontalMargin))") {
                    Slider(value: $settings.epubHorizontalMargin, in: 24...90, step: 2)
                }
            }
            if editingCustomLanguage || !AppSettings.presetExplanationLanguages.contains(settings.explanationLanguage) {
                TextField("自定义语言（英文名，如 Arabic）", text: $settings.explanationLanguage)
                    .accessibilityIdentifier("settings.explanationLanguage")
            }
            HStack {
                Button("检查连接") { Task { await settings.checkConnection() } }
                    .disabled(settings.connectionState == .checking)
                    .accessibilityIdentifier("settings.checkAI")
                connectionStatus
            }
            Text("默认模型：\(OllamaDefaults.model)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("设置")
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { settings.explanationLanguage },
            set: { newValue in
                if newValue == Self.customTag {
                    editingCustomLanguage = true
                } else {
                    editingCustomLanguage = false
                    settings.explanationLanguage = newValue
                }
            }
        )
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
