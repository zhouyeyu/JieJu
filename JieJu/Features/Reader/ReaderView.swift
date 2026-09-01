import SwiftUI

struct ReaderView: View {
    @StateObject private var model: ReaderViewModel

    init(
        explanationProvider: any ReaderExplanationProviding = MockReaderExplanationProvider(),
        saveHandler: @escaping @MainActor (ReaderSavePayload) -> Void = { _ in },
        explanationLanguage: String = "Chinese"
    ) {
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
    }

    @ViewBuilder
    private var content: some View {
        switch model.documentState {
        case .empty:
            ReaderEmptyView(openAction: model.choosePDF)
        case .loading:
            ProgressView("正在打开 PDF…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("无法打开 PDF", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("选择其他 PDF", action: model.choosePDF)
            }
        case .loaded:
            if let document = model.document {
                ZStack(alignment: .topLeading) {
                    PDFReaderView(
                        document: document,
                        initialPageIndex: model.restoredPageIndex,
                        onSelectionChange: model.updateSelection,
                        onPageChange: model.updateCurrentPage
                    )
                    explanationButton
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
                Button("关闭", action: model.closeDocument)
            } else {
                Text("JieJu Reader").font(.headline)
                Spacer()
                Button("打开 PDF", action: model.choosePDF)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    @ViewBuilder
    private var explanationButton: some View {
        if let selection = model.selection {
            Button("解释", systemImage: "text.bubble", action: model.requestExplanation)
                .buttonStyle(.borderedProminent)
                .position(
                    x: max(52, selection.anchorRect.midX),
                    y: max(22, selection.anchorRect.minY - 18)
                )
                .popover(isPresented: $model.isExplanationPresented, arrowEdge: .bottom) {
                    ReaderExplanationPopover(
                        selectedText: selection.targetText,
                        state: model.explanationState,
                        save: model.saveExplanation,
                        retry: model.requestExplanation,
                        close: model.dismissExplanation
                    )
                }
                .accessibilityIdentifier("reader.explain")
        }
    }
}

private struct ReaderEmptyView: View {
    let openAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("打开一份 PDF 开始阅读", systemImage: "doc.richtext")
        } description: {
            Text("第一版支持带可选择文本层的 PDF。")
        } actions: {
            Button("打开 PDF", action: openAction)
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityIdentifier("reader.openPDF")
        }
    }
}

private struct ReaderExplanationPopover: View {
    let selectedText: String
    let state: ReaderExplanationState
    let save: () -> Void
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("解句").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭解释")
            }
            Text(selectedText).font(.body).textSelection(.enabled)
            Divider()
            stateContent
        }
        .padding(18)
        .frame(width: 380)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在解释…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message).foregroundStyle(.red)
                Button("重试", action: retry)
            }
        case .loaded(let explanation):
            VStack(alignment: .leading, spacing: 12) {
                section("翻译", explanation.translation)
                section("句子主干", explanation.sentenceCore)
                if !explanation.grammarPoints.isEmpty {
                    section("语法", explanation.grammarPoints.joined(separator: "\n• "), bullet: true)
                }
                if !explanation.keyPhrases.isEmpty {
                    section("重点表达", explanation.keyPhrases.joined(separator: "\n• "), bullet: true)
                }
                Button("保存到学习记录", systemImage: "bookmark", action: save)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func section(_ title: String, _ value: String, bullet: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(bullet ? "• \(value)" : value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

#Preview { ReaderView() }
