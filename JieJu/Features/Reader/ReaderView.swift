import SwiftUI

struct ReaderView: View {
    @StateObject private var model: ReaderViewModel
    private let explanationProvider: any ReaderExplanationProviding
    private let explanationLanguage: String
    private let configurationID: String
    private let explanationPresentationMode: ExplanationPresentationMode
    private let epubReadingStyle: EPUBReadingStyle

    init(
        explanationProvider: any ReaderExplanationProviding = MockReaderExplanationProvider(),
        saveHandler: @escaping @MainActor (ReaderSavePayload) -> Void = { _ in },
        explanationLanguage: String = "Chinese",
        configurationID: String = "default",
        explanationPresentationMode: ExplanationPresentationMode = .sidebar,
        epubReadingStyle: EPUBReadingStyle = EPUBReadingStyle()
    ) {
        self.explanationProvider = explanationProvider
        self.explanationLanguage = explanationLanguage
        self.configurationID = configurationID
        self.explanationPresentationMode = explanationPresentationMode
        self.epubReadingStyle = epubReadingStyle
        _model = StateObject(wrappedValue: ReaderViewModel(
            explanationProvider: explanationProvider,
            saveHandler: saveHandler,
            explanationLanguage: explanationLanguage
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 520)
        .accessibilityIdentifier("reader.screen")
        .onChange(of: configurationID, initial: true) {
            model.updateExplanationConfiguration(
                provider: explanationProvider,
                explanationLanguage: explanationLanguage
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.documentState {
        case .empty:
            ReaderEmptyView(openAction: model.chooseDocument)
        case .loading:
            ProgressView("正在打开文档…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("无法打开文档", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("选择其他文档", action: model.chooseDocument)
            }
        case .loaded(let metadata):
            HSplitView {
                ZStack(alignment: .topLeading) {
                    switch metadata.kind {
                    case .pdf:
                        if let document = model.document {
                        PDFReaderView(
                            document: document,
                            initialPageIndex: model.restoredPageIndex,
                            onSelectionChange: model.updateSelection,
                            onPageChange: model.updateCurrentPage
                        )
                        }
                    case .epub:
                        if let epub = model.epubDocument,
                           epub.chapters.indices.contains(model.currentPageIndex) {
                            EPUBPagedReaderView(
                                document: epub,
                                chapterIndex: model.currentPageIndex,
                                initialPageAtEnd: model.epubOpenAtEnd,
                                readingStyle: epubReadingStyle,
                                onPreviousChapter: model.showPreviousChapter,
                                onNextChapter: model.showNextChapter,
                                onSelectionChange: model.updateSelection
                            )
                            .id("\(epub.chapters[model.currentPageIndex].id)-\(epubReadingStyle.fontSize)-\(epubReadingStyle.lineHeight)-\(epubReadingStyle.horizontalMargin)")
                        }
                    }
                        explanationButton
                }
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                if explanationPresentationMode == .sidebar,
                   model.isExplanationPresented,
                   let selection = model.selection {
                    ReaderExplanationPanel(
                        selectedText: selection.targetText,
                            state: model.explanationState,
                            deepAnalysisState: model.deepAnalysisState,
                            save: model.saveExplanation,
                            retry: model.requestExplanation,
                            analyzeDeep: model.requestDeepAnalysis,
                        close: model.dismissExplanation,
                        presentation: .sidebar
                    )
                    .frame(minWidth: 340, idealWidth: 400, maxWidth: 480, maxHeight: .infinity)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if case let .loaded(metadata) = model.documentState {
                Text(metadata.displayName)
                    .lineLimit(1)
                    .font(.headline)
                Spacer()
                if let pageLabel = model.pageLabel {
                    Text(pageLabel).monospacedDigit().foregroundStyle(.secondary)
                }
                if metadata.kind == .epub {
                    if let epub = model.epubDocument,
                       epub.chapters.indices.contains(model.currentPageIndex) {
                        Picker("章节", selection: Binding(
                            get: { model.currentPageIndex },
                            set: { model.updateCurrentPage($0) }
                        )) {
                            ForEach(Array(epub.chapters.enumerated()), id: \.element.id) { index, chapter in
                                Text(chapter.title).tag(index)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                        .accessibilityLabel("章节目录")
                    }
                }
                Button("关闭", action: model.closeDocument)
            } else {
                Text("JieJu Reader").font(.headline)
                Spacer()
                Button("打开文档", action: model.chooseDocument)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    @ViewBuilder
    private var explanationButton: some View {
        if let selection = model.selection {
            explanationTrigger(for: selection)
        }
    }

    @ViewBuilder
    private func explanationTrigger(for selection: ReaderSelection) -> some View {
        let button = Button("解释", systemImage: "text.bubble", action: model.requestExplanation)
                .buttonStyle(.borderedProminent)
                .position(
                    x: max(52, selection.anchorRect.midX),
                    y: max(22, selection.anchorRect.minY - 18)
                )

        if explanationPresentationMode == .popover {
            button
                .popover(isPresented: $model.isExplanationPresented, arrowEdge: .bottom) {
                    ReaderExplanationPanel(
                        selectedText: selection.targetText,
                        state: model.explanationState,
                        deepAnalysisState: model.deepAnalysisState,
                        save: model.saveExplanation,
                        retry: model.requestExplanation,
                        analyzeDeep: model.requestDeepAnalysis,
                        close: model.dismissExplanation,
                        presentation: .popover
                    )
                }
                .accessibilityIdentifier("reader.explain")
        } else {
            button.accessibilityIdentifier("reader.explain")
        }
    }
}

private struct ReaderEmptyView: View {
    let openAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("打开一本书开始阅读", systemImage: "books.vertical")
        } description: {
            Text("支持带文本层的 PDF，以及可重排阅读的 EPUB。")
        } actions: {
            Button("打开 PDF 或 EPUB", action: openAction)
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityIdentifier("reader.openDocument")
        }
    }
}

struct ReaderExplanationPanel: View {
    enum Presentation { case sidebar, popover }

    let selectedText: String
    let state: ReaderExplanationState
    let deepAnalysisState: ReaderDeepAnalysisState
    let save: () -> Void
    let retry: () -> Void
    let analyzeDeep: () -> Void
    let close: () -> Void
    let presentation: Presentation

    @State private var sourceExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("解句", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭解释")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    DisclosureGroup("选中的原文", isExpanded: $sourceExpanded) {
                        Text(selectedText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .font(.subheadline.weight(.semibold))

                    stateContent
                }
                .padding(18)
            }
        }
        .background(.background)
        .frame(
            minWidth: presentation == .popover ? 420 : nil,
            idealWidth: presentation == .popover ? 440 : nil,
            maxWidth: presentation == .popover ? 480 : .infinity,
            minHeight: presentation == .popover ? 280 : nil,
            idealHeight: presentation == .popover ? 480 : nil,
            maxHeight: presentation == .popover ? 600 : .infinity
        )
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在解释…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("重试", action: retry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded(let explanation):
            LazyVStack(alignment: .leading, spacing: 12) {
                explanationCard(title: "翻译", systemImage: "character.bubble", value: explanation.translation)
                explanationCard(title: "句子主干", systemImage: "arrow.triangle.branch", value: explanation.sentenceCore)
                if !explanation.grammarPoints.isEmpty {
                    itemCard(title: "语法", systemImage: "text.book.closed", items: explanation.grammarPoints)
                }
                if !explanation.keyPhrases.isEmpty {
                    itemCard(title: "重点表达", systemImage: "quote.bubble", items: explanation.keyPhrases)
                }
                deepAnalysisContent
                Button("保存到学习记录", systemImage: "bookmark", action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var deepAnalysisContent: some View {
        switch deepAnalysisState {
        case .idle:
            Button("深入解析句式与结构", systemImage: "point.3.connected.trianglepath.dotted", action: analyzeDeep)
                .buttonStyle(.bordered)
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在深入分析句式、成分和从句…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("重试深入解析", action: analyzeDeep)
            }
        case .loaded(let analysis):
            LazyVStack(alignment: .leading, spacing: 12) {
                explanationCard(title: "句子类型", systemImage: "text.line.first.and.arrowtriangle.forward", value: analysis.sentenceType)
                explanationCard(title: "句型结构", systemImage: "point.3.connected.trianglepath.dotted", value: analysis.sentencePattern)
                componentCard(analysis.components)
                if !analysis.clauses.isEmpty { clauseCard(analysis.clauses) }
                if !analysis.grammarPoints.isEmpty {
                    itemCard(title: "深度语法", systemImage: "books.vertical", items: analysis.grammarPoints)
                }
                explanationCard(title: "整句理解", systemImage: "lightbulb", value: analysis.interpretation)
            }
        }
    }

    private func componentCard(_ components: [ReaderSentenceComponent]) -> some View {
        DisclosureGroup("句子成分（\(components.count)）") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(component.text).font(.body.weight(.semibold)).textSelection(.enabled)
                        Text(component.role).font(.caption).foregroundStyle(.tint)
                        Text(component.explanation).fixedSize(horizontal: false, vertical: true)
                        if let modifies = component.modifies, !modifies.isEmpty {
                            Text("修饰：\(modifies)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func clauseCard(_ clauses: [ReaderClauseExplanation]) -> some View {
        DisclosureGroup("从句关系（\(clauses.count)）") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(clauses.enumerated()), id: \.offset) { _, clause in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clause.text).font(.body.weight(.semibold)).textSelection(.enabled)
                        Text("\(clause.type) · \(clause.function)").font(.caption).foregroundStyle(.tint)
                        Text(clause.explanation).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func explanationCard(title: String, systemImage: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func itemCard(title: String, systemImage: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.tertiary.opacity(0.35), in: Circle())
                    Text(item)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview { ReaderView() }
