import PDFKit
import SwiftUI

struct PDFReaderView: NSViewRepresentable {
    let document: PDFDocument
    var initialPageIndex: Int?
    let onSelectionChange: (ReaderSelection?) -> Void
    let onPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange, onPageChange: onPageChange)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        context.coordinator.attach(to: view)
        view.document = document
        goToInitialPageIfNeeded(in: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onPageChange = onPageChange
        if view.document !== document {
            view.document = document
            goToInitialPageIfNeeded(in: view)
        }
    }

    private func goToInitialPageIfNeeded(in view: PDFView) {
        guard let initialPageIndex, let page = document.page(at: initialPageIndex) else { return }
        view.go(to: page)
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.detach()
        view.document = nil
    }

    final class Coordinator: NSObject {
        var onSelectionChange: (ReaderSelection?) -> Void
        var onPageChange: (Int) -> Void
        private weak var pdfView: PDFView?
        private var observers: [NSObjectProtocol] = []

        init(
            onSelectionChange: @escaping (ReaderSelection?) -> Void,
            onPageChange: @escaping (Int) -> Void
        ) {
            self.onSelectionChange = onSelectionChange
            self.onPageChange = onPageChange
        }

        func attach(to view: PDFView) {
            pdfView = view
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in
                    self?.selectionDidChange()
                },
                center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                    self?.pageDidChange()
                }
            ]
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }

        private func selectionDidChange() {
            guard
                let view = pdfView,
                let document = view.document,
                let pdfSelection = view.currentSelection,
                let rawText = pdfSelection.string
            else {
                onSelectionChange(nil)
                return
            }

            let target = ReaderTextProcessor.clean(rawText)
            guard !target.isEmpty, let firstPage = pdfSelection.pages.first else {
                onSelectionChange(nil)
                return
            }

            let pageText = firstPage.string ?? ""
            let context = ReaderTextProcessor.context(for: rawText, in: pageText)
            let pageBounds = pdfSelection.bounds(for: firstPage)
            var anchor = view.convert(pageBounds, from: firstPage)
            anchor = anchor.intersection(view.visibleRect)
            if anchor.isNull || anchor.isEmpty {
                anchor = CGRect(x: view.visibleRect.midX, y: view.visibleRect.midY, width: 1, height: 1)
            }

            onSelectionChange(
                ReaderSelection(
                    targetText: target,
                    containingSentence: context.current,
                    precedingContext: context.preceding,
                    followingContext: context.following,
                    anchorRect: anchor,
                    locator: .pdf(pageIndex: document.index(for: firstPage))
                )
            )
        }

        private func pageDidChange() {
            guard let view = pdfView, let page = view.currentPage, let document = view.document else { return }
            onPageChange(document.index(for: page))
        }

        deinit { detach() }
    }
}
