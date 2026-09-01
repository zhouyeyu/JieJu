# JieJu Progress

## 当前阶段

并行模块首轮集成。Track A 语言引擎核心问题已解决：
**中文翻译链路打通，默认模型定为 1.5B 并实测达标**（见 DECISIONS.md）。
剩余主要是人工评分、App 层修复与 UI 测试。

## 已完成

- 建立跨 Codex、Cursor、WorkBuddy 的仓库内协作协议；
- 明确 MVP 产品边界与初始架构；
- 创建最小 macOS SwiftUI App、单元测试和 UI 测试目标；
- 建立统一构建测试入口。
- 建立独立语言 Swift Package、CLI 与批量评测；
- 完成 PDFKit Reader、选区解释弹窗和前后句提取；
- 完成 JSON 存储、CRUD、去重和损坏恢复；
- 完成 Mock/Ollama 设置、学习记录保存和列表；
- 建立 20 条语言冒烟评测集。
- 增加 Ollama/模型诊断和设置页一键检查；
- Prompt 改为 JSON 输入边界，并使用确定性生成参数。
- 增加目标句内容一致性校验：拦截引用上下文或虚构片段的结构化输出，并带原始输入修复一次。
- 输出改用 JSON Schema 受限解码，`sentenceCore` 增加词子集校验，
  repair 降级为「只出可靠翻译」（提交 `26861d4`）。
- **修复 `translation` 输出英文而非中文**（提交 `a427e01`，AI-211/AI-212）：
  - schema 字段描述携带 `explanationLanguage`/`sourceLanguage`；
  - `validated(against:)` 在双语请求下拦截 `translation` 与 `targetText` 完全相同。
- **默认模型定为 1.5B**（AI-411）：`OllamaDefaults.model` 单一来源，
  CLI/App 设置/设置页展示全部引用同一常量，消除默认值重复定义。
- **保存并恢复最近阅读页码**：新增 `ReadingPositionStore`（按文档路径存 UserDefaults），
  打开文档时定位到上次页码，翻页即保存，关闭时兜底保存。
- **EPUB 解析核心**（`EPUBCore`，无第三方依赖）：
  - 自研 ZIP 解包（系统 zlib）、container.xml/OPF 解析、spine 阅读顺序、导航文档跳过；
  - 章节 XHTML → 段落文本（XML 模式 + 实体解码 + 非规范文件的正则回退）；
  - 真实《挪威的森林》EPUB 实测：16 章、3169 段落、书名/作者正确。

## 真实模型基线（2026-09-02，Qwen 2.5 冒烟集 20 条）

### 1.5B（默认，`qwen2.5:1.5b-instruct`）

- 结构化成功率：**100%**（20/20），平均耗时 4.1 秒 —— **达标**（门槛 ≥95%）
- 全部翻译为正确中文；0.5B 全灭的类别（被动、文学、指代消解、非谓语）全部通过
- 语法点 10/20、短语 10/20，语法+短语共 50 条目（0.5B 仅 7 条目）

### 0.5B（`qwen2.5:0.5b-instruct`，可在设置中选用）

- 结构化成功率：**75%**（15/20），平均耗时 2.2 秒 —— 未达标
- 5 条失败：3 条英文照抄被 AI-212 正确拦截，2 条 JSON 解析失败
- 通过条目中仍有英文释义漏网（AI-212 只拦「与原文完全一致」，拦不住「同语言释义」）
- 长句翻译截断、复杂结构翻译质量差
- **结论：0.5B 不满足 MVP 门槛，仅适合低延迟场景**

数据：`Evaluation/results-{0.5b,1.5b}.jsonl`、`report-{0.5b,1.5b}.md`（均已 gitignore，未入库）

## 已定位但未修的缺陷

1. **改设置会读丢正在读的 PDF**（TODO `PDF-112`）：`AppShellView` 的 `.id` 绑定含 `modelName`，
   输入模型名时每敲一键都会重建 `ReaderView`。
   （已部分缓解：即使重建，重开时也会恢复上次页码。）
2. **英文释义漏网**：AI-212 只拦截翻译与原文完全相同；同语言释义（paraphrase）仍能通过校验。
3. 无障碍小项：学习记录删除仅 contextMenu；解释弹窗错误态仅靠红色。
4. 翻译/语法/短语的人工评分（`Evaluation/report-*.md` Manual scoring）尚未填写。

## 当前状态

- 项目路径：`JieJu.xcodeproj`
- 最低系统：macOS 14
- 外部依赖：无第三方依赖；本地 Swift Package 为仓库源码
- 当前功能：PDF Reader、Mock/Ollama 解句、保存与查看学习记录
- 默认模型：`qwen2.5:1.5b-instruct`（`OllamaDefaults.model`），0.5B 可选

## 下一步

1. 人工评分冒烟集输出，确认 1.5B 翻译/语法质量（`Evaluation/report-1.5b.md`）；
2. 修 `PDF-112`（改设置丢 PDF）；
3. 用户开启开发者模式（`sudo DevToolsSecurity -enable` + 重启）后跑 App/UI 测试；
4. `AI-403`：扩展到 100 条正式评测句（在模型定档后做，避免返工）。

## 最近验证

- 日期：2026-09-02
- JieJuLanguage：**33 项离线测试通过**
- **EPUB 解析核心：7 项测试实跑通过**（/tmp 探针包执行，fixture 为 minimal/messy/nocontainer）
- **真实《挪威的森林》EPUB 解析成功**（16 章、3169 段落）
- **App 模块整体类型检查通过**（`swiftc -typecheck`，含 EPUBCore；`#Preview` 宏除外）
- **App 模块 `-emit-module -enable-testing` 通过**（测试目标可访问 `@testable import JieJu`）
- 新增 `ReadingPositionStoreTests`（6 项）：类型检查通过，运行需开发者模式
- 上一轮提交 `ca53263` 中的 `OllamaReadingAI.defaultModel` 泛型引用
  在类型检查中被发现并修复为 `OllamaDefaults.model`（该错误此前无法编译验证）
- CLI 与 Ollama 端到端：默认模型 1.5B 实测输出「火车在六点离开。」；0.5B 批量 45 秒、1.5B 82 秒跑完 20 条
- App/UI 测试：**无法运行**，本机开发者模式关闭，Runner 卡在建立连接
- 基线提交：`fbdf02f chore: create macOS project foundation`
- 模块集成提交：`3529d0f feat: build parallel reader language and storage modules`
- 语言修复提交：`a427e01 fix: bind target language into Ollama JSON schema`
