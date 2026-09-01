# JieJu TODO

任务按可并行模块组织。`[x]` 表示源码已实现并进入工程；真实模型质量和人工 UI 验收单独标记。

## Track A：语言引擎与评测

- [x] `AI-001`～`AI-006` 领域模型、协议、校验与 Codable 测试
- [x] `AI-101`～`AI-107` Mock、HTTP 抽象、Ollama 状态与错误测试
- [x] `AI-108` Ollama 服务、模型缺失与可用状态诊断
- [x] `AI-201`～`AI-208` Qwen 0.5B Prompt、严格 JSON、一次重试与解析测试
- [x] `AI-209` JSON 输入边界、temperature 0 与输出长度限制
- [x] `AI-210` 目标句引用一致性校验、上下文串线拦截与语义修复重试
- [x] `AI-211` JSON Schema 字段携带目标语言，修复 `translation` 输出英文而非中文
      （字段名本身对 0.5B/1.5B 构成词汇诱导，需连同字段描述一起处理）
- [x] `AI-212` 校验拦截 `translation` 与 `targetText` 完全相同
- [x] `AI-301`～`AI-309` Swift CLI、单句/上下文/JSON/raw/model/url
- [x] `AI-401`～`AI-402` JSONL 格式与 20 条冒烟评测句
- [ ] `AI-403` 扩展到 100 条正式评测句
- [x] `AI-404` 冒烟集覆盖主要语法与上下文类别
- [x] `AI-405`～`AI-408` 批量执行、结果、报告和人工评分标准
- [x] `AI-409` 运行有/无上下文真实模型对照
- [x] `AI-410` 记录 Qwen 0.5B 实测能力边界
- [x] `AI-411` 0.5B 与 1.5B 双模型批量对照，决定默认模型（1.5B，提交见 `a427e01` 之后）

> `AI-211`/`AI-212` 已于 2026-09-02 修复（提交 `a427e01`），
> `AI-409`～`AI-411` 的批量评测已产出有效数据
> （`Evaluation/results-{0.5b,1.5b}.jsonl` 与 `report-*.md`，均已 gitignore）。
> 剩余工作：人工评分 `Evaluation/report-*.md` 的 Manual scoring 表。

## Track B：PDF 阅读器

- [x] `PDF-001`～`PDF-008` 文档状态、文件面板、PDFKit 显示、页码与关闭
- [ ] `PDF-009` 固定测试 PDF 与自动打开 UI 测试
- [x] `PDF-101`～`PDF-110` 选区、文本清理、前后句、锚点、弹窗与状态
- [x] `PDF-111` 文本清理和上下文单元测试
- [ ] 人工验证跨页选择与不同 PDF 排版
- [ ] 保存并恢复最近阅读页码
- [ ] `PDF-112` 修 `AppShellView` 的 `.id` 绑定含 `modelName`，
      导致设置页输入模型名时 `ReaderView` 被重建、丢失已打开的 PDF 与页码

## Track C：JSON 本地存储

- [x] `DATA-001`～`DATA-010` 版本化模型、原子写入、损坏恢复、CRUD、去重与测试
- [ ] 增加未来 schema version 的迁移策略
- [ ] 为文档生成内容指纹

## Track D：集成与学习闭环

- [x] `INT-001`～`INT-008` 可配置 Provider、设置、解释状态、取消、保存、去重、列表和删除
- [x] `INT-011` 设置页一键检查 Ollama 与默认模型
- [ ] `INT-009` 重新解释已保存句子
- [ ] `INT-010` 完整端到端 UI 测试
- [ ] 学习记录详情页
- [ ] 保存成功和失败的界面反馈
- [ ] 学习记录删除补键盘/VoiceOver 可达路径（现仅 contextMenu）
- [ ] 解释弹窗错误态补图标或文字标签（现仅靠红色传达）

## 发布前关卡

- [x] App 与本地 Swift Package 共同构建
- [x] 语言引擎 33 项离线测试通过
- [x] 本机已安装 Ollama 与默认模型（0.5B、1.5B 均已拉取）
- [ ] 开启开发者模式（`sudo DevToolsSecurity -enable`，需用户执行并重启）
- [ ] 恢复当前机器的 macOS XCTest Runner 并重跑 App/UI 测试
- [x] 0.5B/1.5B 双模型冒烟评测（1.5B 定为默认模型，见 DECISIONS.md）
- [ ] 人工评分冒烟集输出（`Evaluation/report-*.md` Manual scoring）
- [ ] 在 M1 8GB 和至少一台更高配置 Mac 上记录延迟
- [ ] Xcode 人工运行与完整流程验收

## Later

- [ ] EPUB
- [ ] OCR
- [ ] 1.5B 质量回退建议
- [ ] 更多模型 Provider
- [ ] 数据导出与同步
