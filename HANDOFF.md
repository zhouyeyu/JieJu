# JieJu Agent Handoff

## 本次交接

- 日期：2026-09-02
- Agent：WorkBuddy
- 阶段：并行模块首轮集成（Track A 在途，已做检查点提交）
- 分支：`main`
- 基线提交：`fbdf02f chore: create macOS project foundation`
- 模块集成提交：`3529d0f feat: build parallel reader language and storage modules`
- 本次检查点提交：`26861d4 feat: enforce target-only output with structured schema`

## 本次完成内容

- 复核 Phase 0～并行模块集成阶段的项目状态（文档、Git、Xcode 工程、测试）。
- 把上一任遗留的 6 个未提交文件整理为一次小而明确的提交（`26861d4`），
  内容为 `AI-210` 的延续：`sentenceCore` 词子集校验、JSON Schema 受限解码、
  repair 提示降级为「只出可靠翻译」、`validatedRepair` 降级路径及其测试。
- 实测跑通语言引擎 CLI 与 Ollama，产出第一批真实模型数据（见「实测发现」）。

## 验证

- JieJuLanguage 包测试：**30 项通过**（`swift test --disable-sandbox`）。
- `xcodebuild build`：上一任记载为通过；**本次未能独立复验**，
  本工具环境在解析本地 SwiftPM 依赖时被 `sandbox_exec` 拒绝（环境限制，非工程缺陷）。
- macOS App/UI 测试：**无法运行**。本机 `DevToolsSecurity -status` 为 disabled，
  Runner 卡在 `The test runner hung before establishing connection.`。
- Xcode 人工启动：待用户确认。

## 接手者必读：已定位但未修的缺陷

以下三项是本次实测发现的真实问题，**尚未修改任何代码**，留给下一任务处理。

### 1（严重）translation 字段不出中文，且字段名本身是诱导

`explanationLanguage` 默认为 `Chinese`（`Domain.swift:15`），但走 pipeline 时
两个模型都输出英文翻译；而绕开 pipeline 直接打 Ollama 同一句话，
0.5B 能正确输出 `火车在六点钟出发。`——**模型有能力，是 pipeline 的问题**。

根因在 `OllamaReadingAI.swift` 的 `.explanation(minimumItems:)`：
构造的 JSON Schema 完全静态、不感知 request 的语言。

- `translation` 的 description 只写 `Natural translation of targetText`，未提目标语言；
- `explanation`、`meaning` 两个字段没有 description。

进一步证据：`meaning` 字段在同一次请求中**正确输出了中文**，
只有 `translation` 是英文照抄。说明除 schema 描述外，
**字段名 `translation` 本身就是强词汇诱导**——小模型看到 `translation` + 英文输入，
会直接吐英文；`meaning` 更抽象，才会回落去遵循全局的 `explanationLanguage` 指令。

修法方向：把 `explanationLanguage` / `sourceLanguage` 织进 schema 字段描述
（语言写在描述最开头），并评估是否需要改掉或弱化 `translation` 这个字段名。
`.explanation(...)` 目前签名只有 `minimumItems`，需要扩展为接收 request 的语言参数。

### 2 校验拦不住「翻译等于原文」

0.5B 曾把 `targetText` 原封不动填进 `translation`，**通过了 `validated(against:)`**。
`Domain.swift` 目前只校验 `sentenceCore` 与 grammar/keyPhrase 片段是否在原文内，
未校验 translation 是否真的换了语言。
建议当 `explanationLanguage != sourceLanguage` 时，至少拦截两者完全相同的情况。

### 3 改设置会读丢正在读的 PDF

`AppShellView` 给 `ReaderView` 加了
`.id("\(settings.provider.rawValue)-\(settings.ollamaURL)-\(settings.modelName)")`，
而 `ReaderViewModel` 是 `ReaderView` 内的 `@StateObject`。
在「模型名称」输入框**每敲一个字符** id 就变 → ReaderView 被销毁重建 →
已打开的 PDF、当前页码、选区全部丢失。「保存并恢复最近阅读页码」尚未实现，放大了影响。

### 顺带记录（低优先级）

- `LearningRecordsView` 删除记录只有 contextMenu，缺键盘/VoiceOver 可达的替代路径。
- `ReaderExplanationPopover` 的错误态只有 `foregroundStyle(.red)`，
  未配图标或文字标签，违反「不靠颜色单独传达信息」；设置页的连接状态做得是对的，可对齐。

## 已知问题

- 尚未用真实模型批量验证质量（只跑了单句采样，不足以结论）；
- 缺少固定测试 PDF 和完整 UI 流程；
- 尚未恢复阅读页码和重新解释历史记录；
- 本机开发者模式关闭，App/UI 测试全线阻塞；
- 工作区中的 `.workbuddy/` 未纳入版本控制，接手者不得擅自删除。

## 环境注意事项

- 本机 Ollama 已安装且服务可达（`:11434`），
  已拉取 `qwen2.5:0.5b-instruct`（默认）与 `qwen2.5:1.5b-instruct`。
- 单句实测延迟：0.5B 约 1.3～2.6 秒，1.5B 约 6.8 秒。
- CLI 二进制已存在，可直接运行，无需重新构建：
  `Packages/JieJuLanguage/.build/arm64-apple-macosx/debug/JieJuAILab`
  - 单句：`JieJuAILab explain --text "..." [--before "..." ] [--after "..."] [--raw] [--model N] [--url U]`
  - 批量：`JieJuAILab batch --input X.jsonl --output Y.jsonl --report Z.md`
- 本工具无法构建带本地 SwiftPM 依赖的 Xcode 工程（`sandbox_exec` 被拒），
  验证 App 编译这条路走不通，只能靠包测试 + 读代码。

## 下一任务建议

按优先级：

1. **开开发者模式**（`sudo DevToolsSecurity -enable` + 重启）——解锁 App/UI 测试，
   这是「发布前关卡」里唯一还卡着的环境债，需要先由用户执行。
2. **修缺陷 1 与缺陷 2**（schema 语言绑定 + translation 校验），
   这直接决定 MVP 最核心的中文翻译能否成立。
3. **再跑批量评测** `AI-409`/`AI-410`：修完 schema 后再跑 `Evaluation/smoke.jsonl`，
   并做 0.5B 与 1.5B 对照。**当前状态下跑批量评测会得到废数据**，不要提前跑。
4. 修缺陷 3（ReaderView 被重建导致丢文档）。
5. 之后再做 `PDF-009`（固定测试 PDF）与 `INT-010`（端到端 UI 测试）。

任务结束后更新本文件，不要只把交接信息留在聊天中。
