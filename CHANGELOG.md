# 更新日志

本文件记录 JieJu 的重要变化。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

- macOS 原生 PDF 与可重排 EPUB 阅读器。
- 本地 Ollama 与 OpenAI-compatible AI Provider。
- 流式句子翻译、主干识别、深度语法和重点短语讲解。
- 日语汉字假名注音与可切换显示。
- 单词识别、独立释义、生词本和低压力间隔复习。
- 本地学习记录、阅读进度与版本化跨平台契约。
- Apache-2.0 许可证、贡献指南、安全和隐私文档。
- 可运行的 Windows WinUI 3 开发预览版。
- 中英双语项目 README、平台状态矩阵与统一快速开始说明。
- macOS 与 Windows 一键 Release 构建、便携开发预览 ZIP 和 SHA-256 校验脚本。
- Windows PDF 选区解释、生词/学习记录保存，以及从来源返回 PDF 原页。
- Windows EPUB 横向分页、页内进度、键盘翻页与实时重排状态。
- Windows Alpha ZIP 的当前用户安装/卸载脚本、第三方归属摘要、SHA-256 与自动发布包验证。

### Known limitations

- 暂无 OCR 或签名发布包；Windows 的 PDF 选区与 EPUB 分页仍未完全对齐 macOS。
- 部分复杂 EPUB 排版、内部链接和稳定位置恢复仍待完善。
- 小参数模型对复杂语法的解释可能不稳定。

## [0.0.1] - 2026-09-17

- 首个 Apple Silicon macOS 开发预览 DMG（ad-hoc 签名，未公证）。
- 接入共享黑白应用图标、双平台资源与可复现生成脚本。
- 已发布 tag 与 DMG 保持原样；后续 Windows 增量位于 Unreleased，不计入该安装包。
