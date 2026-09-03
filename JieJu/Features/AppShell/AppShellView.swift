import SwiftUI
import JieJuLanguage

private enum AppSection: String, CaseIterable, Identifiable {
    case reader
    case records
    case vocabulary
    case review
    case settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .reader: "阅读"
        case .records: "学习记录"
        case .vocabulary: "生词本"
        case .review: "随手温习"
        case .settings: "设置"
        }
    }
    var icon: String {
        switch self {
        case .reader: "book"
        case .records: "text.badge.checkmark"
        case .vocabulary: "character.book.closed"
        case .review: "rectangle.stack.badge.play"
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
                } else if activeSection == .vocabulary {
                    VocabularyBookView(model: library)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                } else if activeSection == .review {
                    ReviewSessionView(model: library) {
                        selection = .reader
                    }
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
            vocabularySaveHandler: library.saveVocabulary,
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

private struct ReviewSessionView: View {
    @ObservedObject var model: LearningLibraryModel
    let returnToReading: () -> Void
    @State private var showsAnswer = false
    @State private var isSubmittingRating = false
    @State private var sessionReviewedCount = 0

    private let gentleSessionSize = 10
    private var hasReachedGentlePause: Bool { sessionReviewedCount >= gentleSessionSize }
    private var current: ReviewQueueItem? {
        hasReachedGentlePause ? nil : model.dueReviewItems.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("随手温习").font(.title2.bold())
                    Text("想看几张都可以，随时回到阅读")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("回到阅读", systemImage: "book") { returnToReading() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Divider()

            if hasReachedGentlePause {
                gentlePauseView
            } else if let current {
                reviewCard(current)
            } else if model.vocabularyEntries.isEmpty {
                ContentUnavailableView(
                    "还没有复习卡片",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("从阅读解句中收藏生词后，会自动生成第一张记忆卡片。")
                )
            } else {
                ContentUnavailableView(
                    "先去读点喜欢的内容吧",
                    systemImage: "book.pages",
                    description: Text("暂时没有适合重温的词。不必每天打卡，想起来时再回来。")
                )
            }
        }
        .navigationTitle("随手温习")
        .task { await model.reload() }
        .onChange(of: current?.id) { _, _ in showsAnswer = false }
    }

    private var gentlePauseView: some View {
        ContentUnavailableView {
            Label("这次先看到这里", systemImage: "leaf")
        } description: {
            Text("语言学习是一件长期的事，不急于一时。你可以继续阅读，也可以按自己的心情再看几张。")
        } actions: {
            Button("回到阅读") { returnToReading() }
                .buttonStyle(.borderedProminent)
            Button("再看几张") {
                sessionReviewedCount = 0
                showsAnswer = false
            }
        }
    }

    private func reviewCard(_ item: ReviewQueueItem) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Text(item.entry.lemma)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .textSelection(.enabled)
                    Text(item.entry.language)
                        .font(.caption).foregroundStyle(.secondary)
                    if !showsAnswer {
                        Text("回想它的含义\(item.entry.reading == nil ? "" : "和读音")")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .padding(24)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))

                if showsAnswer {
                    VStack(alignment: .leading, spacing: 14) {
                        if let reading = item.entry.reading, !reading.isEmpty {
                            LabeledContent("读音") { Text(reading).textSelection(.enabled) }
                        }
                        if let partOfSpeech = item.entry.partOfSpeech, !partOfSpeech.isEmpty {
                            LabeledContent("词形/词性") { Text(partOfSpeech) }
                        }
                        ForEach(item.entry.senses) { sense in
                            Text(sense.meaning).font(.title3).textSelection(.enabled)
                        }
                        if let source = item.entry.sources.last {
                            Divider()
                            Text(source.sentence)
                                .font(.body).italic().textSelection(.enabled)
                            Text(source.document.fileName)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))

                    ratingButtons(for: item)
                    Text("按此刻的感觉选择就好，没有对错。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("显示答案", systemImage: "eye") { showsAnswer = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.space, modifiers: [])
                        .accessibilityIdentifier("review.showAnswer")
                }
            }
            .frame(maxWidth: 720)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private func ratingButtons(for item: ReviewQueueItem) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(ReviewRating.allCases.enumerated()), id: \.element) { index, rating in
                Button {
                    Task {
                        guard !isSubmittingRating else { return }
                        isSubmittingRating = true
                        await model.review(item, rating: rating)
                        sessionReviewedCount += 1
                        showsAnswer = false
                        isSubmittingRating = false
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(rating.title).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmittingRating)
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
                .accessibilityIdentifier("review.rate.\(rating.rawValue)")
            }
        }
    }

}

private struct VocabularyBookView: View {
    @ObservedObject var model: LearningLibraryModel
    @State private var selectedEntryID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(12)
            }
            if model.vocabularyEntries.isEmpty {
                ContentUnavailableView(
                    "还没有生词",
                    systemImage: "character.book.closed",
                    description: Text("从解句结果的重点表达或日语词形中收藏，也可以直接划选单词解释后收藏。")
                )
            } else {
                HSplitView {
                    List(model.vocabularyEntries, selection: $selectedEntryID) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.lemma).font(.headline)
                                if let reading = entry.reading, !reading.isEmpty {
                                    Text(reading).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(entry.senses.first?.meaning ?? "暂无释义")
                                .foregroundStyle(.secondary).lineLimit(2)
                            Text("\(entry.sources.count) 个语境 · \(entry.language)")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .tag(entry.id)
                    }
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)

                    if let entry = selectedEntry {
                        VocabularyEntryDetail(entry: entry) {
                            Task { await model.deleteVocabulary(entry) }
                        }
                    } else {
                        ContentUnavailableView("选择一个生词", systemImage: "character.book.closed")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .navigationTitle("生词本")
        .onChange(of: model.vocabularyEntries.map(\.id), initial: true) { _, ids in
            if let selectedEntryID, ids.contains(selectedEntryID) { return }
            selectedEntryID = ids.first
        }
    }

    private var selectedEntry: VocabularyEntry? {
        guard let selectedEntryID else { return nil }
        return model.vocabularyEntries.first { $0.id == selectedEntryID }
    }
}

private struct VocabularyEntryDetail: View {
    let entry: VocabularyEntry
    let delete: () -> Void
    @State private var confirmsDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.lemma).font(.title2.bold()).textSelection(.enabled)
                    if let reading = entry.reading, !reading.isEmpty {
                        Text("【\(reading)】").foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if let partOfSpeech = entry.partOfSpeech, !partOfSpeech.isEmpty {
                    Text(partOfSpeech).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(entry.senses) { sense in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(sense.meaning).textSelection(.enabled)
                        Text("解释语言：\(sense.explanationLanguage)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                }
                Text("来源语境").font(.headline)
                ForEach(entry.sources) { source in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(source.sentence).textSelection(.enabled)
                        Text("\(source.document.fileName)\(source.pageIndex.map { " · 位置 \($0 + 1)" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
                Button("删除这个生词", systemImage: "trash", role: .destructive) {
                    confirmsDeletion = true
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(24)
        }
        .confirmationDialog("确定删除这个生词及其来源？", isPresented: $confirmsDeletion) {
            Button("删除", role: .destructive, action: delete)
        }
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
