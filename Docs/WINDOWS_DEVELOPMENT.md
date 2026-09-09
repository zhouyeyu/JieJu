# JieJu Windows 开发指南

## 当前状态

Windows 客户端尚未生成工程。当前可运行产品位于根目录的 macOS SwiftUI/Xcode 工程；Windows
版本采用独立的 WinUI 3 外壳，共享 JSON 契约和 EPUB Web 层，而不是移植 SwiftUI、AppKit 或
PDFKit。

Windows 第一阶段的目标是验证这条最小闭环：

```text
打开 EPUB → WebView2 排版与分页 → 选择句子 → Ollama 流式解句 → 保存 → 回到原文
```

PDF、OCR、同步、内嵌模型和完整 macOS 功能对齐均不阻塞第一阶段。

## 接手前必读

按顺序阅读：

1. `AGENTS.md`
2. `PRODUCT.md`
3. `ARCHITECTURE.md`
4. `TODO.md`
5. `PROGRESS.md`
6. `DECISIONS.md`
7. `HANDOFF.md`
8. `Docs/CROSS_PLATFORM.md`
9. `Shared/Contracts/README.md`
10. `Shared/ReaderWeb/README.md`

仓库文件和 Git 历史是多 Agent 协作的事实来源。开始修改前必须检查当前分支、最近提交和未提交
改动，不能依赖某个 Agent 的聊天记录。

## 开发环境

在 Windows 开发机安装：

- Git；
- 支持 Windows App SDK 与 WinUI 3 的 Visual Studio；
- 对应的 Windows SDK 和 .NET SDK；
- Microsoft Edge WebView2 Runtime；
- Node.js 20 或更高版本，用于共享契约与 Reader Web 测试；
- Ollama，以及首版默认模型 `qwen2.5:1.5b-instruct`。

创建工程时，把实际使用的 Visual Studio、Windows App SDK、Windows SDK 和 .NET 版本写入本文件，
不要在 macOS 上猜测并提交未经 Windows 构建验证的工程文件。

首次拉取后先运行平台无关测试：

```powershell
node --test Shared/Contracts/Tests/*.test.mjs Shared/ReaderWeb/Tests/*.test.mjs
```

PowerShell 对通配符的展开行为可能随环境不同；如果上述命令不可用，可分别执行：

```powershell
node --test Shared/Contracts/Tests/contracts.test.mjs
node --test Shared/ReaderWeb/Tests/bridge.test.mjs
```

本地模型准备：

```powershell
ollama pull qwen2.5:1.5b-instruct
ollama serve
```

## Solution 与依赖方向

在 Windows 真机中创建并验证以下结构：

```text
Apps/Windows/
├── JieJu.Windows/          WinUI 3 页面、WebView2 Host、文件选择和平台服务
├── JieJu.Domain/           C# DTO、Provider/Store 接口和平台无关业务规则
├── JieJu.Windows.Tests/    DTO、Provider、持久化与 Reader Host 测试
└── JieJu.Windows.sln
```

依赖只能朝向内部：

```text
JieJu.Windows → JieJu.Domain
Shared/ReaderWeb ↔ JSON Reader Bridge ↔ JieJu.Windows
JieJu.Domain DTO ← Shared/Contracts/v1…v5
```

`JieJu.Domain` 不引用 WinUI、WebView2、Ollama SDK 或 Windows Credential Manager。UI 不直接发送
HTTP，也不直接写 `library.json`。

## 跨平台事实来源

### JSON 契约

`Shared/Contracts` 是字段与版本语义的唯一事实来源：

- v1：句子解释、深度分析、基础学习资料和 Reader Bridge；
- v2：生词条目和来源；
- v3：复习卡片与只追加的复习日志；
- v4：独立的上下文单词解释请求/结果；
- v5：学习记录和生词来源的文档 locator。

C# 代码需要读取 v1～v5，新增资料写为 v5。已发布 Schema 不做破坏性修改；需要新字段时建立新
版本并补迁移、示例和跨平台测试。API Key、本机绝对路径、macOS bookmark 和 Windows 文件令牌
都不能进入共享数据。

### Reader Web

`Shared/ReaderWeb` 负责可以在 WKWebView 与 WebView2 共用的 EPUB 排版、分页、选区、Ruby 显示
和稳定正文 locator。原生外壳负责文件权限、窗口、AI、持久化和密钥。

当前共享层只有经过测试的 `jiejuBridge`；成熟的分页、选区和注音脚本仍位于 macOS
`JieJu/Features/Reader/EPUBWebReaderView.swift`。必须按 `XPLAT-101`～`XPLAT-105` 渐进迁移，
每次只移动一类行为并先补 Web 测试，不能一次复制或重写全部脚本。

WebView2 通过以下接口与原生 Host 通信：

```javascript
window.chrome.webview.postMessage(message)
```

所有消息都必须符合 `reader-bridge.schema.json`，携带 `contractVersion`、`type` 和 JSON payload。
Web 层不能直接访问 Ollama、任意外网或用户文件系统。

## 平台实现约定

- EPUB：使用 .NET ZIP/XML 能力解析 `container.xml`、OPF、manifest 和 spine；资源访问必须限制在
  当前 EPUB 内，阻止路径穿越与任意网络加载。
- AI：先实现协议后实现 Ollama Provider；支持 NDJSON 流式预览、取消、最终严格验证和一次结构
  修复。默认地址是 `http://127.0.0.1:11434`，但必须可配置。
- 数据：存放在 `%LOCALAPPDATA%\JieJu`，使用临时文件 + 原子替换；损坏文件要备份并给出明确错误。
- 密钥：将来启用云端 Provider 时使用 Windows Credential Manager，不写日志、设置 JSON、fixture
  或 Git。
- 最近文档：属于 Windows 设备本地状态，不写入共享 `library.json`；共享记录通过文档身份和稳定
  locator 返回原文。
- EPUB 位置：优先使用 manifest 资源路径和规范正文锚点；动态分页随窗口和字体变化，只能作为
  显示及回退信息。
- 日语：原书 Ruby 与自动注音均受用户开关控制，`rt`/`rp` 不可选择且不能进入 AI 上下文。Windows
  首版可以先保留原书 Ruby；自动 MeCab 注音作为独立里程碑实现。

## 实施顺序

### WIN-001：可构建骨架

- 创建 WinUI 3 Solution 和三个项目；
- 显示最小窗口并承载空 WebView2；
- 建立 `IReadingAI`、`IVocabularyAI`、`ILearningLibraryStore` 接口；
- 为 v1～v5 建立必要 C# DTO 和 JSON 往返测试；
- 增加一个 Windows 测试脚本或明确的 `dotnet test` 命令；
- 在 Windows 真机完成 build 与 test，再提交工程文件。

### XPLAT-101～105：共享 Reader

- 先让 macOS 使用统一 `jiejuBridge`，同时保留旧 handler；
- 迁移主题和排版 CSS；
- 迁移分页状态机；
- 迁移选区、上下文清洗和 Ruby 排除；
- 迁移正文锚点，并评估 EPUB CFI 互操作。

### WIN-002：Windows EPUB 闭环

- 打开和解析 EPUB；
- WebView2 安全加载章节资源；
- 逐页翻页、翻章和位置恢复；
- 选区产生结构化 `selectionChanged`；
- Ollama 流式翻译与语法讲解；
- 保存 v5 学习记录，并从记录返回原文。

完成后再拆分生词本、复习、PDF.js 和云端 Provider，避免首个客户端工程同时承受过多变量。

## 测试与完成定义

Windows 提交至少满足：

- `dotnet build` 成功；
- `dotnet test` 成功；
- Node 共享契约与 Bridge 测试成功；
- Provider 测试使用 Stub HTTP，不依赖正在运行的 Ollama；
- fixture 只包含自编或可公开再分发的最小 EPUB；
- 没有密钥、私人书籍、个人绝对路径或构建产物；
- `TODO.md`、`PROGRESS.md` 和 `HANDOFF.md` 已更新。

真实 Ollama 与 WebView2 UI 验收作为独立结果记录，不能代替离线自动测试。

## Windows Agent 起始 Prompt

```text
你正在 Windows 真机上接手 JieJu。先完整阅读 AGENTS.md、PRODUCT.md、ARCHITECTURE.md、
TODO.md、PROGRESS.md、DECISIONS.md、HANDOFF.md、Docs/CROSS_PLATFORM.md、
Docs/WINDOWS_DEVELOPMENT.md、Shared/Contracts/README.md 和 Shared/ReaderWeb/README.md。

当前只执行 WIN-001：在 Apps/Windows 创建并实际验证 WinUI 3 + WebView2 Solution，包含
JieJu.Windows、JieJu.Domain 和 JieJu.Windows.Tests。记录实际 SDK 版本；建立严格的项目依赖方向、
v1～v5 JSON DTO 往返测试和 dotnet build/test 入口。不要实现 PDF，不要重写 macOS Reader，
不要改写已发布 Schema，也不要把 API Key、绝对路径或平台文件令牌放进共享数据。

完成前运行 Windows build/test 和 Node 共享测试，更新 TODO.md、PROGRESS.md、HANDOFF.md，
创建一个边界清晰的 Conventional Commit，并报告仍未实现的 WIN-002 工作。
```
