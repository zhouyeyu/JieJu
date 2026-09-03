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
                try await library.save(payload, modelName: settings.activeModelName)
            },
            explanationLanguage: settings.explanationLanguage,
            configurationID: settings.providerConfigurationID,
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
    @State private var selectedRecordID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(12)
            }
            if model.records.isEmpty {
                ContentUnavailableView("还没有学习记录", systemImage: "text.badge.plus", description: Text("在 PDF 或 EPUB 中选择一句话并保存解释。"))
            } else {
                HSplitView {
                    List(model.records, selection: $selectedRecordID) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.request.targetText).font(.headline).lineLimit(2)
                            Text(record.explanation.translation).foregroundStyle(.secondary).lineLimit(2)
                            Text(record.document.fileName).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .tag(record.id)
                        .contextMenu { Button("删除", role: .destructive) { Task { await model.delete(record) } } }
                    }
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)

                    if let record = selectedRecord {
                        LearningRecordDetail(record: record) {
                            Task { await model.delete(record) }
                        }
                    } else {
                        ContentUnavailableView("选择一条学习记录", systemImage: "text.book.closed")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .navigationTitle("学习记录")
        .onChange(of: model.records.map(\.id), initial: true) { _, ids in
            if let selectedRecordID, ids.contains(selectedRecordID) { return }
            selectedRecordID = ids.first
        }
    }

    private var selectedRecord: SavedExplanationRecord? {
        guard let selectedRecordID else { return nil }
        return model.records.first { $0.id == selectedRecordID }
    }
}

private struct LearningRecordDetail: View {
    let record: SavedExplanationRecord
    let delete: () -> Void
    @State private var confirmsDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(record.request.targetText)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                detailCard("翻译", value: record.explanation.translation)
                detailCard("句子主干", value: record.explanation.sentenceCore)
                if !record.explanation.grammarPoints.isEmpty {
                    listCard("语法", values: record.explanation.grammarPoints.map(\.explanation))
                }
                if !record.explanation.keyPhrases.isEmpty {
                    listCard("重点表达", values: record.explanation.keyPhrases.map(\.meaning))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(record.document.fileName).lineLimit(2)
                    if let page = record.pageIndex { Text("位置：\(page + 1)") }
                    if let model = record.explanation.modelName { Text("模型：\(model)") }
                    Text(record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("删除这条记录", systemImage: "trash", role: .destructive) {
                    confirmsDeletion = true
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("确定删除这条学习记录？", isPresented: $confirmsDeletion) {
            Button("删除", role: .destructive, action: delete)
        }
    }

    private func detailCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(value).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func listCard(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text("\(index + 1). \(value)").textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
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
            if settings.provider == .ollama {
                TextField("Ollama 地址", text: $settings.ollamaURL)
                TextField("模型名称", text: $settings.modelName)
                Text("内容仅在本机处理，不会发送到云端。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if settings.provider == .cloud {
                TextField("API 地址", text: $settings.cloudURL)
                    .textContentType(.URL)
                    .accessibilityIdentifier("settings.cloudURL")
                SecureField("API Key（保存在系统钥匙串）", text: $settings.cloudAPIKey)
                    .accessibilityIdentifier("settings.cloudAPIKey")
                TextField("模型名称", text: $settings.cloudModelName)
                    .accessibilityIdentifier("settings.cloudModelName")
                Label("云端模式会把选中句子及前后文发送给所选服务。", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                EPUBLayoutPreview(settings: settings)
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
            if settings.provider == .ollama {
                Text("默认模型：\(OllamaDefaults.model)")
                    .font(.caption).foregroundStyle(.secondary)
            }
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

private struct EPUBLayoutPreview: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        GeometryReader { geometry in
            let previewMargin = min(
                CGFloat(settings.epubHorizontalMargin),
                max(24, geometry.size.width * 0.28)
            )
            VStack(alignment: .leading, spacing: 12) {
                Text("阅读预览")
                    .font(.system(size: min(settings.epubFontSize + 4, 30), weight: .semibold))
                Text("语言并不只是需要记忆的知识。\n当我们在真实的故事里理解一句话，它才会慢慢成为自己的表达。")
                    .font(.system(size: settings.epubFontSize))
                    .lineSpacing(max(0, settings.epubFontSize * (settings.epubLineHeight - 1.2)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(settings.epubReaderTheme.previewForeground)
            .padding(.vertical, 22)
            .padding(.horizontal, previewMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(settings.epubReaderTheme.previewBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(settings.epubReaderTheme.previewForeground.opacity(0.12))
            }
            .animation(.easeOut(duration: 0.12), value: settings.epubFontSize)
            .animation(.easeOut(duration: 0.12), value: settings.epubLineHeight)
            .animation(.easeOut(duration: 0.12), value: settings.epubHorizontalMargin)
            .animation(.easeOut(duration: 0.12), value: settings.epubReaderTheme)
        }
        .frame(height: 220)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("EPUB 排版预览")
    }
}

private extension EPUBReaderTheme {
    var previewBackground: Color {
        switch self {
        case .paper: Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255)
        case .night: Color(red: 22 / 255, green: 24 / 255, blue: 29 / 255)
        case .sepia: Color(red: 244 / 255, green: 236 / 255, blue: 216 / 255)
        case .sage: Color(red: 221 / 255, green: 232 / 255, blue: 213 / 255)
        }
    }

    var previewForeground: Color {
        switch self {
        case .paper: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
        case .night: Color(red: 242 / 255, green: 242 / 255, blue: 244 / 255)
        case .sepia: Color(red: 51 / 255, green: 43 / 255, blue: 34 / 255)
        case .sage: Color(red: 34 / 255, green: 48 / 255, blue: 40 / 255)
        }
    }
}
