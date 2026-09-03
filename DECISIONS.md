# JieJu Decisions

## 2026-09-03：复习首版使用可解释的版本化间隔调度器

复习首版使用 `jieju-interval-v1`：新卡按忘记/困难/良好/简单分别进入 10 分钟、1 天、2 天、4 天，
后续依据难度因子增长间隔；遗忘会回到学习状态。它是可测试的过渡调度器，不宣称等同 FSRS。
每次评分追加包含调度器版本和前后间隔的 `ReviewLog`，因此后续评估并切换 FSRS 时可以重算，
而不丢用户历史。默认只自动生成一张识别卡，语境挖空卡待加入用户开关后再启用，避免复习量翻倍。

## 2026-09-03：生词、来源语境和复习卡片分层保存

单词解释是解句后的可选操作，但生词不能作为 `SavedExplanationRecord` 的内嵌附属数据。
`VocabularyEntry` 保存用户可修正的词义，`VocabularySource` 保留多个原句和文档来源，
`ReviewCard` 与只追加的 `ReviewLog` 负责间隔复习。模型只提出候选和语境义，不自动收藏；日语
读音、原形和活用继续优先采用本地 MeCab/IPADic。调度器通过协议隔离，首版评估并固定一个
FSRS/Anki 风格版本，保留日志以支持未来算法迁移。该功能通过新的 learning-library v2 引入，
不修改已经固定的跨平台 v1 schema。

## 2026-09-03：多平台采用原生外壳 + 共享契约 + 共享 Reader Web

Windows 支持不通过立即重写 SwiftUI 实现。macOS 保留 SwiftUI/PDFKit/WKWebView，Windows 计划
使用 WinUI 3/WebView2；双方共享版本化 JSON Schema、EPUB Web 层、评测和 fixture。当前先建立
`Shared/Contracts/v1`、Reader Bridge 与 Windows 接入骨架，EPUB 脚本后续逐项迁移并维持 macOS
回归。暂不决定 Rust 核心，也不创建无法在 Windows SDK 下验证的占位 WinUI 工程。

## 2026-09-02：EPUB 正式模式改用 WebKit 动态分页

实际试读表明“一章一个长滚动页”会把十几章误呈现为十几页，不符合桌面图书阅读预期。
后续正式阅读模式使用 `WKWebView` 渲染原始 XHTML/CSS，并以视口多栏布局动态分页；现有
`NSTextView` 保留为简洁和无障碍回退模式。阅读进度保存章节与内容锚点，不保存不稳定的
动态页码。WebKit 选区通过受控 JavaScript 桥接为现有 `ReaderSelection`。

## 2026-09-02：深度句法按需生成，日语读音不以小模型为真值来源

快速解句继续使用 1.5B 输出翻译、主干和少量语法；句型、成分和从句关系由用户按需触发
“深入解析”，并单独评测 1.5B/3B。日语假名采用本地形态分析和词典生成结构化读音片段，
模型只负责语法说明及消歧解释，避免小模型的错误读音直接用于语言学习。

## 2026-09-02：EPUB 第一版采用原生可重排文本

EPUB 阅读首版使用 `NSTextView` 呈现解析后的段落文本，而不是直接用 WebKit 渲染原始 XHTML。
这样能立即获得稳定的 macOS 原生文本选择、动态窗口重排和无障碍基础，并可直接复用 PDF 的
统一 `ReaderSelection` 与解句流程。解析层继续保留 `rawXHTML`，图片、原书 CSS、脚注和链接
等高保真能力可在后续富文本/WebKit 模式中补充，不阻塞语言学习 MVP。

## 2026-09-02：EPUB 支持分两阶段（解析核心先行）

用户要求支持 EPUB，更新原「先验证 PDF 再实现 EPUB」的决策：解析核心（ZIP 解包、
container/OPF、spine 顺序、章节文本抽取）先行实现并可独立验证；
阅读界面（渲染方案 WebKit vs 重排文本待定）与选区解句复用现有管线，作为下一阶段。
PDF 闭环验收仍保持优先。无第三方依赖，ZIP 用系统 zlib，XML 用 Foundation。

## 2026-09-02：默认模型定为 qwen2.5:1.5b-instruct

冒烟集（20 条）实测对照：0.5B 结构化成功率 75%、翻译在被动/文学/指代消解等类别系统性失败；
1.5B 结构化成功率 100%、全部翻译正确、语法/短语产出条目数是 0.5B 的 7 倍。
单句延迟 0.5B 约 2.2 秒、1.5B 约 4.1 秒，MVP 为异步解句场景，延迟可接受。
默认模型统一为 1.5B（`OllamaDefaults.model` 单一来源），0.5B 仍可在设置中选择。

## 2026-09-02：模型输出字段语言绑定到请求

Ollama JSON Schema 的字段描述必须携带 `explanationLanguage`/`sourceLanguage`，
不能依赖全局 system prompt 指令；`translation` 等字段名本身对小模型构成词汇诱导，
语言要求必须出现在字段描述最前。

## 2026-09-01：采用原生 macOS 技术栈

使用 SwiftUI、AppKit 和 PDFKit，最低支持 macOS 14。第一阶段不引入第三方 UI 或 PDF 依赖，以降低工程和多 Agent 协作复杂度。

## 2026-09-01：先验证 PDF，再实现 EPUB

PDF 文本选择和解句交互是 MVP 的主要技术与体验风险。完成该闭环后再增加 EPUB，避免同时维护两套渲染体系。

## 2026-09-01：模型 Provider 可替换

业务层通过 `ReadingAI` 协议调用模型。Ollama 是第一个真实实现，但不会成为业务层的硬依赖。自动测试使用 Mock 或 Stub。

## 2026-09-01：仓库文件是 Agent 间的事实来源

Agent 不依赖特定工具的历史对话。任务状态、架构决策、测试结果和交接信息必须写入版本控制中的 Markdown 文件。

## 2026-09-01：同一工作区单写者

同一工作区同一时间仅允许一个 Agent 修改。确需并行时使用独立分支或 worktree，并提前划分互不重叠的文件范围。
