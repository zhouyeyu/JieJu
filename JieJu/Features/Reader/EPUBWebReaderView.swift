import SwiftUI
import WebKit
import JieJuLanguage

struct EPUBPagedReaderView: View {
    let document: EPUBDocument
    let chapterIndex: Int
    let initialPageIndex: Int?
    let initialTextAnchor: EPUBTextAnchor?
    let initialPageAtEnd: Bool
    let readingStyle: EPUBReadingStyle
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onPageChange: (Int, Int, EPUBTextAnchor?) -> Void
    let onSelectionChange: (ReaderSelection?) -> Void

    @State private var pageIndex = 0
    @State private var pageCount = 1
    @State private var command = EPUBPageCommand.none
    @State private var isPaginationReady = false

    private var chapter: EPUBChapter { document.chapters[chapterIndex] }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                EPUBWebReaderView(
                    document: document,
                    chapter: chapter,
                    initialPageIndex: initialPageIndex,
                    initialTextAnchor: initialTextAnchor,
                    initialPageAtEnd: initialPageAtEnd,
                    readingStyle: readingStyle,
                    command: command,
                    onPaginationChange: { page, count, textAnchor in
                        pageIndex = page
                        pageCount = max(1, count)
                        isPaginationReady = true
                        onPageChange(page, count, textAnchor)
                    },
                    onSelectionChange: onSelectionChange
                )
                .id(chapter.id)

                if !isPaginationReady {
                    readingStyle.theme.swiftUIColor
                        .ignoresSafeArea()
                    ProgressView("正在排版…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Divider()
            HStack(spacing: 14) {
                Button(action: previousPage) { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(pageIndex == 0 && chapterIndex == 0)
                    .accessibilityLabel("上一页")
                ProgressView(value: Double(pageIndex + 1), total: Double(pageCount))
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text(isPaginationReady
                     ? "第 \(chapterIndex + 1) / \(document.chapters.count) 章 · 本章 \(pageIndex + 1) / \(pageCount) 页"
                     : "第 \(chapterIndex + 1) / \(document.chapters.count) 章 · 正在排版…")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 180)
                Button(action: nextPage) { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(pageIndex + 1 >= pageCount && chapterIndex + 1 >= document.chapters.count)
                    .accessibilityLabel("下一页")
            }
            .buttonStyle(.plain)
            .padding(.vertical, 9)
        }
        .onChange(of: chapter.id, initial: true) {
            pageIndex = 0
            pageCount = 1
            command = .none
            isPaginationReady = false
        }
    }

    private func previousPage() {
        onSelectionChange(nil)
        if pageIndex > 0 { command = .previous(UUID()) }
        else { onPreviousChapter() }
    }

    private func nextPage() {
        onSelectionChange(nil)
        if pageIndex + 1 < pageCount { command = .next(UUID()) }
        else { onNextChapter() }
    }
}

private enum EPUBPageCommand: Equatable {
    case none
    case previous(UUID)
    case next(UUID)
}

private struct EPUBWebReaderView: NSViewRepresentable {
    let document: EPUBDocument
    let chapter: EPUBChapter
    let initialPageIndex: Int?
    let initialTextAnchor: EPUBTextAnchor?
    let initialPageAtEnd: Bool
    let readingStyle: EPUBReadingStyle
    let command: EPUBPageCommand
    let onPaginationChange: (Int, Int, EPUBTextAnchor?) -> Void
    let onSelectionChange: (ReaderSelection?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            EPUBSchemeHandler(
                resources: document.resources,
                readingStyle: readingStyle,
                documentLanguage: document.metadata.language
            ),
            forURLScheme: EPUBSchemeHandler.scheme
        )
        configuration.userContentController.add(context.coordinator, name: "pagination")
        configuration.userContentController.add(context.coordinator, name: "selection")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = readingStyle.theme.webBackgroundColor
        context.coordinator.webView = webView
        context.coordinator.load(chapter)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastCommand != command else { return }
        context.coordinator.lastCommand = command
        switch command {
        case .none: break
        case .previous: context.coordinator.turnPage(delta: -1)
        case .next: context.coordinator.turnPage(delta: 1)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "pagination")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "selection")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EPUBWebReaderView
        weak var webView: WKWebView?
        var lastCommand = EPUBPageCommand.none

        init(parent: EPUBWebReaderView) { self.parent = parent }

        func load(_ chapter: EPUBChapter) {
            let encodedPath = chapter.resourcePath
                .split(separator: "/")
                .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                .joined(separator: "/")
            let fragment: String
            if parent.initialPageAtEnd {
                fragment = "#jieju-end"
            } else if let anchor = parent.initialTextAnchor,
                      let data = try? JSONEncoder().encode(anchor) {
                let value = data.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
                fragment = "#jieju-location-\(value)"
            } else if let page = parent.initialPageIndex, page > 0 {
                fragment = "#jieju-page-\(page)"
            } else {
                fragment = ""
            }
            guard let url = URL(string: "\(EPUBSchemeHandler.scheme)://book/\(encodedPath)\(fragment)") else { return }
            webView?.load(URLRequest(url: url))
        }

        func turnPage(delta: Int) {
            webView?.evaluateJavaScript("window.JieJuReader.turnPage(\(delta));")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if message.name == "pagination" {
                receivePagination(body)
            } else if message.name == "selection" {
                receiveSelection(body)
            }
        }

        private func receivePagination(_ body: [String: Any]) {
            let page = body["page"] as? Int ?? 0
            let count = body["count"] as? Int ?? 1
            let anchor: EPUBTextAnchor?
            if let value = body["anchor"] as? [String: Any],
               let offset = value["textOffset"] as? Int {
                anchor = EPUBTextAnchor(
                    textOffset: offset,
                    textQuote: value["textQuote"] as? String ?? "",
                    progression: value["progression"] as? Double
                )
            } else {
                anchor = nil
            }
            parent.onPaginationChange(page, count, anchor)
        }

        private func receiveSelection(_ body: [String: Any]) {
            let text = ReaderTextProcessor.preparedSelection(body["text"] as? String ?? "")
            guard !text.isEmpty else { parent.onSelectionChange(nil); return }
            let surrounding = body["surrounding"] as? String ?? ""
            let context = ReaderTextProcessor.context(for: text, in: surrounding)
            let x = body["x"] as? Double ?? 60
            let y = body["y"] as? Double ?? 60
            let width = body["width"] as? Double ?? 1
            let height = body["height"] as? Double ?? 1
            let textAnchor: EPUBTextAnchor?
            if let value = body["textAnchor"] as? [String: Any],
               let offset = value["textOffset"] as? Int {
                textAnchor = EPUBTextAnchor(
                    textOffset: offset,
                    textQuote: value["textQuote"] as? String ?? "",
                    progression: value["progression"] as? Double
                )
            } else {
                textAnchor = nil
            }
            let locator = DocumentLocator.epub(
                chapterHref: parent.chapter.resourcePath,
                textAnchor: textAnchor,
                displayPageIndex: body["page"] as? Int
            )
            parent.onSelectionChange(ReaderSelection(
                targetText: text,
                containingSentence: context.current,
                precedingContext: context.preceding,
                followingContext: context.following,
                anchorRect: CGRect(x: x, y: y, width: width, height: height),
                locator: locator
            ))
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let scheme = navigationAction.request.url?.scheme else {
                decisionHandler(.cancel); return
            }
            decisionHandler(scheme == EPUBSchemeHandler.scheme ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak webView] in
                guard let self, let webView else { return }
                webView.evaluateJavaScript("window.JieJuReader && window.JieJuReader.forceLayout()") { result, _ in
                    guard let body = result as? [String: Any] else { return }
                    self.receivePagination(body)
                }
            }
        }
    }
}

final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "jieju-epub"
    private let resources: [String: EPUBResource]
    private let readingStyle: EPUBReadingStyle
    private let documentLanguage: String?
    private let japaneseReadingProvider: any JapaneseReadingProviding
    private let cacheLock = NSLock()
    private var injectedCache: [String: Data] = [:]

    init(
        resources: [String: EPUBResource],
        readingStyle: EPUBReadingStyle,
        documentLanguage: String? = nil,
        japaneseReadingProvider: any JapaneseReadingProviding = JapaneseReadingProviders.default
    ) {
        self.resources = resources
        self.readingStyle = readingStyle
        self.documentLanguage = documentLanguage
        self.japaneseReadingProvider = japaneseReadingProvider
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == Self.scheme,
              url.host == "book" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return
        }
        let path = String(url.path.drop(while: { $0 == "/" })).removingPercentEncoding ?? ""
        guard !path.isEmpty, !path.split(separator: "/").contains(".."),
              let resource = resources[path] else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let isHTML = resource.mediaType.contains("xhtml") || resource.mediaType.contains("html")
        let data = isHTML
            ? cachedInjectedXHTML(resource.data, path: path)
            : resource.data
        let response = URLResponse(
            url: url,
            mimeType: isHTML ? "text/html" : resource.mediaType,
            expectedContentLength: data.count,
            textEncodingName: resource.mediaType.contains("text") || isHTML ? "utf-8" : nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func cachedInjectedXHTML(_ data: Data, path: String) -> Data {
        if let cached = cacheLock.withLock({ injectedCache[path] }) { return cached }
        let injected = injectedXHTML(data)
        cacheLock.withLock { injectedCache[path] = injected }
        return injected
    }

    func injectedXHTML(_ data: Data) -> Data {
        guard var html = String(data: data, encoding: .utf8) else { return data }
        let shouldInjectFurigana = readingStyle.showsFurigana
            && EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
                documentLanguage: documentLanguage,
                xhtml: html
            )
        let furiganaScript = shouldInjectFurigana
            ? EPUBFuriganaInjection.script(for: html, provider: japaneseReadingProvider)
            : ""
        let rubyVisibility = readingStyle.showsFurigana ? "ruby-text" : "none"
        let injection = """
        <meta http-equiv="Content-Security-Policy" content="default-src jieju-epub: data:; connect-src 'none'; script-src 'unsafe-inline'; style-src jieju-epub: 'unsafe-inline'; img-src jieju-epub: data:; font-src jieju-epub: data:">
        <style id="jieju-reader-style">
        html { width: 100% !important; height: 100% !important; margin: 0 !important;
               padding: 0 !important; overflow: hidden !important;
               background: \(readingStyle.theme.backgroundCSS) !important; }
        body { box-sizing: border-box !important; width: 100vw !important; height: 100vh !important;
               min-width: 0 !important; max-width: none !important; min-height: 0 !important;
               max-height: none !important; margin: 0 !important;
               padding: 32px \(readingStyle.horizontalMargin)px 38px !important;
               overflow: visible !important;
               column-width: calc(100vw - \(readingStyle.horizontalMargin * 2)px) !important;
               column-gap: \(readingStyle.horizontalMargin * 2)px !important; column-fill: auto !important;
               font-size: \(readingStyle.fontSize)px !important; line-height: \(readingStyle.lineHeight) !important;
               color: \(readingStyle.theme.foregroundCSS) !important;
               background: \(readingStyle.theme.backgroundCSS) !important; }
        body * { color: \(readingStyle.theme.foregroundCSS) !important;
                 background-color: transparent !important; }
        body p, body li, body blockquote, body dd, body dt {
                 font-size: \(readingStyle.fontSize)px !important;
                 line-height: \(readingStyle.lineHeight) !important; }
        body a, body a * { color: \(readingStyle.theme.linkCSS) !important; }
        ::selection { background: color-mix(in srgb, \(readingStyle.theme.linkCSS) 35%, transparent) !important; }
        img, svg { max-width: 100%; max-height: 80vh; object-fit: contain; }
        ruby rt { display: \(rubyVisibility); font-size: 0.55em; user-select: none; -webkit-user-select: none; }
        ruby rt[data-jieju-reading]::before { content: attr(data-jieju-reading); }
        ruby rp { display: none; user-select: none; -webkit-user-select: none; }
        </style>
        <script>
        \(EPUBWebScript.script(horizontalMargin: readingStyle.horizontalMargin))
        window.addEventListener('load', () => JieJuReader.observeAndLayout());
        window.addEventListener('resize', () => JieJuReader.scheduleLayout());
        document.addEventListener('mouseup', () => setTimeout(() => JieJuReader.selection(), 0));
        document.addEventListener('DOMContentLoaded', () =>
          setTimeout(() => JieJuReader.makeReadingsPresentationOnly(), 0));
        \(furiganaScript)
        </script>
        """
        if let range = html.range(of: "</head>", options: .caseInsensitive) {
            html.insert(contentsOf: injection, at: range.lowerBound)
        } else {
            html = injection + html
        }
        return Data(html.utf8)
    }
}

private extension EPUBReaderTheme {
    var webBackgroundColor: NSColor {
        switch self {
        case .paper: NSColor(deviceRed: 250 / 255, green: 250 / 255, blue: 248 / 255, alpha: 1)
        case .night: NSColor(deviceRed: 22 / 255, green: 24 / 255, blue: 29 / 255, alpha: 1)
        case .sepia: NSColor(deviceRed: 244 / 255, green: 236 / 255, blue: 216 / 255, alpha: 1)
        case .sage: NSColor(deviceRed: 221 / 255, green: 232 / 255, blue: 213 / 255, alpha: 1)
        }
    }

    var swiftUIColor: Color { Color(nsColor: webBackgroundColor) }
}

enum EPUBWebScript {
    static func script(horizontalMargin: Double) -> String {
        """
        window.JieJuReader = {
          page: 0,
          layoutTimer: null,
          layoutAttempts: 0,
          committedPageCount: 1,
          pendingAnchor: null,
          locationAnchor: null,
          viewportWidth: function() {
            return Math.max(1, document.documentElement.clientWidth || window.innerWidth);
          },
          pageCount: function() {
            const width = this.viewportWidth();
            const extent = Math.max(document.body.scrollWidth, document.documentElement.scrollWidth);
            return Math.max(1, Math.ceil((extent - 1) / width));
          },
          scheduleLayout: function() {
            clearTimeout(this.layoutTimer);
            this.layoutTimer = setTimeout(() => this.layout(), 80);
          },
          readableTextNodes: function() {
            if (!document.body) return [];
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
              acceptNode(node) {
                const parent = node.parentElement;
                if (!parent || parent.closest('rt, rp, script, style, head, textarea')) {
                  return NodeFilter.FILTER_REJECT;
                }
                return NodeFilter.FILTER_ACCEPT;
              }
            });
            const nodes = [];
            while (walker.nextNode()) nodes.push(walker.currentNode);
            return nodes;
          },
          canonicalText: function(nodes) {
            return (nodes || this.readableTextNodes()).map(node => node.nodeValue || '').join('');
          },
          anchorForRange: function(range) {
            const nodes = this.readableTextNodes();
            const text = this.canonicalText(nodes);
            let consumed = 0;
            for (const node of nodes) {
              const length = (node.nodeValue || '').length;
              let localOffset = null;
              if (node === range.startContainer) {
                localOffset = Math.min(length, Math.max(0, range.startOffset));
              } else {
                try { if (range.intersectsNode(node)) localOffset = 0; } catch (_) {}
              }
              if (localOffset !== null) {
                const offset = consumed + localOffset;
                return {textOffset: offset, textQuote: text.slice(offset, offset + 80),
                  progression: offset / Math.max(1, text.length)};
              }
              consumed += length;
            }
            return null;
          },
          captureAnchor: function() {
            if (!this.didApplyInitialPage) return null;
            const fallback = (this.page + 0.5) / Math.max(1, this.committedPageCount);
            const width = this.viewportWidth();
            const nodes = this.readableTextNodes();
            const text = this.canonicalText(nodes);
            const pageAt = (node, offset) => {
              try {
                const length = (node.nodeValue || '').length;
                if (length === 0) return null;
                const range = document.createRange();
                const start = Math.min(Math.max(0, offset), length - 1);
                range.setStart(node, start);
                range.setEnd(node, Math.min(length, start + 1));
                const rect = Array.from(range.getClientRects()).find(value => value.width > 0 || value.height > 0);
                if (!rect) return null;
                return Math.max(0, Math.floor((rect.left + window.scrollX) / width));
              } catch (_) {
                return null;
              }
            };
            let consumed = 0;
            for (const node of nodes) {
              const length = (node.nodeValue || '').length;
              if (length === 0) continue;
              const firstPage = pageAt(node, 0);
              const lastPage = pageAt(node, length - 1);
              if (firstPage === null || lastPage === null || lastPage < this.page) {
                consumed += length;
                continue;
              }
              let low = 0;
              let high = length - 1;
              while (low < high) {
                const middle = Math.floor((low + high) / 2);
                const middlePage = pageAt(node, middle);
                if (middlePage !== null && middlePage >= this.page) high = middle;
                else low = middle + 1;
              }
              if (pageAt(node, low) === this.page) {
                const offset = consumed + low;
                return {textOffset: offset, textQuote: text.slice(offset, offset + 80), progression: fallback};
              }
              consumed += length;
            }
            return null;
          },
          initialAnchorFromHash: function() {
            const prefix = '#jieju-location-';
            if (!location.hash.startsWith(prefix)) return null;
            try {
              let encoded = location.hash.slice(prefix.length).replace(/-/g, '+').replace(/_/g, '/');
              while (encoded.length % 4) encoded += '=';
              const bytes = Uint8Array.from(atob(encoded), character => character.charCodeAt(0));
              return JSON.parse(new TextDecoder().decode(bytes));
            } catch (_) {
              return null;
            }
          },
          normalizedTextOffset: function(anchor, nodes, text) {
            if (!anchor || !Number.isFinite(anchor.textOffset)) return null;
            let offset = Math.min(text.length, Math.max(0, Math.floor(anchor.textOffset)));
            const quote = typeof anchor.textQuote === 'string' ? anchor.textQuote : '';
            if (!quote || text.slice(offset, offset + quote.length) === quote) return offset;
            let match = text.indexOf(quote);
            if (match < 0) return offset;
            let closest = match;
            while (match >= 0) {
              if (Math.abs(match - offset) < Math.abs(closest - offset)) closest = match;
              match = text.indexOf(quote, match + 1);
            }
            return closest;
          },
          pageForAnchor: function(anchor, count, width) {
            const nodes = this.readableTextNodes();
            const text = this.canonicalText(nodes);
            const offset = this.normalizedTextOffset(anchor, nodes, text);
            if (offset !== null) {
              try {
                let consumed = 0;
                let target = null;
                let localOffset = 0;
                for (const node of nodes) {
                  const length = (node.nodeValue || '').length;
                  if (consumed + length >= offset) {
                    target = node;
                    localOffset = Math.min(length, Math.max(0, offset - consumed));
                    break;
                  }
                  consumed += length;
                }
                if (!target) throw new Error('Text anchor is outside the chapter');
                const range = document.createRange();
                range.setStart(target, localOffset);
                range.collapse(true);
                const rect = range.getBoundingClientRect();
                const absoluteX = rect.left + window.scrollX;
                if (Number.isFinite(absoluteX) && absoluteX >= 0) {
                  return Math.min(count - 1, Math.max(0, Math.floor(absoluteX / width)));
                }
              } catch (_) {}
            }
            const fallback = anchor && Number.isFinite(anchor.progression) ? anchor.progression : 0;
            return Math.min(count - 1, Math.max(0, Math.floor(fallback * count)));
          },
          paginationResult: function(count, preservedAnchor) {
            const anchor = preservedAnchor || this.captureAnchor();
            if (anchor) this.locationAnchor = anchor;
            return {page: this.page, count: count, anchor: anchor};
          },
          commitLayout: function(count, width) {
            let preservedAnchor = this.pendingAnchor || this.locationAnchor;
            if (location.hash === '#jieju-end' && !this.didApplyInitialPage) {
              this.page = count - 1; this.didApplyInitialPage = true;
            } else if (location.hash.startsWith('#jieju-location-') && !this.didApplyInitialPage) {
              preservedAnchor = this.initialAnchorFromHash();
              this.page = this.pageForAnchor(preservedAnchor, count, width);
              this.didApplyInitialPage = true;
            } else if (location.hash.startsWith('#jieju-page-') && !this.didApplyInitialPage) {
              const restored = Number.parseInt(location.hash.slice('#jieju-page-'.length), 10);
              this.page = Number.isFinite(restored) ? Math.min(Math.max(0, restored), count - 1) : 0;
              this.didApplyInitialPage = true;
            } else if (!this.didApplyInitialPage) {
              this.page = 0; this.didApplyInitialPage = true;
            } else {
              this.page = this.pageForAnchor(preservedAnchor, count, width);
            }
            this.committedPageCount = count;
            this.pendingAnchor = null;
            window.scrollTo(this.page * width, 0);
            const result = this.paginationResult(count, preservedAnchor);
            webkit.messageHandlers.pagination.postMessage(result);
            return result;
          },
          forceLayout: function() {
            const width = this.viewportWidth();
            if (!document.body || width < 1) return {page: 0, count: 1};
            if (!this.pendingAnchor) this.pendingAnchor = this.locationAnchor || this.captureAnchor();
            document.body.style.width = width + 'px';
            document.body.style.height = window.innerHeight + 'px';
            document.body.style.columnWidth = Math.max(1, width - \(horizontalMargin * 2)) + 'px';
            return this.commitLayout(this.pageCount(), width);
          },
          observeAndLayout: function() {
            document.body.querySelectorAll('img, svg, video').forEach(element => {
              if (!element.complete) element.addEventListener('load', () => this.scheduleLayout(), {once: true});
            });
            if (document.fonts && document.fonts.ready) {
              document.fonts.ready.then(() => this.scheduleLayout());
            }
            this.layout();
          },
          layout: function() {
            const width = this.viewportWidth();
            if (width < 200 || window.innerHeight < 200 || !document.body) {
              this.scheduleLayout(); return;
            }
            if (!this.pendingAnchor) this.pendingAnchor = this.locationAnchor || this.captureAnchor();
            document.body.style.width = width + 'px';
            document.body.style.height = window.innerHeight + 'px';
            document.body.style.columnWidth = Math.max(1, width - \(horizontalMargin * 2)) + 'px';
            requestAnimationFrame(() => {
              const count = this.pageCount();
              const textLength = (document.body.innerText || '').trim().length;
              if (count === 1 && textLength > 1200 && this.layoutAttempts < 10) {
                this.layoutAttempts += 1;
                this.scheduleLayout();
                return;
              }
              this.layoutAttempts = 0;
              this.commitLayout(count, width);
            });
          },
          turnPage: function(delta) {
            const selection = window.getSelection();
            if (selection) selection.removeAllRanges();
            webkit.messageHandlers.selection.postMessage({text: ''});
            const width = this.viewportWidth();
            const count = this.pageCount();
            this.page = Math.max(0, Math.min(count - 1, this.page + delta));
            window.scrollTo({left: this.page * width, top: 0, behavior: 'auto'});
            webkit.messageHandlers.pagination.postMessage(this.paginationResult(count, null));
          },
          textWithoutReadings: function(source) {
            const clone = source.cloneNode(true);
            if (clone.querySelectorAll) clone.querySelectorAll('rt, rp').forEach(node => node.remove());
            return (clone.textContent || '').trim();
          },
          selection: function() {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
              webkit.messageHandlers.selection.postMessage({text: ''}); return;
            }
            const range = selection.getRangeAt(0);
            const text = this.textWithoutReadings(range.cloneContents());
            if (!text) { webkit.messageHandlers.selection.postMessage({text: ''}); return; }
            const rect = range.getBoundingClientRect();
            const surrounding = this.textWithoutReadings(document.body);
            webkit.messageHandlers.selection.postMessage({text: text, surrounding: surrounding,
              x: rect.x, y: rect.y, width: rect.width, height: rect.height,
              page: this.page, textAnchor: this.anchorForRange(range)});
          },
          makeReadingsPresentationOnly: function() {
            document.querySelectorAll('rt').forEach(rt => {
              if (!rt.hasAttribute('data-jieju-reading')) {
                rt.setAttribute('data-jieju-reading', rt.textContent || '');
                rt.textContent = '';
              }
              rt.setAttribute('aria-hidden', 'true');
            });
          }
        };
        """
    }
}

enum EPUBFuriganaPolicy {
    static func shouldAutomaticallyAnnotate(documentLanguage: String?, xhtml: String) -> Bool {
        let evidence = scriptEvidence(in: xhtml)
        if let chapterLanguage = rootLanguage(in: xhtml) {
            if isJapanese(chapterLanguage) { return true }
            if !isUnspecified(chapterLanguage) { return evidence.isStronglyJapanese }
        }
        if let documentLanguage = normalized(documentLanguage), !isUnspecified(documentLanguage) {
            if isJapanese(documentLanguage) { return true }
            return evidence.isStronglyJapanese
        }

        return evidence.isProbablyJapanese
    }

    private static func scriptEvidence(in xhtml: String) -> ScriptEvidence {
        let text = XHTMLExtractor.blocks(from: xhtml).joined()
        var kanaCount = 0
        var cjkCount = 0
        var latinCount = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D:
                kanaCount += 1
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                cjkCount += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latinCount += 1
            default:
                break
            }
        }
        return ScriptEvidence(kanaCount: kanaCount, cjkCount: cjkCount, latinCount: latinCount)
    }

    private struct ScriptEvidence {
        let kanaCount: Int
        let cjkCount: Int
        let latinCount: Int

        var isProbablyJapanese: Bool {
            kanaCount >= 2 && kanaShareAmongCJK >= 0.05
        }

        /// EPUB language tags are often inherited from a conversion template. Only a substantial
        /// Japanese passage may override an explicit non-Japanese tag.
        var isStronglyJapanese: Bool {
            kanaCount >= 12 && kanaShareAmongCJK >= 0.20 && kanaShareAmongLetters >= 0.15
        }

        private var kanaShareAmongCJK: Double {
            Double(kanaCount) / Double(max(1, kanaCount + cjkCount))
        }

        private var kanaShareAmongLetters: Double {
            Double(kanaCount) / Double(max(1, kanaCount + cjkCount + latinCount))
        }
    }

    private static func rootLanguage(in xhtml: String) -> String? {
        let pattern = #"<html\b[^>]*\b(?:xml:)?lang\s*=\s*[\"']([^\"']+)[\"']"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(
                in: xhtml,
                range: NSRange(xhtml.startIndex..., in: xhtml)
              ),
              let range = Range(match.range(at: 1), in: xhtml) else { return nil }
        return normalized(String(xhtml[range]))
    }

    private static func normalized(_ language: String?) -> String? {
        guard let language else { return nil }
        let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return value.isEmpty ? nil : value
    }

    private static func isJapanese(_ language: String) -> Bool {
        language == "ja" || language.hasPrefix("ja-") || language == "jpn"
    }

    private static func isUnspecified(_ language: String) -> Bool {
        ["und", "mul", "zxx"].contains(language)
    }
}

enum EPUBFuriganaInjection {
    struct Entry: Codable, Equatable {
        let surface: String
        let reading: String
    }

    static func entries(for xhtml: String, provider: any JapaneseReadingProviding = JapaneseReadingProviders.default) -> [Entry] {
        let text = XHTMLExtractor.blocks(from: xhtml).joined(separator: "\n")
        var readings: [String: Set<String>] = [:]
        for segment in provider.segments(for: text) {
            guard let reading = segment.reading, !segment.surface.isEmpty else { continue }
            readings[segment.surface, default: []].insert(reading)
        }
        return readings.compactMap { surface, values in
            guard values.count == 1, let reading = values.first else { return nil }
            return Entry(surface: surface, reading: reading)
        }.sorted {
            $0.surface.count == $1.surface.count ? $0.surface < $1.surface : $0.surface.count > $1.surface.count
        }
    }

    static func script(for xhtml: String, provider: any JapaneseReadingProviding = JapaneseReadingProviders.default) -> String {
        let entries = entries(for: xhtml, provider: provider)
        guard !entries.isEmpty, let data = try? JSONEncoder().encode(entries),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return """
        window.addEventListener('DOMContentLoaded', () => {
          const entries = \(json);
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode(node) {
              const parent = node.parentElement;
              if (!parent || parent.closest('ruby, rt, script, style, head, textarea')) return NodeFilter.FILTER_REJECT;
              return node.nodeValue.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
          });
          const nodes = [];
          while (walker.nextNode()) nodes.push(walker.currentNode);
          for (const node of nodes) {
            const text = node.nodeValue;
            const fragment = document.createDocumentFragment();
            let cursor = 0;
            while (cursor < text.length) {
              let selected = null, selectedIndex = -1;
              for (const entry of entries) {
                const index = text.indexOf(entry.surface, cursor);
                if (index < 0) continue;
                if (selectedIndex < 0 || index < selectedIndex ||
                    (index === selectedIndex && entry.surface.length > selected.surface.length)) {
                  selected = entry; selectedIndex = index;
                }
              }
              if (!selected) { fragment.append(document.createTextNode(text.slice(cursor))); break; }
              if (selectedIndex > cursor) fragment.append(document.createTextNode(text.slice(cursor, selectedIndex)));
              const ruby = document.createElement('ruby');
              ruby.append(document.createTextNode(selected.surface));
              const rt = document.createElement('rt'); rt.textContent = selected.reading; ruby.append(rt);
              fragment.append(ruby);
              cursor = selectedIndex + selected.surface.length;
            }
            node.replaceWith(fragment);
          }
        });
        """
    }
}
