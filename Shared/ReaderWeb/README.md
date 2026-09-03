# JieJu Reader Web

这是 EPUB 阅读器中可跨 WKWebView（macOS）和 WebView2（Windows）共享的 Web 层骨架。
当前 macOS 阅读器仍使用 `EPUBWebReaderView.swift` 内的已验证脚本；后续按模块逐项迁入这里，
每迁一项都先补浏览器测试，再替换 Swift 内联版本，避免一次性重写造成阅读回归。

## 边界

- 本模块负责 HTML/CSS 排版、分页、文本选择、Ruby 显示和稳定阅读 locator。
- 原生外壳负责文件权限、窗口、设置、持久化、AI 调用和密钥。
- 双方只通过 `Shared/Contracts/v1/reader-bridge.schema.json` 定义的消息通信。
- Web 层不能直接调用 Ollama、云端模型、文件系统或任意外部网络。

## Host 通道

- macOS：`window.webkit.messageHandlers.jiejuBridge.postMessage(message)`
- Windows：`window.chrome.webview.postMessage(message)`
- 浏览器测试：注入 `{ postMessage(message) {} }`

运行无依赖测试：

```bash
npm test --prefix Shared/ReaderWeb
```
