import AppKit
import SwiftUI

struct EPUBReaderView: NSViewRepresentable {
    let chapter: EPUBChapter
    let onSelectionChange: (ReaderSelection?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 42, height: 36)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        context.coordinator.render(chapter)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.chapterID != chapter.id else { return }
        context.coordinator.render(chapter)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EPUBReaderView
        weak var textView: NSTextView?
        var chapterID: String?

        init(parent: EPUBReaderView) { self.parent = parent }

        func render(_ chapter: EPUBChapter) {
            chapterID = chapter.id
            guard let textView else { return }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 7
            style.paragraphSpacing = 14
            let body = chapter.textBlocks.joined(separator: "\n\n")
            textView.textStorage?.setAttributedString(NSAttributedString(
                string: body,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 18),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: style
                ]
            ))
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            parent.onSelectionChange(nil)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, textView.selectedRange().length > 0 else {
                parent.onSelectionChange(nil)
                return
            }
            let range = textView.selectedRange()
            guard let swiftRange = Range(range, in: textView.string) else { return }
            let selected = ReaderTextProcessor.clean(String(textView.string[swiftRange]))
            guard !selected.isEmpty else { parent.onSelectionChange(nil); return }
            let context = ReaderTextProcessor.context(for: selected, in: textView.string)
            let anchor = selectionRect(range, in: textView)
            parent.onSelectionChange(ReaderSelection(
                targetText: selected,
                precedingContext: context.preceding,
                followingContext: context.following,
                anchorRect: anchor
            ))
        }

        private func selectionRect(_ range: NSRange, in textView: NSTextView) -> CGRect {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return .zero }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            return rect
        }
    }
}
