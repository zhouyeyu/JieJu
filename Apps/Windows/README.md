# JieJu Windows

Windows 版本已完成 `WIN-001` 及 `WIN-101`～`WIN-105` 阅读界面。本目录是 Windows 原生外壳的唯一入口；继续开发前请完整阅读
[`Docs/WINDOWS_DEVELOPMENT.md`](../../Docs/WINDOWS_DEVELOPMENT.md) 和
[`Docs/CROSS_PLATFORM.md`](../../Docs/CROSS_PLATFORM.md)。

## 当前开发环境

- Windows 11 `10.0.26100`（x64）
- .NET SDK `10.0.401` / MSBuild `18.9.11`
- Windows App SDK WinUI `1.8.260803003`
- Windows SDK Build Tools `10.0.26100.9169`
- Microsoft Edge WebView2 Runtime `152.0.4191.66`
- Visual Studio 未参与本次构建；工程通过 `dotnet` CLI 在 Windows 真机完成构建、测试和启动验证

安装对应 .NET SDK 后，在仓库根目录运行 `.\scripts\build-windows.ps1`，Release 程序会输出到
`artifacts\windows\win-x64\JieJu`。运行 `.\scripts\package-windows.ps1 -Version 0.1.0-alpha`
可生成带当前用户安装/卸载脚本、第三方归属摘要与 SHA-256 的 Alpha ZIP；解压后可直接运行，或
执行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1` 安装并创建开始菜单快捷方式。
完整说明见 [`Docs/BUILDING.md`](../../Docs/BUILDING.md)。发布包可用
`.\scripts\test-windows-package.ps1 -Version 0.1.0-alpha` 完整验证。开发验证仍使用
`.\scripts\test-windows.ps1`，追加 `-Smoke` 会启动最小测试文档检查 WebView2 阅读链路。
追加 `-PdfLearningSmoke` 会使用本地生成的两页 PDF 验证选区、学习记录/生词保存及返回原页，
不连接 Ollama 或云端服务。
追加 `-PaginationSmoke` 会使用本地长章节验证横向分页、键盘翻页和实时重排。

## 计划技术栈

- UI：WinUI 3 + C#（Windows App SDK）
- EPUB：WebView2 加载 `Shared/ReaderWeb` 的同一构建产物
- PDF：随包携带本地 PDF.js，提供受控渲染、文字选择、上下文和页码 locator；解释、生词/学习记录
  保存与返回原页闭环已完成
- AI：按 `Shared/Contracts/v1` 与 `v4` 实现句子和单词解释，首版连接 Ollama
- 密钥：Windows Credential Manager，不写设置 JSON
- 数据：读取 v1～v5，新增数据写为当前 `learning-library` v5；引入 SQLite 时保留 JSON 导入器

## 第一条垂直链路

```text
打开 EPUB → WebView2 分页 → 选择句子 → Ollama 解句 → 保存学习记录
```

## 创建工程时的目录约束

```text
Apps/Windows/
├── JieJu.Windows/          # WinUI View 与平台服务
├── JieJu.Domain/           # 由共享契约映射出的 C# DTO/接口
├── JieJu.Windows.Tests/
└── JieJu.Windows.sln
```

`WIN-001` 已建立三个项目、严格依赖方向、v1/v2/v3/v5 学习资料迁移、v4 单词解释 DTO 和共享
Bridge。`WIN-101`～`WIN-105` 已加入原生导航、受限 EPUB 加载、章节阅读、排版设置和最近位置。
`WIN-201`、`WIN-202` 已实现 WebView2 选区、上下文、常驻解句栏和 Ollama 流式推理，并在 RTX
5060 Ti 上完成真实 GPU 验收。`WIN-203` 已加入 v5 学习资料保存、记录列表/详情/确认删除及从
EPUB locator 回到原文。`WIN-204` 已加入独立词语解释、生词收藏合并、详情和来源跳转。
`-Smoke -OllamaSmoke`、`-Smoke -VocabularySmoke`、`-Smoke -FuriganaSmoke` 与
`-Smoke -JapaneseDeepSmoke` 可复跑本地推理、词语、自动注音和确定性日语深入解析链路。Windows
现已具备 MeCab/IPADic 分词、日语选区边界、EPUB 自动注音、解释面板注音和日语本地句法层。
OpenAI-compatible 云端 Provider 现已提供 SSE 解句、词语/深入解析和连接检查；API Key 仅保存在
Windows 凭据管理器，默认 Ollama 模式不会调用外网。解释与日语注音清单已经全部对齐，下一项为
`WIN-205` 随手温习。
