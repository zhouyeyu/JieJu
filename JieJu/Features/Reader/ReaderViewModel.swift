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

    private let explanationProvider: any ReaderExplanationProviding
    private let saveHandler: @MainActor (ReaderSavePayload) -> Void
    private var explanationTask: Task<Void, Never>?

    init(
        explanationProvider: any ReaderExplanationProviding = MockReaderExplanationProvider(),
        saveHandler: @escaping @MainActor (ReaderSavePayload) -> Void = { _ in }
    ) {
        self.explanationProvider = explanationProvider
        self.saveHandler = saveHandler
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
        currentPageIndex = 0
        selection = nil
        explanationState = .idle
        documentState = .loaded(.init(url: url, pageCount: pdf.pageCount))
    }

    func closeDocument() {
        explanationTask?.cancel()
        document = nil
        selection = nil
        currentPageIndex = 0
        explanationState = .idle
        isExplanationPresented = false
        documentState = .empty
    }

    func updateCurrentPage(_ index: Int) {
        currentPageIndex = max(0, index)
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
