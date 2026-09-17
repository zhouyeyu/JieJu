# JieJu v0.0.1 — macOS developer preview

首个 macOS 开发预览安装包，面向早期测试者，不是已签名、公证的稳定发行版。

## 下载与安装 / Installation

- `JieJu-0.0.1-macOS-arm64.dmg`：Apple Silicon（M1 或更新），macOS 14+。
- 打开 DMG，将 JieJu 拖入 Applications；附件 `.sha256` 用于校验下载完整性。
- 应用仅使用 ad-hoc 签名，**没有 Developer ID 签名或 Apple 公证**。Gatekeeper 可能阻止启动；
  不建议关闭系统安全保护。需要正常验证的发行版请等待后续签名发布，或从源码使用 Xcode 构建。
- 不包含 Ollama 服务或模型；本地解句需自行安装 Ollama 并获取 `qwen2.5:1.5b-instruct`。
  也可在设置中显式配置 OpenAI-compatible 服务；云端模式会发送选区及有限上下文。

Apple Silicon only, macOS 14 or later. Drag JieJu to Applications.
This preview is ad-hoc signed, **not Developer ID signed or notarized**; Gatekeeper may block it.
Do not disable system protections. Ollama and its models are not bundled.

## 功能 / Features

- PDF 与可重排 EPUB 阅读、主题及排版设置、最近阅读和位置恢复。
- 流式翻译、句子主干、语法与按需深入解析；词语释义与日语假名注音。
- 学习记录、生词本、可选的低压力间隔温习，以及回到原文。
- 新的共享黑白图标，macOS 与 Windows 工程均已接入。

PDF/EPUB reading, streaming explanations, vocabulary, optional gentle review,
Japanese readings, source navigation, and a shared application icon.
This release includes a macOS DMG only, not a Windows installer.

## 已知限制 / Validation

- 小模型讲解可能不准确；深入解析不保证教师级质量。
- 共享 Node 15、语言引擎 65、macOS 单元 77 项已通过。
- 全量测试已尝试；UI Runner 被系统认证状态 `System authentication is running` 阻止初始化，
  不能声称本版本通过完整 UI 自动验收。首次安装及 Gatekeeper 干净账户验证尚未完成。
- Windows 新图标尚待真机确认；Windows 后续主分支提交不在本发布分支范围内。

Unit tests pass; UI automation is blocked by system authentication. Clean-account
installation and Gatekeeper acceptance are not verified. AI output can be incorrect.
