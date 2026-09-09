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
    @Published private(set) var selectionKindOverride: ReaderSelectionKind?
    @Published private(set) var selectionTextOverride: String?
    @Published var explanationState: ReaderExplanationState = .idle
    @Published var wordExplanationState: ReaderWordExplanationState = .idle
    @Published var deepAnalysisState: ReaderDeepAnalysisState = .idle
    @Published private(set) var saveState: ReaderSaveState = .idle
    @Published var isExplanationPresented = false
    @Published private(set) var epubOpenAtEnd = false
    @Published private(set) var currentEPUBPageIndex = 0
    @Published private(set) var recentDocumentErrorMessage: String?

    /// 打开文档时希望 PDFView 定位到的页码；为 nil 表示从第一页开始。
    private(set) var restoredPageIndex: Int?
    private(set) var restoredEPUBPageIndex: Int?
    private(set) var restoredEPUBTextAnchor: EPUBTextAnchor?

    private var explanationProvider: any ReaderExplanationProviding
    private var vocabularyProvider: any ReaderVocabularyProviding
    private let saveHandler: @MainActor (ReaderSavePayload) async throws -> Void
    private let vocabularySaveHandler: @MainActor (ReaderVocabularySavePayload) async throws -> Void
    private let positionStore: ReadingPositionStore
    private let recentDocumentStore: RecentDocumentStore?
    private let fallbackSourceLanguage: String
    private var explanationLanguage: String
    private var explanationTask: Task<Void, Never>?
    private var vocabularyTask: Task<Void, Never>?
    private var deepAnalysisTask: Task<Void, Never>?
    private var documentLoadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var accessedSecurityScopedURL: URL?

    init(
        explanationProvider: any ReaderExplanationProviding = MockReaderExplanationProvider(),
        vocabularyProvider: any ReaderVocabularyProviding = MockReaderVocabularyProvider(),
        saveHandler: @escaping @MainActor (ReaderSavePayload) async throws -> Void = { _ in },
        vocabularySaveHandler: @escaping @MainActor (ReaderVocabularySavePayload) async throws -> Void = { _ in },
        positionStore: ReadingPositionStore = ReadingPositionStore(),
        recentDocumentStore: RecentDocumentStore? = nil,
        sourceLanguage: String = "English",
        explanationLanguage: String = "Chinese"
    ) {
        self.explanationProvider = explanationProvider
        self.vocabularyProvider = vocabularyProvider
        self.saveHandler = saveHandler
        self.vocabularySaveHandler = vocabularySaveHandler
        self.positionStore = positionStore
        self.recentDocumentStore = recentDocumentStore
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
        vocabularyProvider: any ReaderVocabularyProviding,
        explanationLanguage: String
    ) {
        explanationTask?.cancel()
        vocabularyTask?.cancel()
        deepAnalysisTask?.cancel()
        saveTask?.cancel()
        explanationProvider = provider
        self.vocabularyProvider = vocabularyProvider
        self.explanationLanguage = explanationLanguage
        if isExplanationPresented {
            isExplanationPresented = false
            explanationState = .idle
            wordExplanationState = .idle
            deepAnalysisState = .idle
            saveState = .idle
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

    func openRecentDocument(_ recentDocument: RecentDocument) {
        recentDocumentErrorMessage = nil
        guard let recentDocumentStore else { return }
        do {
            open(try recentDocumentStore.resolve(recentDocument))
        } catch {
            recentDocumentErrorMessage = error.localizedDescription
        }
    }

    func relocateRecentDocument(_ recentDocument: RecentDocument) {
        guard let recentDocumentStore else { return }
        let panel = NSOpenPanel()
        panel.title = "重新定位“\(recentDocument.displayName)”"
        panel.prompt = "选择"
        panel.allowedContentTypes = recentDocument.kind == .pdf
            ? [.pdf]
            : [UTType(filenameExtension: "epub") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try recentDocumentStore.relocate(recentDocument, to: url)
            recentDocumentErrorMessage = nil
            open(url)
        } catch {
            recentDocumentErrorMessage = error.localizedDescription
        }
    }

    func removeRecentDocument(_ recentDocument: RecentDocument) {
        recentDocumentStore?.remove(recentDocument)
        recentDocumentErrorMessage = nil
    }

    func open(_ url: URL) {
        open(url, sourceLocator: nil, legacyPageIndex: nil)
    }

    func openSource(_ source: ReaderSourceNavigation) {
        if let recentDocumentStore,
           let recent = recentDocumentStore.documents.first(where: {
            $0.fallbackPath == source.document.id
        }) {
            do {
                open(
                    try recentDocumentStore.resolve(recent),
                    sourceLocator: source.locator,
                    legacyPageIndex: source.legacyPageIndex
                )
            } catch {
                recentDocumentErrorMessage = error.localizedDescription
                fail(.fileUnavailable)
            }
            return
        }
        open(
            URL(fileURLWithPath: source.document.id),
            sourceLocator: source.locator,
            legacyPageIndex: source.legacyPageIndex
        )
    }

    private func open(
        _ url: URL,
        sourceLocator: DocumentLocator?,
        legacyPageIndex: Int?
    ) {
        documentLoadTask?.cancel()
        releaseDocumentAccess()
        if url.startAccessingSecurityScopedResource() {
            accessedSecurityScopedURL = url
        }
        recentDocumentErrorMessage = nil
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
        case "pdf": openPDF(url, sourceLocator: sourceLocator, legacyPageIndex: legacyPageIndex)
        case "epub": openEPUB(url, sourceLocator: sourceLocator, legacyPageIndex: legacyPageIndex)
        default: fail(.unsupportedFormat)
        }
    }

    private func openPDF(
        _ url: URL,
        sourceLocator: DocumentLocator?,
        legacyPageIndex: Int?
    ) {
        epubOpenAtEnd = false
        restoredEPUBPageIndex = nil
        restoredEPUBTextAnchor = nil
        currentEPUBPageIndex = 0
        guard let pdf = PDFDocument(url: url) else { fail(.invalidPDF); return }

        document = pdf
        epubDocument = nil
        selection = nil
        explanationState = .idle
        wordExplanationState = .idle
        deepAnalysisState = .idle
        saveState = .idle
        restoredPageIndex = nil
        let requestedPage = sourceLocator?.kind == .pdf
            ? sourceLocator?.pageIndex
            : legacyPageIndex
        if let requestedPage, requestedPage >= 0, requestedPage < pdf.pageCount {
            currentPageIndex = requestedPage
            restoredPageIndex = requestedPage
        } else if let saved = positionStore.position(for: url), saved > 0, saved < pdf.pageCount {
            currentPageIndex = saved
            restoredPageIndex = saved
        } else {
            currentPageIndex = 0
        }
        documentState = .loaded(.init(url: url, pageCount: pdf.pageCount, kind: .pdf))
        recordRecentDocument(url, kind: .pdf, locationLabel: pageLabel)
    }

    private func openEPUB(
        _ url: URL,
        sourceLocator: DocumentLocator?,
        legacyPageIndex: Int?
    ) {
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
                self.wordExplanationState = .idle
                self.deepAnalysisState = .idle
                self.saveState = .idle
                let savedPosition = self.positionStore.epubPosition(for: url)
                let requestedChapter = sourceLocator?.kind == .epub
                    ? sourceLocator?.chapterHref.flatMap { href in
                        epub.chapters.firstIndex { $0.resourcePath == href }
                    }
                    : nil
                let stableChapter = savedPosition.flatMap { position in
                    epub.chapters.firstIndex { chapter in
                        if let href = position.chapterHref, chapter.resourcePath == href { return true }
                        if let id = position.chapterID, chapter.id == id { return true }
                        return false
                    }
                }
                let savedChapter = requestedChapter
                    ?? (sourceLocator == nil ? stableChapter : nil)
                    ?? legacyPageIndex
                    ?? (sourceLocator == nil ? savedPosition?.chapterIndex : nil)
                    ?? (sourceLocator == nil ? self.positionStore.position(for: url) : nil)
                    ?? 0
                self.currentPageIndex = min(max(0, savedChapter), epub.chapters.count - 1)
                let requestedDisplayPage = sourceLocator?.kind == .epub
                    ? sourceLocator?.displayPageIndex
                    : nil
                self.currentEPUBPageIndex = max(
                    0,
                    requestedDisplayPage ?? (sourceLocator == nil ? savedPosition?.pageIndex : nil) ?? 0
                )
                self.restoredEPUBPageIndex = self.currentEPUBPageIndex
                self.restoredEPUBTextAnchor = sourceLocator?.kind == .epub
                    ? sourceLocator?.epubTextAnchor
                    : savedPosition?.textAnchor
                self.restoredPageIndex = nil
                self.epubOpenAtEnd = false
                self.documentState = .loaded(.init(url: url, pageCount: epub.chapters.count, kind: .epub))
                self.recordRecentDocument(url, kind: .epub, locationLabel: self.pageLabel)
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
        vocabularyTask?.cancel()
        deepAnalysisTask?.cancel()
        saveTask?.cancel()
        if case let .loaded(metadata) = documentState {
            positionStore.save(currentPageIndex, for: metadata.url)
        }
        document = nil
        epubDocument = nil
        selection = nil
        currentPageIndex = 0
        currentEPUBPageIndex = 0
        restoredPageIndex = nil
        restoredEPUBPageIndex = nil
        restoredEPUBTextAnchor = nil
        explanationState = .idle
        wordExplanationState = .idle
        deepAnalysisState = .idle
        saveState = .idle
        isExplanationPresented = false
        documentState = .empty
        releaseDocumentAccess()
    }

    func updateCurrentPage(_ index: Int) {
        let upperBound: Int
        if case let .loaded(metadata) = documentState { upperBound = max(0, metadata.pageCount - 1) }
        else { upperBound = Int.max }
        let clamped = min(max(0, index), upperBound)
        if clamped != currentPageIndex,
           case let .loaded(metadata) = documentState,
           metadata.kind == .epub {
            updateSelection(nil)
        }
        currentPageIndex = clamped
        if case let .loaded(metadata) = documentState {
            if metadata.kind == .epub {
                epubOpenAtEnd = false
                currentEPUBPageIndex = 0
                restoredEPUBPageIndex = nil
                restoredEPUBTextAnchor = nil
                saveCurrentEPUBPosition(pageIndex: 0, textAnchor: nil, for: metadata.url)
            } else {
                positionStore.save(clamped, for: metadata.url)
            }
            updateRecentLocation(for: metadata.url)
        }
    }

    func showPreviousChapter() {
        guard currentPageIndex > 0 else { return }
        updateSelection(nil)
        epubOpenAtEnd = true
        restoredEPUBPageIndex = nil
        restoredEPUBTextAnchor = nil
        currentEPUBPageIndex = 0
        currentPageIndex -= 1
        if case let .loaded(metadata) = documentState {
            saveCurrentEPUBPosition(pageIndex: 0, textAnchor: nil, for: metadata.url)
            updateRecentLocation(for: metadata.url)
        }
    }

    func showNextChapter() {
        guard case let .loaded(metadata) = documentState,
              currentPageIndex + 1 < metadata.pageCount else { return }
        updateSelection(nil)
        epubOpenAtEnd = false
        restoredEPUBPageIndex = nil
        restoredEPUBTextAnchor = nil
        currentEPUBPageIndex = 0
        currentPageIndex += 1
        saveCurrentEPUBPosition(pageIndex: 0, textAnchor: nil, for: metadata.url)
        updateRecentLocation(for: metadata.url)
    }

    func updateEPUBPage(_ page: Int, pageCount: Int, textAnchor: EPUBTextAnchor? = nil) {
        guard pageCount > 0, case let .loaded(metadata) = documentState, metadata.kind == .epub else { return }
        let clamped = min(max(0, page), pageCount - 1)
        currentEPUBPageIndex = clamped
        restoredEPUBPageIndex = clamped
        if let textAnchor { restoredEPUBTextAnchor = textAnchor }
        saveCurrentEPUBPosition(
            pageIndex: clamped,
            textAnchor: textAnchor ?? restoredEPUBTextAnchor,
            for: metadata.url
        )
        recentDocumentStore?.updateLocation(
            for: metadata.url,
            label: "第 \(currentPageIndex + 1) / \(metadata.pageCount) 章 · 本章 \(clamped + 1) / \(pageCount) 页"
        )
    }

    func updateSelection(_ selection: ReaderSelection?) {
        if self.selection != selection {
            saveTask?.cancel()
            explanationTask?.cancel()
            vocabularyTask?.cancel()
            deepAnalysisTask?.cancel()
            saveState = .idle
            selectionKindOverride = nil
            selectionTextOverride = nil
            explanationState = .idle
            wordExplanationState = .idle
            deepAnalysisState = .idle
            isExplanationPresented = false
        }
        self.selection = selection
        if selection == nil {
            isExplanationPresented = false
            explanationState = .idle
            wordExplanationState = .idle
            deepAnalysisState = .idle
        }
    }

    func requestExplanation(as kind: ReaderSelectionKind? = nil, targetText: String? = nil) {
        if let targetText { selectionTextOverride = targetText }
        else if kind != nil { selectionTextOverride = nil }
        if let kind { selectionKindOverride = kind }
        if selectionKind.canSaveSelectionAsVocabulary {
            requestWordExplanation()
            return
        }
        let sourceLanguage = detectedSourceLanguage
        guard let request = selection?.explanationRequest(
            targetText: effectiveSelectionText,
            sourceLanguage: sourceLanguage,
            explanationLanguage: explanationLanguage
        ) else { return }
        explanationTask?.cancel()
        vocabularyTask?.cancel()
        isExplanationPresented = true
        explanationState = .loading
        wordExplanationState = .idle
        deepAnalysisState = .idle
        saveState = .idle
        explanationTask = Task { [weak self, explanationProvider] in
            do {
                let stream = try await explanationProvider.explanationStream(request)
                var finalResult: ReaderExplanation?
                for try await update in stream {
                    try Task.checkCancellation()
                    finalResult = update
                    self?.explanationState = .streaming(update)
                }
                guard let finalResult else {
                    throw ReadingAIError.invalidResponse("解释服务没有返回内容")
                }
                self?.explanationState = .loaded(finalResult)
            } catch is CancellationError {
                return
            } catch {
                self?.explanationState = .failed(error.localizedDescription)
            }
        }
    }

    private func requestWordExplanation() {
        guard let selection else { return }
        let request = WordExplanationRequest(
            selectedText: effectiveSelectionText,
            sentenceContext: selection.containingSentence ?? selection.targetText,
            precedingContext: selection.precedingContext,
            followingContext: selection.followingContext,
            sourceLanguage: detectedSourceLanguage,
            explanationLanguage: explanationLanguage
        )
        explanationTask?.cancel()
        vocabularyTask?.cancel()
        deepAnalysisTask?.cancel()
        isExplanationPresented = true
        explanationState = .idle
        wordExplanationState = .loading
        deepAnalysisState = .idle
        saveState = .idle
        vocabularyTask = Task { [weak self, vocabularyProvider] in
            do {
                let stream = try await vocabularyProvider.wordExplanationStream(request)
                var finalResult: ReaderWordExplanation?
                for try await update in stream {
                    try Task.checkCancellation()
                    finalResult = update
                    self?.wordExplanationState = .streaming(update)
                }
                guard let finalResult else {
                    throw ReadingAIError.invalidResponse("词语解释服务没有返回内容")
                }
                self?.wordExplanationState = .loaded(finalResult)
            } catch is CancellationError {
                return
            } catch {
                self?.wordExplanationState = .failed(error.localizedDescription)
            }
        }
    }

    func requestDeepAnalysis() {
        let sourceLanguage = detectedSourceLanguage
        guard let request = selection?.explanationRequest(
            targetText: effectiveSelectionText,
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
        vocabularyTask?.cancel()
        deepAnalysisTask?.cancel()
        isExplanationPresented = false
        explanationState = .idle
        wordExplanationState = .idle
        deepAnalysisState = .idle
    }

    func saveExplanation() {
        guard
            case let .loaded(explanation) = explanationState,
            case let .loaded(metadata) = documentState,
            let selection
        else { return }
        let sourceLanguage = detectedSourceLanguage
        let payload = ReaderSavePayload(
            documentURL: metadata.url,
            pageIndex: selection.locator?.kind == .pdf
                ? selection.locator?.pageIndex ?? currentPageIndex
                : currentPageIndex,
            locator: selection.locator ?? currentDocumentLocator,
            selection: selection,
            explanation: explanation,
            sourceLanguage: sourceLanguage,
            explanationLanguage: explanationLanguage
        )
        saveTask?.cancel()
        saveState = .saving
        saveTask = Task { [weak self, saveHandler] in
            do {
                try await saveHandler(payload)
                try Task.checkCancellation()
                self?.saveState = .saved
            } catch is CancellationError {
                return
            } catch {
                self?.saveState = .failed(error.localizedDescription)
            }
        }
    }

    func saveVocabulary(_ candidate: ReaderVocabularyCandidate) async throws {
        guard case let .loaded(metadata) = documentState, let selection else { return }
        try await vocabularySaveHandler(.init(
            documentURL: metadata.url,
            pageIndex: currentPageIndex,
            locator: selection.locator ?? currentDocumentLocator,
            sentence: selection.containingSentence ?? selection.targetText,
            sourceLanguage: detectedSourceLanguage,
            explanationLanguage: explanationLanguage,
            candidate: candidate
        ))
    }

    private var detectedSourceLanguage: String {
        let contextSample = [
            selection?.precedingContext,
            selection?.targetText,
            selection?.followingContext
        ].compactMap { $0 }.joined(separator: " ")
        return TextLanguageDetector.languageName(for: contextSample, fallback: documentSourceLanguage)
    }

    var selectionKind: ReaderSelectionKind {
        if let selectionKindOverride { return selectionKindOverride }
        return ReaderSelectionClassifier.classify(
            effectiveSelectionText,
            sourceLanguage: detectedSourceLanguage
        )
    }

    var effectiveSelectionText: String {
        selectionTextOverride ?? selection?.targetText ?? ""
    }

    var selectionBoundarySuggestion: ReaderSelectionBoundarySuggestion? {
        guard selectionTextOverride == nil, let selection else { return nil }
        return ReaderSelectionBoundarySuggester.suggestion(
            for: selection.targetText,
            in: selection.containingSentence,
            sourceLanguage: detectedSourceLanguage
        )
    }

    private var documentSourceLanguage: String {
        guard let code = epubDocument?.metadata.language?.lowercased() else {
            return fallbackSourceLanguage
        }
        if code.hasPrefix("ja") { return "Japanese" }
        if code.hasPrefix("zh") { return "Chinese" }
        if code.hasPrefix("ko") { return "Korean" }
        if code.hasPrefix("fr") { return "French" }
        if code.hasPrefix("de") { return "German" }
        if code.hasPrefix("en") { return "English" }
        return fallbackSourceLanguage
    }

    private var currentDocumentLocator: DocumentLocator? {
        guard case let .loaded(metadata) = documentState else { return nil }
        if metadata.kind == .pdf {
            return .pdf(pageIndex: currentPageIndex)
        }
        guard let epubDocument,
              epubDocument.chapters.indices.contains(currentPageIndex) else { return nil }
        return .epub(
            chapterHref: epubDocument.chapters[currentPageIndex].resourcePath,
            textAnchor: restoredEPUBTextAnchor,
            displayPageIndex: currentEPUBPageIndex
        )
    }

    private func fail(_ error: ReaderDocumentError) {
        document = nil
        epubDocument = nil
        documentState = .failed(error)
        releaseDocumentAccess()
    }

    private func recordRecentDocument(
        _ url: URL,
        kind: RecentDocument.Kind,
        locationLabel: String?
    ) {
        do {
            try recentDocumentStore?.recordOpened(url, kind: kind, locationLabel: locationLabel)
        } catch {
            recentDocumentErrorMessage = "已打开文档，但无法加入最近阅读：\(error.localizedDescription)"
        }
    }

    private func updateRecentLocation(for url: URL) {
        guard let pageLabel else { return }
        recentDocumentStore?.updateLocation(for: url, label: pageLabel)
    }

    private func saveCurrentEPUBPosition(
        pageIndex: Int,
        textAnchor: EPUBTextAnchor?,
        for url: URL
    ) {
        guard let epubDocument,
              epubDocument.chapters.indices.contains(currentPageIndex) else { return }
        let chapter = epubDocument.chapters[currentPageIndex]
        positionStore.saveEPUB(.init(
            chapterIndex: currentPageIndex,
            pageIndex: pageIndex,
            chapterID: chapter.id,
            chapterHref: chapter.resourcePath,
            textAnchor: textAnchor
        ), for: url)
    }

    private func releaseDocumentAccess() {
        accessedSecurityScopedURL?.stopAccessingSecurityScopedResource()
        accessedSecurityScopedURL = nil
    }
}
