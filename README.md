# JieJu（解句）

JieJu 是一款面向语言学习的 macOS 原生 PDF / EPUB 阅读器。它希望让“读懂一句话”自然地发生在阅读途中：选中文字，查看翻译、句子结构、语法和重点表达，再把真正想记住的词收入生词本。

> 语言学习是一场缓慢而长久的相遇。今天记住一点，忘记一点，也仍然是在向前走。

项目目前处于 **0.1 Alpha**：主要阅读与学习闭环已经可用，但格式兼容性、模型效果和发布体验仍在完善。暂未提供签名安装包，请从源码构建。

## 已有能力

- PDF 与可重排 EPUB 阅读，支持主题、字号、行距、边距和日语假名注音。
- 最近阅读与继续阅读，保存 PDF 页码或 EPUB 章节位置；文件移动后可重新定位。
- 区分单词与句子选区，并提供更合适的解释入口。
- 句子翻译、主干识别、深度句法与语法讲解、重点短语提取。
- 单词释义、生词本与低压力的间隔复习卡片。
- 流式显示模型结果，减少本地小模型的等待感。
- 默认通过本机 Ollama 推理，也可配置 OpenAI-compatible 服务。
- 阅读进度、学习记录和偏好保存在本地。

AI 解释可能出错，尤其是小参数模型处理复杂句、文学省略和罕见表达时。请把它视为辅助理解的线索，而不是权威语法结论。

## 隐私与数据

使用 Ollama 时，解释请求只发送到本机配置的服务。只有主动选择云端 Provider 后，选中的文本及其有限上下文才会发送到相应服务。项目目前不包含遥测或分析 SDK。

学习记录保存在 `~/Library/Application Support/JieJu/library.json`，云端 API Key 保存在 macOS 钥匙串。更完整的说明见 [PRIVACY.md](PRIVACY.md)。

## 环境要求

- macOS 14 或更高版本
- Xcode 16 或更高版本（Swift 6）
- Node.js 20 或更高版本（仅契约测试需要）
- Ollama（仅使用本地 AI 时需要）

Apple Silicon（M1 或更新）是本地模型的推荐环境。Intel Mac 可以构建应用，但本地推理体验未作为当前优化目标。

## 从源码运行

1. 获取仓库后，在项目根目录打开工程：

   ```bash
   open JieJu.xcodeproj
   ```

2. 在 Xcode 中选择 `JieJu` scheme，运行 macOS App。

3. 如需本地 AI，先启动 Ollama 并安装默认模型：

   ```bash
   ollama pull qwen2.5:1.5b-instruct
   ollama serve
   ```

4. 在 JieJu 设置中选择 Ollama，并按需调整服务地址和模型名。

0.5B 模型也可用于实验，但复杂语法的稳定性通常不如 1.5B。Provider 通过统一接口隔离，阅读器不依赖某个固定模型。

## 测试

运行完整测试入口：

```bash
./scripts/test-all.sh
```

脚本依次运行跨平台契约测试、语言引擎测试、App 单元测试和关键 UI 测试。macOS UI 测试需要在“系统设置 → 隐私与安全性”中启用开发者模式。

语言引擎也提供命令行实验入口：

```bash
cd Packages/JieJuLanguage
swift run JieJuAILab explain --text "彼は本を読みながら、音楽を聞いている。"
swift run JieJuAILab explain --stream --text "Although it was raining, she went out."
```

## 项目结构

```text
JieJu/                  macOS App、阅读器与持久化适配
Packages/JieJuLanguage 独立语言领域模型、Provider、CLI 与测试
Shared/Contracts/      跨平台稳定 JSON 契约
Evaluation/            小模型评测数据与报告
Docs/                  架构专题和发布文档
```

产品方向见 [PRODUCT.md](PRODUCT.md)，架构边界见 [ARCHITECTURE.md](ARCHITECTURE.md)，近期任务见 [TODO.md](TODO.md)。多 Agent 协作前请先阅读 [AGENTS.md](AGENTS.md) 和 [HANDOFF.md](HANDOFF.md)。

## 当前限制

- 扫描型 PDF 尚不支持 OCR。
- EPUB 的复杂排版、内部链接和跨版本稳定定位仍需继续兼容。
- 本地小模型的速度和讲解质量受机器、模型和文本复杂度影响。
- 尚未发布经过签名与公证的安装包。
- Windows 已有可运行开发版，支持 EPUB 阅读、Ollama 选句解释与学习记录；分页、PDF、生词和复习仍在开发。

兼容性问题请使用对应 Issue 模板，并只上传有权公开的最小复现文件。

## 参与项目

欢迎提交缺陷、EPUB 兼容性样本、模型讲解案例和代码改进。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。

## 许可证

JieJu 以 [Apache License 2.0](LICENSE) 开源。第三方依赖仍适用各自的许可证。
