# JieJu Architecture

## 技术基线

- 平台：macOS 14+
- UI：SwiftUI，必要时通过 `NSViewRepresentable` 包装 AppKit/PDFKit
- PDF：PDFKit
- 并发：Swift Concurrency
- 测试：XCTest 与 XCUITest
- 本地模型：首选 Ollama；后续可增加 MLX 或系统模型 Provider

## 模块边界

```text
JieJuApp
  ├── Features
  │   ├── Library
  │   ├── Reader
  │   ├── Selection
  │   ├── Explanation
  │   └── Review
  ├── Domain
  │   ├── Document
  │   ├── Highlight
  │   └── Explanation
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

## 测试策略

- 单元测试：句子切分、上下文截取、请求构造、响应解析、数据保存；
- 集成测试：使用 Stub HTTP 层验证 Provider，不依赖真实模型；
- UI 测试：打开测试文档、触发解释、保存学习条目；
- 手工验收：PDFKit 文本选择、弹层定位和真实模型质量。

所有自动测试必须可离线重复运行。

## 依赖规则

- 优先使用 Apple 系统框架；
- 新增第三方依赖前记录到 `DECISIONS.md`；
- 业务逻辑不得绑定单一模型、网络协议或持久化方案；
- 测试资源放在测试 Target 内，不读取用户真实文档。
