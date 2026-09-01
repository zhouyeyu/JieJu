import AppKit
import Foundation
import PDFKit

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var documentState: ReaderDocumentState = .empty
    @Published private(set) var document: PDFDocument?
    @Published private(set) var currentPageIndex = 0
    @Published var selection: ReaderSelection?
    @Published var explanationState: ReaderExplanationState = .idle
    @Published var isExplanationPresented = false

    /// 打开文档时希望 PDFView 定位到的页码；为 nil 表示从第一页开始。
    private(set) var restoredPageIndex: Int?

    private let explanationProvider: any ReaderExplanationProviding
    private let saveHandler: @MainActor (ReaderSavePayload) -> Void
    private let positionStore: ReadingPositionStore
    private var explanationTask: Task<Void, Never>?

    init(
        explanationProvider: any ReaderExplanationProviding = MockReaderExplanationProvider(),
        saveHandler: @escaping @MainActor (ReaderSavePayload) -> Void = { _ in },
        positionStore: ReadingPositionStore = ReadingPositionStore()
    ) {
        self.explanationProvider = explanationProvider
        self.saveHandler = saveHandler
        self.positionStore = positionStore
    }

    var pageLabel: String? {
        guard case let .loaded(metadata) = documentState, metadata.pageCount > 0 else { return nil }
        return "\(min(currentPageIndex + 1, metadata.pageCount)) / \(metadata.pageCount)"
    }

    func choosePDF() {
        let panel = NSOpenPanel()
        panel.title = "打开 PDF"
        panel.prompt = "打开"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        documentState = .loading(url)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fail(.fileUnavailable)
            return
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            fail(.unreadableFile)
            return
        }
        guard let pdf = PDFDocument(url: url) else {
            fail(.invalidPDF)
            return
        }

        document = pdf
        selection = nil
        explanationState = .idle
        restoredPageIndex = nil
        if let saved = positionStore.position(for: url), saved > 0, saved < pdf.pageCount {
            currentPageIndex = saved
            restoredPageIndex = saved
        } else {
            currentPageIndex = 0
        }
        documentState = .loaded(.init(url: url, pageCount: pdf.pageCount))
    }

    func closeDocument() {
        explanationTask?.cancel()
        if case let .loaded(metadata) = documentState {
            positionStore.save(currentPageIndex, for: metadata.url)
        }
        document = nil
        selection = nil
        currentPageIndex = 0
        restoredPageIndex = nil
        explanationState = .idle
        isExplanationPresented = false
        documentState = .empty
    }

    func updateCurrentPage(_ index: Int) {
        let clamped = max(0, index)
        currentPageIndex = clamped
        if case let .loaded(metadata) = documentState {
            positionStore.save(clamped, for: metadata.url)
        }
    }

    func updateSelection(_ selection: ReaderSelection?) {
        self.selection = selection
        if selection == nil {
            isExplanationPresented = false
            explanationState = .idle
        }
    }

    func requestExplanation() {
        guard let request = selection?.explanationRequest() else { return }
        explanationTask?.cancel()
        isExplanationPresented = true
        explanationState = .loading
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

    func dismissExplanation() {
        explanationTask?.cancel()
        isExplanationPresented = false
        explanationState = .idle
    }

    func saveExplanation() {
        guard
            case let .loaded(explanation) = explanationState,
            case let .loaded(metadata) = documentState,
            let selection
        else { return }
        saveHandler(.init(documentURL: metadata.url, pageIndex: currentPageIndex, selection: selection, explanation: explanation))
    }

    private func fail(_ error: ReaderDocumentError) {
        document = nil
        documentState = .failed(error)
    }
}
