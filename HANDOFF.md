# JieJu Agent Handoff

## 本次交接

- 日期：2026-09-02
- Agent：Codex
- 阶段：PDF/EPUB 阅读闭环集成（EPUB-102 已完成）
- 分支：`main`
- 基线提交：`fbdf02f chore: create macOS project foundation`
- 模块集成提交：`3529d0f feat: build parallel reader language and storage modules`
- 语言修复提交：`a427e01 fix: bind target language into Ollama JSON schema`

### 2026-09-02 额度中断检查点（接手者先读）

- 本轮修复了注音混入选区、翻页残留选区、误选下一句残片、侧栏重排定位、保存反馈和学习记录详情；
  日语本地语法同时纠正「十八で」并增加「た形＋ばかり」。
- 语言包 **51 项通过**；App 单元测试 **46 项通过**；随后加入的 `forceLayout()` 原生回退已通过
  `xcodebuild build`，但因用户中断，尚未重新跑单元测试。
- XCTest UI Runner 仍因 `Timed out while enabling automation mode` 无法启动，这不是产品断言失败。
- 重要：真实 EPUB 首版“稳定两次才上报”曾导致一直停在“正在排版”，已改为有限重试，并新增
  `WKNavigationDelegate.didFinish` 一秒后的 `forceLayout()` 回退。最后构建成功，但界面复测恰好被
  中断。下一位 Agent 的第一项任务应是打开《ノルウェイの森》，确认约 1 秒后从“正在排版”进入
  `本章 P / N 页`；若仍不退出，优先检查 `EPUBWebReaderView.Coordinator.didFinish` 的 JS 返回类型。
- `.workbuddy/` 仍是用户未跟踪目录，未修改、未纳入提交。

## 本次完成内容

- 完成 `EPUB-211C`：设置页 EPUB 排版区域增加实时页面预览，字号、行距、左右边距和四种主题均
  立即反馈。注入 CSS 进一步对 `p/li/blockquote/dd/dt` 显式覆盖字号与行距，解决 EPUB 自带
  固定段落样式导致滑块看似无效的问题，同时不覆盖标题字号层级。
- 完成 `INT-015`：`AppShellView` 不再用互斥 `switch` 创建/销毁 Reader。Reader 始终保留在详情
  区域，设置与学习记录以覆盖层显示；隐藏期间禁用点击、键盘快捷键和辅助功能暴露。返回阅读页
  会复用同一个 `ReaderViewModel`，因此已打开文档、章节、章内页和选区不会丢失。
- 完成 `EPUB-211B`：设置页新增白纸、夜间、羊皮纸、护眼绿四种阅读背景并持久化。主题会同时
  设置 WKWebView 底色、HTML/body 背景，以及正文全部子元素的前景色，防止透明 WebView 与系统
  深色模式、书内固定白字叠加后出现白底白字。默认白纸为 `#FAFAF8` + `#1C1C1E`。
- 主题变化会重建当前 EPUB 渲染视图并保留章内阅读位置；新增四主题 CSS 覆盖与设置持久化测试，
  App 单元测试现为 43 项全部通过。
- EPUB 分页强制规范原章节 `body` 的视口宽高、边距和多栏属性，并通过横向滚动偏移翻页；曾尝试
  把正文 DOM 搬入独立容器，但实际 EPUB 出现整页空白，现已撤销该方案并补回归测试。长章节仍按
  当前窗口拆页，资源处理同时覆盖 `application/xhtml+xml` 与 `text/html` 章节。
- 章内底栏新增页进度条及“第 X/Y 章 · 本章 P/C 页”；窗口、图片和字体加载变化会防抖重排，
  上一页/下一页及方向键均先在章内逐页移动，到边界后才跨章。
- 阅读位置由仅保存章节扩展为“章节索引 + 章内页码”，打开、跨章和调整排版后均恢复最近书页；
  保留旧章节位置键作为兼容回退。新增存储和分页注入回归测试，App 单元测试 42 项全部通过。
- 完整 App 界面验收仍需 macOS 允许辅助功能控制；自动控制本轮停在授权等待，因此 `EPUB-214`
  仍保留，不能把离线测试误记成完整 UI 测试。
- 完成 Ollama 快速解句流式链路：新增可取消的 URLSession NDJSON 行流、增量 JSON 字符串/对象
  解析和 App `streaming` 状态。翻译、主干、合法语法点和短语会随生成逐步刷新，最终严格校验
  通过前不提供保存或深度分析按钮；格式损坏仍保留一次修复。
- Prompt 固定字段生成顺序为翻译→主干→语法→短语；可解码结果优先本地清洗，避免仅因一个
  越界条目再次等待模型。CLI 增加 `stream` 实验命令。真实 1.5B 测试首次内容约 1.45 秒、
  翻译完成约 1.78 秒、最终约 3.92 秒。
- 修复 EPUB “16 页等于 16 章”的误导：工具栏现明确显示章节进度，章内底栏继续显示动态页数；
  WebKit 分页从仅测 `documentElement.scrollWidth` 改为测正文真实多栏宽度，避免长章被算成一页。
- 日语注音设置明确为“关闭/开启”；关闭时隐藏原书和自动 Ruby，开启时 `rt/rp` 使用不可选择
  样式。选区桥接对 Range 和整章正文分别克隆并移除 `rt/rp`，保证假名不进入目标句或上下文。
- 新增分页脚本、Ruby 选区与章节标签回归测试；两项针对性 App 测试实跑通过，语言包 47 项通过。
- 完成 `JA-003`：以固定 revision `1f096492...` 接入 Mecab-Swift + IPADic，默认本地 Provider
  现在返回分词、平假名读音、词性、词典原形、活用状态及汉字对齐区间；tokenizer 使用锁保护。
  IPADic Bundle 约 51MB，Debug App 约 136MB。高频小词典仅保留为初始化失败回退。
- 完成 `JA-006`：EPUB 开启“汉字注音”时，从本地词典结果生成安全 JSON，在 DOMContentLoaded
  阶段遍历正文 Text Node 注入 `<ruby>`；跳过原书 Ruby、rt、script、style、head 和 textarea。
  章节内同一表层形有多个读音时不注入，避免多音词被全局错误替换；注入结果按资源路径缓存。
- 修复日语深入解析超时和内容空洞：不再让 1.5B 填充庞大的日语 Deep Schema，而由本地
  `JapaneseGrammarAnalyzer` 基于 MeCab token 生成助词功能、日语句式骨架、谓语、原形和常见
  「〜ている／〜ました／〜ません／〜たい」活用说明。实测「私は日本語の本を読んでいます。」
  从模型失败/可能 60 秒超时变为约 0.013 秒，并稳定解释「は／の／を／〜でいます」。
- 外部依赖已同时锁定在 Swift Package 与 Xcode workspace 的 `Package.resolved`。上游独立探针
  21 项测试通过；本项目语言包 47 项测试通过，App/App Tests/UI Tests build-for-testing 通过。

- 开始 Track G 日语阅读：新增可持久化 `ReadingSegment(surface, reading)`、日语自动识别、
  日语无空格片段校验和可替换 `JapaneseReadingProviding`。当前本地实现仅注音明确命中的高频词，
  未知汉字保持原样，禁止使用模型猜测结果作为正文注音。
- 解句面板新增可换行 Furigana/Ruby 布局，设置页增加“不显示/汉字注音”并持久化；深入解析
  JSON 增加日语词语的原形、假名、活用类型和句中语法功能，并在 UI 标为“AI 参考”。
- 新增 12 条日语读音评测数据，覆盖多音字、姓名、活用、日期数字、熟字训和未知词；
  `Docs/JAPANESE_READING_ENGINE.md` 记录 Sudachi、MeCab/UniDic 与 Apple NaturalLanguage 的取舍。
- 尚未完成：正式形态词典接入与全量汉字—假名对齐（`JA-003`）、无原书 Ruby 的 EPUB 正文
  批量注音注入（`JA-006`）。后续 Agent 不应扩充手写小词典来冒充完整形态分析器。

- 重排后续计划为 Track E（WebKit 动态分页）、Track F（深度句法）和 Track G（日语假名）。
- 完成 `EPUB-201`：`EPUBDocument.resources` 暴露 manifest 资源数据、MIME 类型和标准包内路径；
  `EPUBChapter.resourcePath` 记录章节 XHTML 位置，并增加资源路径与内容回归测试。
- 完成 EPUB WebKit 正式阅读主链路：受限自定义 scheme、CSP 离线边界、XHTML/CSS/图片、
  动态多栏分页、页内/跨章翻页、方向键、章节菜单和 WebKit 选区解句桥接。
- 设置页新增 EPUB 字号、行距和页边距，变化后自动重新排版并持久化；系统明暗模式自动适配。
- 完成 Track F 功能主链路：新增 `DeepAnalysis` 领域模型、原文片段校验、独立深度 Prompt/
  Schema/解析/一次修复和 Ollama 调用；App 在快速结果后提供“深入解析句式与结构”，按层展示
  句型、成分、修饰关系、从句、深度语法和整句理解。深度分析不会随快速解句自动运行。
- 深度分析新增 `JieJuAILab deep` 独立入口和命令解析测试；`component.modifies` 也纳入目标句
  原文校验。新增 12 句句法冒烟集并完成 1.5B 实测：6/12 通过严格结构校验，平均约 20.1 秒；
  小模型常把语法标签写进原文片段字段，且通过项仍有句型误判。结论是 1.5B 暂不应作为
  “可靠深度语法老师”，下一步需完成 3B 对照（本机目前未安装 3B）。

- **EPUB 阅读界面**（`EPUB-101`）：统一打开面板支持 PDF/EPUB；以 `NSTextView` 实现
  原生可重排正文和滚动阅读，工具栏支持上一章/下一章并显示当前章节，章节进度可恢复。
- **EPUB 解句闭环**（`EPUB-102`）：原生选区生成统一 `ReaderSelection`，自动提取前后句，
  复用 Ollama 翻译/语法讲解、侧边栏/弹窗和学习记录保存，不另建一套 AI 接口。
- EPUB 解析移至后台任务，打开较大图书时不阻塞主界面；关闭或重新打开会取消旧加载。
- EPUB 错误增加可读中文说明；阅读入口及学习记录空状态文案改为 PDF/EPUB。

- **完善解句布局**（`PDF-113`）：解句面板增加独立滚动容器，翻译、主干、语法点、
  重点表达改为分区卡片；数组条目逐项显示，长文本固定纵向展开，避免字体拥挤和内容裁切。
- **侧边栏/弹窗切换**（`PDF-114`）：设置页增加分段选择并持久化；默认侧边栏通过
  `HSplitView` 与 PDF 并排，弹窗模式保留选区锚定交互。两种模式复用同一个解释面板。
- 选中原文改为默认折叠的 `DisclosureGroup`；失败状态增加明确图标与文本，不再只依赖颜色。
- 新增显示方式默认值及持久化回归测试。

- 修复 `AI-211`：Ollama JSON Schema 字段描述现在携带
  `explanationLanguage`/`sourceLanguage`（如 `translation` 描述为
  "Translate targetText into Chinese. Write the translation in Chinese, never in English."）。
  实测 0.5B/1.5B 均恢复输出正确中文翻译。
- 修复 `AI-212`：`validated(against:)` 在双语请求下拦截
  `translation` 与 `targetText` 完全相同（含大小写变体）；repair 提示补语言约束。
- 跑通 0.5B 批量冒烟评测（20 条，45 秒），建立真实模型基线；1.5B 对照已启动。
- **保存并恢复最近阅读页码**（`PDF` 阅读闭环补全）：
  - 新增 `ReadingPositionStore`（UserDefaults，按文档标准化路径存页码）；
  - `ReaderViewModel` 打开文档时恢复上次页码，翻页即保存，关闭时兜底保存；
  - `PDFReaderView` 增加 `initialPageIndex`，`makeNSView`/文档切换时 `go(to:)` 定位；
  - 新增 `ReadingPositionStoreTests`（6 项）。
- **修复上一轮 `ca53263` 引入的编译错误**：`AppSettings`/`AppShellView` 中
  `OllamaReadingAI.defaultModel` 是泛型静态成员、无法裸引用，
  已改为非泛型常量 `OllamaDefaults.model`（此前该错误无法编译验证，本轮用类型检查抓到）。
- **EPUB 解析核心**（`JieJu/Infrastructure/EPUB/EPUBCore.swift`，无第三方依赖）：
  自研 ZIP 解包（系统 zlib）+ container/OPF + spine + 章节文本抽取（XML 模式/实体解码/正则回退）。
  测试 fixture：`JieJuTests/Fixtures/{minimal,messy,nocontainer}.epub`（已入测试 Target 资源）。
  实测 7 项测试通过、真实《挪威的森林》EPUB 解析成功（16 章 3169 段）。
  **渲染与阅读界面尚未实现，待选方案（WebKit 排版 vs 重排文本），见 DECISIONS.md。**
- **可配置解释语言**（`INT-012`）：设置页选择解释语言（预设 6 种 + 自定义），
  `AppSettings.explanationLanguage` 持久化；请求与学习记录使用实际语言。
- **修复 `PDF-112`**：移除由 AI 设置驱动的 `ReaderView.id`，改为原位更新 Provider
  与解释语言；当前 PDF、页码和选区不再因设置输入而丢失，并增加配置更新回归测试。
- **真实解句成为默认**（`1a55765`）：旧版 Mock 默认偏好一次性迁移到 Ollama 1.5B；
  修复轮逐项删除越界内容而非清空全部讲解，并明确要求中文翻译/语法/词义。

## 验证

- JieJuLanguage 包测试：**44 项通过**（`swift test`）。
- App、App Tests 与 UI Tests：`xcodebuild build-for-testing` 通过；新增日语识别和注音设置测试。
- Ollama 1.5B 端到端：中文翻译、英文主干、中文语法说明通过；不再返回 Mock 示例。
- 单句实测：0.5B「火车于六点出发。」、1.5B「火车六点出发。」均正确。
- `xcodebuild build`：通过。
- `xcodebuild build-for-testing`：通过，App 单元测试与 UI 测试目标均成功编译。
- 本轮 `xcodebuild build` 与 `build-for-testing` 均通过；JieJuLanguage 35 项测试通过。
- macOS App/UI 测试：**无法运行**。本机 `DevToolsSecurity -status` 为 disabled，
  Runner 卡在 `The test runner hung before establishing connection.`。
- Xcode 人工启动：待用户确认。

## 真实模型基线（2026-09-02，Qwen 2.5 冒烟集 20 条）

### 0.5B（可在设置中选择）

- 结构化成功率 **75%**（15/20），平均 2.2 秒 —— 未达 95% 门槛
- 失败 5 条：3 条英文照抄被 AI-212 正确拦截（passive-01、ambiguity-02、literary-01），
  2 条 JSON 解析失败（nonfinite-01、ambiguity-01）
- 通过条目中 ≥2 条英文释义漏网（nonfinite-02、relative-02）：
  AI-212 只拦「与原文完全一致」，拦不住「同语言释义」
- 长句翻译截断、复杂结构（被动/文学/指代）质量差
- **结论：0.5B 暂不满足 MVP 门槛，不建议作为默认模型**

数据：`Evaluation/results-0.5b.jsonl`、`Evaluation/report-0.5b.md`
（两者均已在 `.gitignore` 中，未入库）

### 1.5B

- 结构化成功率 **100%**（20/20），平均 4.1 秒 —— 达标（门槛 ≥95%）
- 全部翻译正确中文；0.5B 全灭的类别（被动/文学/指代消解/非谓语）全部通过
- 语法点 10/20、短语 10/20，共 50 条目
- **已定为默认模型**：`OllamaDefaults.model` 单一来源，CLI/App 设置/设置页展示均引用

数据：`Evaluation/results-1.5b.jsonl`、`Evaluation/report-1.5b.md`（均 gitignore，未入库）

## 已定位但未修的缺陷

1. **英文释义漏网**：AI-212 只拦截翻译与原文完全相同；同语言释义仍能通过校验。
   可在 `validated(against:)` 增加启发式（如检测翻译为源语言字符集）或交给评测门槛把关。
3. 无障碍小项：`LearningRecordsView` 删除仅 contextMenu，缺键盘/VoiceOver 路径。

## 已知问题

- 真实模型质量未达标（0.5B 75%，门槛 95%）；默认模型 1.5B 已定档（DECISIONS.md）
- EPUB：基础阅读、章节导航与选区解句已完成；目录、排版设置和富文本样式尚未实现。
- 缺少固定测试 PDF 和完整 UI 流程；
- 尚未实现「重新解释已保存句子」（INT-009）与学习记录详情页；
- 本机开发者模式关闭，App/UI 测试全线阻塞；
- 工作区中的 `.workbuddy/` 未纳入版本控制，接手者不得擅自删除。
- EPUB Agent 当前正在修改 Reader/EPUB 文件；`1a55765` 未包含这些并行未提交改动。

## 环境注意事项

- **App 层编译验证的可行办法（重要，替代 xcodebuild）**：
  本工具无法跑 `xcodebuild build`（本地 SwiftPM 解析时 `sandbox_exec` 被拒），
  但可以用裸 `swiftc` 完成等效验证：
  ```bash
  # 1) 先构建本地包（--disable-sandbox）
  cd Packages/JieJuLanguage && swift build --disable-sandbox
  # 2) 整个 App 模块类型检查（先剥离 #Preview，宏插件服务器同样被沙箱挡）
  xcrun swiftc -typecheck -sdk $(xcrun --show-sdk-path) -target arm64-apple-macosx14.0 \
    -I Packages/JieJuLanguage/.build/arm64-apple-macosx/debug/Modules $(find JieJu -name '*.swift')
  # 3) 测试目标：先 emit-module -enable-testing 出 JieJu 模块，再对测试文件 typecheck
  #    （加 -F .../MacOSX.platform/Developer/Library/Frameworks 供 XCTest；
  #     XCTAssertNil 等 C 宏在独立 swiftc 下报 "function like macros not supported"，属正常，Xcode 里没问题）
  ```
  用这个方法在 2026-09-02 实际抓出了 `ca53263` 里的泛型静态成员编译错误。
- 本机 Ollama 已装可达（`:11434`），已拉取 `qwen2.5:0.5b-instruct` 与 `qwen2.5:1.5b-instruct`；
  默认模型为 1.5B（`OllamaDefaults.model`），0.5B 可在设置中选择。
- CLI 二进制：`Packages/JieJuLanguage/.build/arm64-apple-macosx/debug/JieJuAILab`
  - 单句：`JieJuAILab explain --text "..." [--before "..." ] [--after "..."] [--raw] [--model N] [--url U]`
  - 批量：`JieJuAILab batch --input X.jsonl --output Y.jsonl --report Z.md [--model N]`
  - 注意 `--raw/` 之类的尾部斜杠是非法参数，参数之间用空格。
- 本工具无法构建带本地 SwiftPM 依赖的 Xcode 工程（`sandbox_exec` 被拒），
  验证 App 编译只能靠包测试 + 读代码 + 用户在 Xcode 里确认。

## 下一任务建议

1. **人工评分 0.5B/1.5B 输出**（`Evaluation/report-*.md` 的 Manual scoring 表）：
   translationAccuracy / sentenceCoreAccuracy / grammarAccuracy / phraseValue / hallucination。
2. 用户开启开发者模式（`sudo DevToolsSecurity -enable` + 重启）后跑 App/UI 测试与 `PDF-009`。
3. `AI-403`：扩展到 100 条正式评测句（在模型定档之后做，避免反复返工）。

任务结束后更新本文件，不要只把交接信息留在聊天中。
