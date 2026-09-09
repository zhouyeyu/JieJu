# JieJu Windows

Windows 版本尚未生成可运行工程。本目录是 Windows 原生外壳的唯一入口；开始前请完整阅读
[`Docs/WINDOWS_DEVELOPMENT.md`](../../Docs/WINDOWS_DEVELOPMENT.md) 和
[`Docs/CROSS_PLATFORM.md`](../../Docs/CROSS_PLATFORM.md)。

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

创建 WinUI 工程前必须先在 Windows CI/开发机确认 SDK 版本，因此当前不提交无法在本仓库验证的
伪 `.csproj`。Windows Agent 的第一项任务是 `WIN-001`：创建工程、记录实际 SDK 版本、建立测试
项目并让最小窗口与 WebView2 在 Windows 真机上运行。不得为了方便修改 macOS Reader 的公开接口。

首个 Pull Request 只应包含可构建的 Windows 工程骨架、依赖方向和自动测试入口；EPUB 垂直闭环
作为后续独立任务实现。
