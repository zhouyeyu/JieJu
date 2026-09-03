# JieJu Windows Shell（预留框架）

Windows 版本尚未进入实现阶段。本目录提前固定边界，避免未来复制 macOS 业务代码或另建不兼容数据。

## 计划技术栈

- UI：WinUI 3 + C#（Windows App SDK）
- EPUB：WebView2 加载 `Shared/ReaderWeb` 的同一构建产物
- PDF：首个原型使用 PDF.js；是否与 macOS 统一待垂直闭环评测
- AI：实现 `Shared/Contracts/v1`，首版连接 Ollama 或 OpenAI Compatible HTTP
- 密钥：Windows Credential Manager，不写设置 JSON
- 数据：先读写 `learning-library.schema.json` v1；引入 SQLite 时提供 v1 导入器

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
伪 `.csproj`。Windows Agent 的第一项任务应是 `WIN-001`，并且不能修改 macOS Reader 接口。
