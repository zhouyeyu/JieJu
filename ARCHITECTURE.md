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
               ├─ Shared/Contracts/v1…v5 ─ AI / Persistence
Windows WinUI ─┘           │
                    Shared/ReaderWeb
```

- `Shared/Contracts/v1…v5`：解释请求、解释结果、深度分析、学习资料、复习、上下文单词解释及
  来源定位的
  版本化规范；
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

protocol VocabularyAI: Sendable {
    func explainWord(_ request: WordExplanationRequest) async throws -> WordExplanation
}
```

句子/段落解释与词语解释是两个独立能力：前者输出翻译和语法结构，后者只解释明确选中的词语或
表达。两者复用 HTTP Client 和 Provider 配置，但不共享 Prompt 或结果 DTO。日语词语的读音、原形、
词性和活用由本地 MeCab/IPADic 覆盖模型结果；模型负责语境义、简明义与搭配。两类接口均可选
流式扩展，切换选区或关闭解释时必须向下取消传输。

计划中的实现：

- `MockReadingAI`：确定性结果，用于 Preview 和测试；
- `OllamaReadingAI`：本机 HTTP 接口；
- `OpenAICompatibleReadingAI`：可选扩展；
- Apple/MLX Provider：验证可用性后再决定。

模型输入只包含选中文本、前后有限上下文、文档元数据、目标语言和学习水平。输出使用可校验的结构化数据。

语言能力位于本地 Swift Package `Packages/JieJuLanguage`：library 提供领域类型、Mock、Ollama、Prompt、解析与批量评测，`JieJuAILab` executable 提供单句调试和 JSONL 批量评测。Reader、Persistence 与语言包可独立开发，App 通过协议适配器完成转换。

## 本地数据

学习记录和阅读进度写入 Application Support 下的版本化 `library.json`。存储使用 actor 隔离、原子替换和损坏文件备份。持久化 DTO 不直接依赖模型 Provider。

最近文档属于设备本地的阅读入口状态，独立保存在 `UserDefaults` 的 `recentDocuments.v1`。每条记录
包含显示名称、文档类型、最后位置、打开时间、回退路径和 macOS security-scoped bookmark；最多
保留 12 条并按规范化路径去重。打开最近文档时先解析书签，再由 `ReaderViewModel` 在整个阅读会话
持有安全访问权限；关闭或打开其他文档时释放。失效书签不会删除阅读记录，而是要求用户重新定位。

这份最近列表不替代 `library.json` 中的跨平台学习数据，也不作为未来 Windows 的共享格式。后续文档
身份应通过内容指纹与稳定锚点升级，避免把平台书签或绝对路径写入共享 locator。

`library.json` v5 为解句记录和每条生词来源保存可选 `DocumentLocator`。PDF 使用零基页索引；EPUB
使用 manifest 资源路径、规范正文锚点和仅作回退的动态页码。学习记录、生词本与温习页只发布
导航意图，由 Reader 解析设备本地书签并打开文档；旧记录没有 locator 时继续使用原 `pageIndex`。
文档移动后的自动关联仍依赖后续内容指纹，不把 macOS bookmark 写入跨平台学习资料。

EPUB 的本地阅读位置保存章节 ID、manifest 资源路径、动态页码和 `EPUBTextAnchor`。文本锚点使用
不含 Ruby 注音与脚本/样式节点的规范正文 UTF-16 偏移，并携带短引用与章内比例用于修复和回退。
恢复顺序为资源路径、章节 ID、旧章节索引；动态页码不是稳定身份。后续迁入 `Shared/ReaderWeb` 时
保持这一语义，并评估用 EPUB CFI 补充跨阅读器互操作。

EPUB 自动假名注入由 `EPUBFuriganaPolicy` 在调用 MeCab 前门控：章节根语言优先于整书元数据；
明确非日语时不生成自动 Ruby；缺失语言时仅以足量假名作为保守回退。原书已有 Ruby 的显示仍由
阅读设置控制。语言判断与注入分离，便于未来迁入共享 Reader Web 或改成段落级语言识别。

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
检查编码字段和对应版本 Schema，防止平台实现与共享契约静默漂移。v4 固定上下文单词解释交换
结构；v5 为学习记录和生词来源增加可选 Reader locator。

## 依赖规则

- 优先使用 Apple 系统框架；
- 新增第三方依赖前记录到 `DECISIONS.md`；
- 业务逻辑不得绑定单一模型、网络协议或持久化方案；
- 测试资源放在测试 Target 内，不读取用户真实文档。
