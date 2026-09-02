import SwiftUI
import WebKit
import JieJuLanguage

struct EPUBPagedReaderView: View {
    let document: EPUBDocument
    let chapterIndex: Int
    let initialPageAtEnd: Bool
    let readingStyle: EPUBReadingStyle
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onSelectionChange: (ReaderSelection?) -> Void

    @State private var pageIndex = 0
    @State private var pageCount = 1
    @State private var command = EPUBPageCommand.none

    private var chapter: EPUBChapter { document.chapters[chapterIndex] }

    var body: some View {
        VStack(spacing: 0) {
            EPUBWebReaderView(
                document: document,
                chapter: chapter,
                initialPageAtEnd: initialPageAtEnd,
                readingStyle: readingStyle,
                command: command,
                onPaginationChange: { page, count in
                    pageIndex = page
                    pageCount = max(1, count)
                },
                onSelectionChange: onSelectionChange
            )
            .id(chapter.id)

            Divider()
            HStack(spacing: 18) {
                Button(action: previousPage) { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(pageIndex == 0 && chapterIndex == 0)
                    .accessibilityLabel("上一页")
                Text("本章 \(pageIndex + 1) / \(pageCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 92)
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
        }
    }

    private func previousPage() {
        if pageIndex > 0 { command = .previous(UUID()) }
        else { onPreviousChapter() }
    }

    private func nextPage() {
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
    let initialPageAtEnd: Bool
    let readingStyle: EPUBReadingStyle
    let command: EPUBPageCommand
    let onPaginationChange: (Int, Int) -> Void
    let onSelectionChange: (ReaderSelection?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            EPUBSchemeHandler(resources: document.resources, readingStyle: readingStyle),
            forURLScheme: EPUBSchemeHandler.scheme
        )
        configuration.userContentController.add(context.coordinator, name: "pagination")
        configuration.userContentController.add(context.coordinator, name: "selection")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
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
            let fragment = parent.initialPageAtEnd ? "#jieju-end" : ""
            guard let url = URL(string: "\(EPUBSchemeHandler.scheme)://book/\(encodedPath)\(fragment)") else { return }
            webView?.load(URLRequest(url: url))
        }

        func turnPage(delta: Int) {
            webView?.evaluateJavaScript("window.JieJuReader.turnPage(\(delta));")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if message.name == "pagination" {
                let page = body["page"] as? Int ?? 0
                let count = body["count"] as? Int ?? 1
                parent.onPaginationChange(page, count)
            } else if message.name == "selection" {
                receiveSelection(body)
            }
        }

        private func receiveSelection(_ body: [String: Any]) {
            let text = ReaderTextProcessor.clean(body["text"] as? String ?? "")
            guard !text.isEmpty else { parent.onSelectionChange(nil); return }
            let surrounding = body["surrounding"] as? String ?? ""
            let context = ReaderTextProcessor.context(for: text, in: surrounding)
            let x = body["x"] as? Double ?? 60
            let y = body["y"] as? Double ?? 60
            let width = body["width"] as? Double ?? 1
            let height = body["height"] as? Double ?? 1
            parent.onSelectionChange(ReaderSelection(
                targetText: text,
                precedingContext: context.preceding,
                followingContext: context.following,
                anchorRect: CGRect(x: x, y: y, width: width, height: height)
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
    }
}

private final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "jieju-epub"
    private let resources: [String: EPUBResource]
    private let readingStyle: EPUBReadingStyle
    private let cacheLock = NSLock()
    private var injectedCache: [String: Data] = [:]

    init(resources: [String: EPUBResource], readingStyle: EPUBReadingStyle) {
        self.resources = resources
        self.readingStyle = readingStyle
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
        let data = resource.mediaType.contains("xhtml")
            ? cachedInjectedXHTML(resource.data, path: path)
            : resource.data
        let response = URLResponse(
            url: url,
            mimeType: resource.mediaType.contains("xhtml") ? "text/html" : resource.mediaType,
            expectedContentLength: data.count,
            textEncodingName: resource.mediaType.contains("text") || resource.mediaType.contains("xhtml") ? "utf-8" : nil
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

    private func injectedXHTML(_ data: Data) -> Data {
        guard var html = String(data: data, encoding: .utf8) else { return data }
        let furiganaScript = readingStyle.showsFurigana
            ? EPUBFuriganaInjection.script(for: html)
            : ""
        let rubyVisibility = readingStyle.showsFurigana ? "ruby-text" : "none"
        let injection = """
        <meta http-equiv="Content-Security-Policy" content="default-src jieju-epub: data:; connect-src 'none'; script-src 'unsafe-inline'; style-src jieju-epub: 'unsafe-inline'; img-src jieju-epub: data:; font-src jieju-epub: data:">
        <style id="jieju-reader-style">
        html { height: 100%; margin: 0; overflow: hidden; }
        body { box-sizing: border-box; padding: 36px \(readingStyle.horizontalMargin)px 42px;
               column-gap: \(readingStyle.horizontalMargin * 2)px;
               column-fill: auto; font-size: \(readingStyle.fontSize)px; line-height: \(readingStyle.lineHeight);
               margin: 0; overflow: visible;
               color: CanvasText; color-scheme: light dark; background: transparent; }
        img, svg { max-width: 100%; max-height: 80vh; object-fit: contain; }
        ruby rt { display: \(rubyVisibility); font-size: 0.55em; user-select: none; -webkit-user-select: none; }
        ruby rp { display: none; user-select: none; -webkit-user-select: none; }
        </style>
        <script>
        \(EPUBWebScript.script(horizontalMargin: readingStyle.horizontalMargin))
        window.addEventListener('load', () => setTimeout(() => JieJuReader.layout(), 0));
        window.addEventListener('resize', () => JieJuReader.layout());
        document.addEventListener('mouseup', () => setTimeout(() => JieJuReader.selection(), 0));
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

enum EPUBWebScript {
    static func script(horizontalMargin: Double) -> String {
        """
        window.JieJuReader = {
          page: 0,
          viewportWidth: function() {
            return Math.max(1, document.documentElement.clientWidth || window.innerWidth);
          },
          pageCount: function() {
            const width = this.viewportWidth();
            const extent = Math.max(document.body.scrollWidth, document.documentElement.scrollWidth);
            return Math.max(1, Math.ceil((extent - 1) / width));
          },
          layout: function() {
            const width = this.viewportWidth();
            document.body.style.width = width + 'px';
            document.body.style.height = window.innerHeight + 'px';
            document.body.style.columnWidth = Math.max(1, width - \(horizontalMargin * 2)) + 'px';
            requestAnimationFrame(() => {
              const count = this.pageCount();
              if (location.hash === '#jieju-end' && !this.didApplyInitialPage) {
                this.page = count - 1; this.didApplyInitialPage = true;
              } else { this.page = Math.min(this.page, count - 1); }
              window.scrollTo(this.page * width, 0);
              webkit.messageHandlers.pagination.postMessage({page: this.page, count: count});
            });
          },
          turnPage: function(delta) {
            const width = this.viewportWidth();
            const count = this.pageCount();
            this.page = Math.max(0, Math.min(count - 1, this.page + delta));
            window.scrollTo({left: this.page * width, top: 0, behavior: 'smooth'});
            webkit.messageHandlers.pagination.postMessage({page: this.page, count: count});
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
              x: rect.x, y: rect.y, width: rect.width, height: rect.height});
          }
        };
        """
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
