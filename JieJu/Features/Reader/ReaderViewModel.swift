import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers
import JieJuLanguage

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var documentState: ReaderDocumentState = .empty
    @Published private(set) var document: PDFDocument?
    @Published private(set) var epubDocument: EPUBDocument?
    @Published private(set) var currentPageIndex = 0
    @Published var selection: ReaderSelection?
    @Published var explanationState: ReaderExplanationState = .idle
    @Published var deepAnalysisState: ReaderDeepAnalysisState = .idle
    @Published var isExplanationPresented = false
    @Published private(set) var epubOpenAtEnd = false

    /// 打开文档时希望 PDFView 定位到的页码；为 nil 表示从第一页开始。
    private(set) var restoredPageIndex: Int?

    private var explanationProvider: any ReaderExplanationProviding
    private let saveHandler: @MainActor (ReaderSavePayload) -> Void
    private let positionStore: ReadingPositionStore
    private let fallbackSourceLanguage: String
    private var explanationLanguage: String
    private var explanationTask: Task<Void, Never>?
    private var deepAnalysisTask: Task<Void, Never>?
    private var documentLoadTask: Task<Void, Never>?

    init(
        explanationProvider: any ReaderExplanationProviding = MockReaderExplanationProvider(),
        saveHandler: @escaping @MainActor (ReaderSavePayload) -> Void = { _ in },
        positionStore: ReadingPositionStore = ReadingPositionStore(),
        sourceLanguage: String = "English",
        explanationLanguage: String = "Chinese"
    ) {
        self.explanationProvider = explanationProvider
        self.saveHandler = saveHandler
        self.positionStore = positionStore
        self.fallbackSourceLanguage = sourceLanguage
        self.explanationLanguage = explanationLanguage
    }

    var pageLabel: String? {
        guard case let .loaded(metadata) = documentState, metadata.pageCount > 0 else { return nil }
        let position = "\(min(currentPageIndex + 1, metadata.pageCount)) / \(metadata.pageCount)"
        return metadata.kind == .epub ? "第 \(position) 章" : position
    }

    func updateExplanationConfiguration(
        provider: any ReaderExplanationProviding,
        explanationLanguage: String
    ) {
        explanationTask?.cancel()
        deepAnalysisTask?.cancel()
        explanationProvider = provider
        self.explanationLanguage = explanationLanguage
        if isExplanationPresented {
            isExplanationPresented = false
            explanationState = .idle
            deepAnalysisState = .idle
        }
    }

    func chooseDocument() {
        let panel = NSOpenPanel()
        panel.title = "打开 PDF 或 EPUB"
        panel.prompt = "打开"
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "epub") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        documentLoadTask?.cancel()
        documentState = .loading(url)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fail(.fileUnavailable)
            return
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            fail(.unreadableFile)
            return
        }
        switch url.pathExtension.lowercased() {
        case "pdf": openPDF(url)
        case "epub": openEPUB(url)
        default: fail(.unsupportedFormat)
        }
    }

    private func openPDF(_ url: URL) {
        epubOpenAtEnd = false
        guard let pdf = PDFDocument(url: url) else { fail(.invalidPDF); return }

        document = pdf
        epubDocument = nil
        selection = nil
        explanationState = .idle
        deepAnalysisState = .idle
        restoredPageIndex = nil
        if let saved = positionStore.position(for: url), saved > 0, saved < pdf.pageCount {
            currentPageIndex = saved
            restoredPageIndex = saved
        } else {
            currentPageIndex = 0
        }
        documentState = .loaded(.init(url: url, pageCount: pdf.pageCount, kind: .pdf))
    }

    private func openEPUB(_ url: URL) {
        documentLoadTask = Task { [weak self] in
            do {
                let epub = try await Task.detached(priority: .userInitiated) {
                    try EPUBCore.parse(url: url)
                }.value
                try Task.checkCancellation()
                guard let self, self.documentState == .loading(url) else { return }
                self.document = nil
                self.epubDocument = epub
                self.selection = nil
                self.explanationState = .idle
                self.deepAnalysisState = .idle
                let saved = self.positionStore.position(for: url) ?? 0
                self.currentPageIndex = min(max(0, saved), epub.chapters.count - 1)
                self.restoredPageIndex = nil
                self.epubOpenAtEnd = false
                self.documentState = .loaded(.init(url: url, pageCount: epub.chapters.count, kind: .epub))
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.documentState == .loading(url) else { return }
                self.fail(.invalidEPUB(error.localizedDescription))
            }
        }
    }

    func closeDocument() {
        documentLoadTask?.cancel()
        explanationTask?.cancel()
        deepAnalysisTask?.cancel()
        if case let .loaded(metadata) = documentState {
            positionStore.save(currentPageIndex, for: metadata.url)
        }
        document = nil
        epubDocument = nil
        selection = nil
        currentPageIndex = 0
        restoredPageIndex = nil
        explanationState = .idle
        deepAnalysisState = .idle
        isExplanationPresented = false
        documentState = .empty
    }

    func updateCurrentPage(_ index: Int) {
        let upperBound: Int
        if case let .loaded(metadata) = documentState { upperBound = max(0, metadata.pageCount - 1) }
        else { upperBound = Int.max }
        let clamped = min(max(0, index), upperBound)
        currentPageIndex = clamped
        if case let .loaded(metadata) = documentState {
            positionStore.save(clamped, for: metadata.url)
        }
    }

    func showPreviousChapter() {
        guard currentPageIndex > 0 else { return }
        epubOpenAtEnd = true
        updateCurrentPage(currentPageIndex - 1)
    }

    func showNextChapter() {
        guard case let .loaded(metadata) = documentState,
              currentPageIndex + 1 < metadata.pageCount else { return }
        epubOpenAtEnd = false
        updateCurrentPage(currentPageIndex + 1)
    }

    func updateSelection(_ selection: ReaderSelection?) {
        self.selection = selection
        if selection == nil {
            isExplanationPresented = false
            explanationState = .idle
            deepAnalysisState = .idle
        }
    }

    func requestExplanation() {
        let sourceLanguage = detectedSourceLanguage
        guard let request = selection?.explanationRequest(
            sourceLanguage: sourceLanguage,
            explanationLanguage: explanationLanguage
        ) else { return }
        explanationTask?.cancel()
        isExplanationPresented = true
        explanationState = .loading
        deepAnalysisState = .idle
        explanationTask = Task { [weak self, explanationProvider] in
            do {
                let result = try await explanationProvider.explain(request)
                try Task.checkCancellation()
                self?.explanationState = .loaded(result)
            } catch is CancellationError {
                return
            } catch {
                self?.explanationState = .failed(error.localizedDescription)
            }
        }
    }

    func requestDeepAnalysis() {
        let sourceLanguage = detectedSourceLanguage
        guard let request = selection?.explanationRequest(
            sourceLanguage: sourceLanguage,
            explanationLanguage: explanationLanguage
        ) else { return }
        deepAnalysisTask?.cancel()
        deepAnalysisState = .loading
        deepAnalysisTask = Task { [weak self, explanationProvider] in
            do {
                let result = try await explanationProvider.analyzeDeep(request)
                try Task.checkCancellation()
                self?.deepAnalysisState = .loaded(result)
            } catch is CancellationError {
                return
            } catch {
                self?.deepAnalysisState = .failed(error.localizedDescription)
            }
        }
    }

    func dismissExplanation() {
        explanationTask?.cancel()
        deepAnalysisTask?.cancel()
        isExplanationPresented = false
        explanationState = .idle
        deepAnalysisState = .idle
    }

    func saveExplanation() {
        guard
            case let .loaded(explanation) = explanationState,
            case let .loaded(metadata) = documentState,
            let selection
        else { return }
        let sourceLanguage = detectedSourceLanguage
        saveHandler(.init(
            documentURL: metadata.url,
            pageIndex: currentPageIndex,
            selection: selection,
            explanation: explanation,
            sourceLanguage: sourceLanguage,
            explanationLanguage: explanationLanguage
        ))
    }

    private var detectedSourceLanguage: String {
        TextLanguageDetector.languageName(for: selection?.targetText ?? "", fallback: fallbackSourceLanguage)
    }

    private func fail(_ error: ReaderDocumentError) {
        document = nil
        epubDocument = nil
        documentState = .failed(error)
    }
}
