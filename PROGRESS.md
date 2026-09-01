# JieJu Progress

## 当前阶段

并行模块首轮集成。Track A 语言引擎在途：目标句一致性校验已落地并做检查点提交，
但**真实模型输出质量尚未达标**，见「已定位但未修的缺陷」。

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

## 已定位但未修的缺陷

1. **translation 不出中文**（严重）：schema 字段描述不含目标语言，
   且字段名 `translation` 对 0.5B/1.5B 构成强词汇诱导，实测输出英文而非中文；
   同请求下 `meaning` 字段却能正确输出中文。详见 `HANDOFF.md`。
2. **校验拦不住「翻译等于原文」**：`translation == targetText` 目前能通过校验。
3. **改设置会读丢正在读的 PDF**：`AppShellView` 的 `.id` 绑定含 `modelName`，
   输入模型名时每敲一键都会重建 `ReaderView`。

## 当前状态

- 项目路径：`JieJu.xcodeproj`
- 最低系统：macOS 14
- 外部依赖：无第三方依赖；本地 Swift Package 为仓库源码
- 当前功能：PDF Reader、Mock/Ollama 解句、保存与查看学习记录
- 本地模型：Ollama 已装可达，已拉取 `qwen2.5:0.5b-instruct`（默认）与 `qwen2.5:1.5b-instruct`
- 实测延迟：0.5B 约 1.3～2.6 秒，1.5B 约 6.8 秒

## 下一步

先修 schema 的语言绑定与 translation 校验，再跑 0.5B / 1.5B 双模型批量对照。
**当前状态下批量评测会得到废数据，不要提前跑。**

## 最近验证

- 日期：2026-09-02
- JieJuLanguage：**30 项离线测试通过**
- CLI 与 Ollama 端到端：跑通，单句 1.3～6.8 秒
- App `xcodebuild build`：上一任记载为通过；本次**未能独立复验**
  （本工具解析本地 SwiftPM 依赖时被 `sandbox_exec` 拒绝，属环境限制）
- App/UI 测试：**无法运行**，本机开发者模式关闭，Runner 卡在建立连接
- 基线提交：`fbdf02f chore: create macOS project foundation`
- 模块集成提交：`3529d0f feat: build parallel reader language and storage modules`
- 检查点提交：`26861d4 feat: enforce target-only output with structured schema`
