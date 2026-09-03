# JieJu Cross-platform Roadmap

## 目标

在不重写当前 macOS 产品的前提下，为 Windows 和未来平台建立稳定边界。平台可以拥有不同 UI 和
系统集成，但阅读消息、AI 数据、学习记录和评测语义必须一致。

## 目标架构

```text
Apps/macOS (SwiftUI)               Apps/Windows (WinUI 3)
        │                                   │
        ├── Platform Reader Host ───────────┤
        │           │                       │
        │     Shared/ReaderWeb              │
        │           │                       │
        └──── Shared/Contracts/v1 ──────────┘
                    │
        Ollama / OpenAI Compatible / future llama.cpp
```

## 当前迁移原则

1. 当前根目录下的 `JieJu/` 和 Xcode 工程就是 macOS App；Windows 原型稳定前不做目录搬迁。
2. `Shared/Contracts/v1` 是跨语言规范，Swift 类型仍是 macOS 实现，不再是唯一事实来源。
3. `Shared/ReaderWeb` 是渐进迁移目标，不一次性替换已稳定的 EPUB 脚本。
4. Windows 首版只实现 EPUB 垂直链路；PDF、同步和内嵌模型在其后。
5. 平台密钥各自进入系统安全存储，禁止加入共享数据。

## Reader Web 迁移顺序

- `XPLAT-101`：统一原生消息通道并保持旧 selection/pagination handler 兼容。
- `XPLAT-102`：迁移主题和排版配置。
- `XPLAT-103`：迁移分页状态机与浏览器测试。
- `XPLAT-104`：迁移选区、上下文清洗和 Ruby 排除。
- `XPLAT-105`：实现 EPUB CFI 或文本锚点 locator，替换动态页码持久化。

每一步都要求 macOS 固定 EPUB 回归通过，不能以跨平台为由降低当前阅读体验。

## Windows 最小闭环

1. Windows 机器创建 WinUI 3 Solution，并配置 WebView2。
2. C# DTO 对应 `Shared/Contracts/v1`，添加 JSON 往返测试。
3. WebView2 加载 `Shared/ReaderWeb`，完成 host bridge。
4. 打开 EPUB，分页并产生 `selectionChanged`。
5. 通过同一 AI 契约连接 Ollama。
6. 保存并重新加载 `learning-library` v1。

## 暂不决定

- 不立即把 Swift 语言引擎重写为 Rust。
- 不立即把 macOS PDFKit 替换为 PDF.js。
- 不生成未经 Windows SDK 实际构建验证的 WinUI 工程文件。
- 不把动态显示页码当作跨设备稳定位置。
