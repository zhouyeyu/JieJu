# JieJu Agent Guide

本文件是 Codex、Cursor、WorkBuddy 及其他开发 Agent 的共同工作协议。

## 项目目标

JieJu 是一个 macOS 原生、以语言学习为目标的 PDF/EPUB 阅读器。核心流程是：

> 打开文档 → 阅读 → 选中内容 → 获得分层解释 → 保存重点表达 → 复习

MVP 优先验证 PDF 阅读与“划线解句”闭环。EPUB、OCR、云同步和完整复习系统不属于第一阶段。

## 开始任务前

每个 Agent 必须先阅读：

1. `PRODUCT.md`
2. `ARCHITECTURE.md`
3. `TODO.md`
4. `PROGRESS.md`
5. `DECISIONS.md`
6. `HANDOFF.md`

然后检查当前分支、最近提交和未提交改动。用户已有改动不得擅自覆盖、回退或删除。

## 工作规则

1. 一次只完成一个边界明确、可独立验证的小任务。
2. 不修改与当前任务无关的代码，不顺手进行大规模重构。
3. SwiftUI 视图不直接调用 Ollama、网络或持久化实现。
4. AI 能力必须通过 `ReadingAI` 协议访问；自动测试默认使用可预测的 Mock。
5. 新增业务逻辑必须有单元测试；关键用户路径应有 UI 测试。
6. 完成前运行 `./scripts/test-all.sh`。
7. 测试失败时不得宣称完成；记录无法解决的阻塞及复现方法。
8. 架构或产品边界发生变化时，更新 `DECISIONS.md`。
9. 每项任务结束时更新 `TODO.md`、`PROGRESS.md` 和 `HANDOFF.md`。
10. 仅在工作树内容清晰、测试通过时创建小而明确的 Git commit。
11. 未经用户明确授权，不推送远程仓库、不合并分支、不改写 Git 历史。

## 多 Agent 协作

- 同一工作区同一时间只允许一个 Agent 写入。
- 并行任务必须使用独立分支或独立 worktree，且任务文件范围不得重叠。
- 接手者以仓库文件和 Git 历史为事实来源，不依赖上一工具的聊天记录。
- Review Agent 默认只报告问题；未经任务授权，不进行范围外重构。
- 交接必须写入 `HANDOFF.md`，包含当前分支、提交、测试结果、已知问题和下一步。

## 完成定义

任务只有在以下条件全部满足时才完成：

- 验收标准已满足；
- 项目能够构建；
- 相关自动测试通过；
- 文档和交接记录已更新；
- 没有混入无关改动；
- 已明确下一步或剩余问题。

## 提交格式

使用简洁的 Conventional Commits 风格：

- `chore: create macOS project foundation`
- `feat: display selected PDF document`
- `test: cover explanation response parsing`
- `fix: preserve reading position on reopen`
- `docs: record local model decision`

