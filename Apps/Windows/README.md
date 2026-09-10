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

安装对应 .NET SDK 后，在仓库根目录运行 `./scripts/test-windows.ps1`。追加 `-Smoke` 会分别启动
欢迎页和最小测试 EPUB，验证 WebView2、章节导航与共享 Reader Bridge。

## 计划技术栈

- UI：WinUI 3 + C#（Windows App SDK）
- EPUB：WebView2 加载 `Shared/ReaderWeb` 的同一构建产物
- PDF：首个原型使用 PDF.js；是否与 macOS 统一待垂直闭环评测
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
`-Smoke -OllamaSmoke` 与 `-Smoke -VocabularySmoke` 可复跑两条本地推理链路。下一项任务是
`WIN-205` 温习流程。不得为了方便修改 macOS Reader 的公开接口。

首个 Pull Request 只应包含可构建的 Windows 工程骨架、依赖方向和自动测试入口；EPUB 垂直闭环
作为后续独立任务实现。
