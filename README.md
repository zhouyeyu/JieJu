# JieJu（解句）

<p align="center">
  在真实阅读中，读懂一句话，也留住一点语言。
</p>

<p align="center">
  <a href="README.en.md">English</a> · 简体中文
</p>

<p align="center">
  <a href="LICENSE"><img alt="Apache-2.0 License" src="https://img.shields.io/badge/license-Apache--2.0-blue.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111.svg">
  <img alt="Windows 11" src="https://img.shields.io/badge/Windows-11-0078D4.svg">
  <img alt="Project status: Alpha" src="https://img.shields.io/badge/status-Alpha-EA8C00.svg">
</p>

JieJu 是一款本地优先、面向语言学习的 PDF / EPUB 阅读器。阅读时选中单词、表达或句子，即可获得翻译、句子结构、语法说明和重点表达；真正值得记住的内容可以保存到生词本，在以后从容地再次遇见。

> 语言学习是一场缓慢而长久的相遇。今天记住一点，忘记一点，也仍然是在向前走。

<p align="center">
  <img src="Docs/Assets/README/jieju-macos.jpg" alt="JieJu macOS：EPUB 阅读、日语注音与分层解句" width="100%">
  <br>
  <sub>macOS · EPUB 阅读、日语注音与分层解句</sub>
</p>

<p align="center">
  <img src="Docs/Assets/README/jieju-windows.png" alt="JieJu Windows：EPUB 阅读与弹出式深入解析" width="100%">
  <br>
  <sub>Windows · EPUB 阅读、注音与弹出式深入解析</sub>
</p>

项目处于 **0.1 Alpha**。macOS 已具备较完整的阅读与学习闭环；Windows 提供可运行的开发预览版。当前尚未发布签名安装包，请从源码构建。

## 为什么做 JieJu

很多阅读工具会把翻译、词典、语法和笔记拆散。JieJu 希望把它们放回阅读现场：解释服务于正在读的这一句话，学习记录保留它出现时的语境，复习则保持自愿、安静且没有压力。

- **阅读优先**：解释可以显示在常驻侧栏或弹窗中，不必离开原文。
- **分层理解**：先看翻译和主干，再按需展开句型、成分、语法与表达。
- **本地优先**：默认连接本机 Ollama；云端 OpenAI-compatible 服务完全可选。
- **尊重遗忘**：没有连续打卡、红点、积压数字或强制提醒。
- **不伪装确定性**：小模型可能出错，保存前会校验结构，但讲解仍应被视作辅助线索。

## 主要功能

| 能力 | macOS | Windows 开发预览版 |
| --- | :---: | :---: |
| PDF 阅读 | ✅ | ◐ |
| 可重排 EPUB 阅读 | ✅ 分页 | ✅ 连续阅读 |
| 单词 / 表达 / 句子选区识别 | ✅ | ✅ |
| 流式翻译与分层语法讲解 | ✅ | ✅ |
| 日语分词、原形、活用与假名注音 | ✅ | ✅ |
| 生词本、来源语境与返回原文 | ✅ | ✅ |
| 自愿的间隔温习 | ✅ | ✅ |
| Ollama / OpenAI-compatible Provider | ✅ | ✅ |

`✅` 表示已进入当前源码，`◐` 表示可用但功能仍在补齐。准确进度以 [TODO.md](TODO.md) 和 [CHANGELOG.md](CHANGELOG.md) 为准。

### 阅读与解句

- 打开带文本层的 PDF 和可重排 EPUB。
- EPUB 支持主题、字号、行距、页边距、目录、键盘翻页和阅读位置恢复。
- 自动区分单词、表达、句子和段落；不确定时允许手动选择解释方式。
- 流式显示翻译、句子主干、语法点和重点短语，深入句法分析按需触发。
- 日语正文可选择显示汉字注音；注音不会进入选区或 AI 请求。

### 积累与温习

- 保存解句结果、生词、多个语境义和原文位置。
- 从学习记录、生词来源或温习卡片返回原文。
- 复习卡片采用温和的间隔调度，每轮可以随时停止。
- 阅读进度、学习资料和偏好默认保存在本机。

## 快速开始

### macOS

环境要求：macOS 14+、Xcode 16+；本地 AI 另需 [Ollama](https://ollama.com/)。Apple Silicon（M1 或更新）是推荐环境。

```bash
git clone https://github.com/zhouyeyu/JieJu.git
cd JieJu
ollama pull qwen2.5:1.5b-instruct
open JieJu.xcodeproj
```

在 Xcode 中选择 `JieJu` scheme 后运行应用。启动 Ollama，并在 JieJu 设置中检查本地服务连接。`0.5B` 模型可以用于实验，但复杂语法的稳定性明显弱于默认的 `1.5B`。

### Windows

Windows 客户端使用 WinUI 3、.NET 和 WebView2，目前面向开发者提供源码预览。请先阅读 [Windows 开发指南](Apps/Windows/README.md)，再在 PowerShell 中运行：

```powershell
.\scripts\test-windows.ps1
```

Windows 的实际 SDK 版本、启动方式和可选冒烟测试均记录在该指南中。

## AI Provider 与隐私

JieJu 默认使用 `http://127.0.0.1:11434` 上的 Ollama。此模式下，选中文本和有限上下文只会发送到用户配置的 Ollama 服务。若主动切换到 OpenAI-compatible Provider，相同内容会发送到所填写的服务地址，其数据政策由对应服务提供方决定。

- 项目不包含广告、产品分析或第三方遥测 SDK。
- 云端 API Key 保存在 macOS 钥匙串或 Windows 凭据管理器中。
- API Key 不会写入学习资料、偏好文件、日志或 Git。
- EPUB 被视为不可信输入：书内脚本与隐式外部网络访问受到限制。

本地数据位置和删除方式见 [隐私说明](PRIVACY.md)。安全问题请按照 [安全政策](SECURITY.md) 私下报告。

## 架构概览

```text
macOS · SwiftUI / PDFKit / WKWebView ─┐
                                      ├─ Shared/Contracts ─ AI / Learning Data
Windows · WinUI 3 / WebView2 ─────────┘          │
                                         Shared/ReaderWeb
```

- `JieJu/`：macOS 应用、阅读器和平台适配。
- `Apps/Windows/`：Windows 原生应用、领域层和测试。
- `Packages/JieJuLanguage/`：独立 Swift 语言引擎、Provider、CLI 和评测工具。
- `Shared/Contracts/`：版本化的跨平台 JSON 契约。
- `Shared/ReaderWeb/`：WKWebView 与 WebView2 共用的 EPUB Bridge。

设计边界见 [ARCHITECTURE.md](ARCHITECTURE.md)，产品原则见 [PRODUCT.md](PRODUCT.md)，跨平台约定见 [Docs/CROSS_PLATFORM.md](Docs/CROSS_PLATFORM.md)。

## 测试

macOS 与共享模块的完整测试入口：

```bash
./scripts/test-all.sh
```

Windows 的构建、单元测试和可选 WebView2 冒烟入口：

```powershell
.\scripts\test-windows.ps1
```

自动测试默认使用确定性的 Mock 或 Stub，不依赖真实模型或外网。涉及界面、真实 Ollama 和电子书兼容性的改动，还应记录手工验收结果。

语言引擎也可以独立试验：

```bash
cd Packages/JieJuLanguage
swift run JieJuAILab explain --stream --text "彼は本を読みながら、音楽を聞いている。"
```

## 当前限制与路线

- 扫描型 PDF 尚不支持 OCR。
- 复杂 EPUB 排版、脚注、内部链接和跨阅读器稳定定位仍在完善。
- 本地小模型的速度与讲解质量取决于设备、模型和文本复杂度。
- Windows 的 PDF 选区闭环与 EPUB 分页尚未完全对齐 macOS。
- 尚无签名、公证并提供校验和的 Alpha 安装包。

近期计划公开维护在 [TODO.md](TODO.md)。项目不会把社交竞争、强制提醒或打卡机制列入学习体验。

## 参与贡献

欢迎提交代码、文档、测试、语言评测案例和可公开再分发的最小 EPUB/PDF 样本。开始前请阅读：

- [贡献指南](CONTRIBUTING.md)
- [社区行为准则](CODE_OF_CONDUCT.md)
- [安全政策](SECURITY.md)
- [多 Agent 协作约定](AGENTS.md)

一个 Pull Request 应解决一个边界清晰的问题，并说明验证方式、隐私影响及素材来源。AI 辅助生成的贡献仍需要提交者阅读、验证并承担责任。

## 许可证

JieJu 以 [Apache License 2.0](LICENSE) 开源。第三方组件和词典保留各自许可证，发布包将附带相应归属说明。
