# JieJu Architecture

## 技术基线

- 平台：macOS 14+
- UI：SwiftUI，必要时通过 `NSViewRepresentable` 包装 AppKit/PDFKit
- PDF：PDFKit
- 并发：Swift Concurrency
- 测试：XCTest 与 XCUITest
- 本地模型：首选 Ollama；后续可增加 MLX 或系统模型 Provider

当前产品仍以 macOS 为实现平台，但架构边界已经扩展为多平台准备状态。Windows 采用独立原生
外壳，跨平台共享契约和 Reader Web，不要求 SwiftUI 代码在 Windows 编译。完整路线见
`Docs/CROSS_PLATFORM.md`。

## 跨平台边界

```text
macOS SwiftUI ─┐
               ├─ Shared/Contracts/v1 ─ AI / Persistence
Windows WinUI ─┘           │
                    Shared/ReaderWeb
```

- `Shared/Contracts/v1`：解释请求、解释结果、深度分析、学习记录和 Reader Bridge 的版本化规范；
- `Shared/ReaderWeb`：未来由 WKWebView/WebView2 共同加载的 EPUB 排版、分页和选区层；
- `Apps/Windows`：Windows 原生外壳预留目录；
- 当前 `JieJu/`、`JieJu.xcodeproj`：继续作为稳定的 macOS 实现，暂不移动。

## 模块边界

```text
JieJuApp
  ├── Features
  │   ├── Library
  │   ├── Reader
  │   ├── Selection
  │   ├── Explanation
  │   ├── Vocabulary
  │   └── Review
  ├── Domain
  │   ├── Document
  │   ├── Highlight
  │   ├── Explanation
  │   ├── Vocabulary
  │   └── Review
  └── Infrastructure
      ├── PDFKit
      ├── Persistence
      └── AI Providers
```

功能层负责用户流程，Domain 保存稳定的数据结构和协议，Infrastructure 实现系统框架、磁盘和模型调用。

## AI 边界

界面只依赖协议，不直接依赖 Ollama：

```swift
protocol ReadingAI: Sendable {
    func explain(_ request: ExplanationRequest) async throws -> Explanation
}
```

计划中的实现：

- `MockReadingAI`：确定性结果，用于 Preview 和测试；
- `OllamaReadingAI`：本机 HTTP 接口；
- `OpenAICompatibleReadingAI`：可选扩展；
- Apple/MLX Provider：验证可用性后再决定。

模型输入只包含选中文本、前后有限上下文、文档元数据、目标语言和学习水平。输出使用可校验的结构化数据。

语言能力位于本地 Swift Package `Packages/JieJuLanguage`：library 提供领域类型、Mock、Ollama、Prompt、解析与批量评测，`JieJuAILab` executable 提供单句调试和 JSONL 批量评测。Reader、Persistence 与语言包可独立开发，App 通过协议适配器完成转换。

## 本地数据

学习记录和阅读进度写入 Application Support 下的版本化 `library.json`。存储使用 actor 隔离、原子替换和损坏文件备份。持久化 DTO 不直接依赖模型 Provider。

生词与复习采用三层关系：`VocabularyEntry` 保存可编辑词条，`VocabularySource` 保存它出现过的
文档和原句，`ReviewCard` 保存复习方向与调度状态。`ReviewLog` 只追加、不覆盖，确保调度算法升级
后可以重算。解句记录和生词通过 ID 关联而不互相拥有生命周期；v2 引入生词，v3 引入
`ReviewCard`/`ReviewLog`，旧版本目录均保持不可变。

## 测试策略

- 单元测试：句子切分、上下文截取、请求构造、响应解析、数据保存；
- 集成测试：使用 Stub HTTP 层验证 Provider，不依赖真实模型；
- UI 测试：打开测试文档、触发解释、保存学习条目；
- 手工验收：PDFKit 文本选择、弹层定位和真实模型质量。

所有自动测试必须可离线重复运行。

共享契约和 Reader Web Bridge 使用 Node 内置测试运行器，不引入 npm 运行时依赖；Swift 测试同时
检查编码字段和 v1 Schema，防止平台实现与共享契约静默漂移。

## 依赖规则

- 优先使用 Apple 系统框架；
- 新增第三方依赖前记录到 `DECISIONS.md`；
- 业务逻辑不得绑定单一模型、网络协议或持久化方案；
- 测试资源放在测试 Target 内，不读取用户真实文档。
