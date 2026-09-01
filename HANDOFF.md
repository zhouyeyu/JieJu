# JieJu Agent Handoff

## 本次交接

- 日期：2026-09-02
- Agent：WorkBuddy
- 阶段：并行模块首轮集成（Track A：AI-211/212 已修复，真实模型基线已建立）
- 分支：`main`
- 基线提交：`fbdf02f chore: create macOS project foundation`
- 模块集成提交：`3529d0f feat: build parallel reader language and storage modules`
- 语言修复提交：`a427e01 fix: bind target language into Ollama JSON schema`

## 本次完成内容

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

## 验证

- JieJuLanguage 包测试：**33 项通过**（`swift test --disable-sandbox`）。
- 单句实测：0.5B「火车于六点出发。」、1.5B「火车六点出发。」均正确。
- `xcodebuild build`：上一任记载为通过；**WorkBuddy 工具环境未能独立复验**
  （解析本地 SwiftPM 依赖时 `sandbox_exec` 被拒，属环境限制，非工程缺陷）。
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

1. **改设置会读丢正在读的 PDF**（TODO `PDF-112`）：`AppShellView` 给 `ReaderView` 加
   `.id("\(provider)-\(url)-\(modelName)")`，`ReaderViewModel` 是 `ReaderView` 内的
   `@StateObject`。「模型名称」输入框每敲一键 id 就变 → ReaderView 重建 →
   已打开 PDF、页码、选区全部丢失。
2. **英文释义漏网**：AI-212 只拦截翻译与原文完全相同；同语言释义仍能通过校验。
   可在 `validated(against:)` 增加启发式（如检测翻译为源语言字符集）或交给评测门槛把关。
3. 无障碍小项：`LearningRecordsView` 删除仅 contextMenu，缺键盘/VoiceOver 路径；
   `ReaderExplanationPopover` 错误态仅 `foregroundStyle(.red)`，未配图标或文字。

## 已知问题

- 真实模型质量未达标（0.5B 75%，门槛 95%）；默认模型 1.5B 已定档（DECISIONS.md）
- EPUB：解析核心完成，**阅读界面未实现**（渲染方案待定）
- 缺少固定测试 PDF 和完整 UI 流程；
- 尚未实现「重新解释已保存句子」（INT-009）与学习记录详情页；
- 本机开发者模式关闭，App/UI 测试全线阻塞；
- 工作区中的 `.workbuddy/` 未纳入版本控制，接手者不得擅自删除。

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
2. 修 `PDF-112`（改设置丢 PDF）。
3. 用户开启开发者模式（`sudo DevToolsSecurity -enable` + 重启）后跑 App/UI 测试与 `PDF-009`。
4. `AI-403`：扩展到 100 条正式评测句（在模型定档之后做，避免反复返工）。

任务结束后更新本文件，不要只把交接信息留在聊天中。
