# JieJu Progress

## 当前阶段

并行模块首轮集成。

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

## 当前状态

- 项目路径：`JieJu.xcodeproj`
- 最低系统：macOS 14
- 外部依赖：无第三方依赖；本地 Swift Package 为仓库源码
- 当前功能：PDF Reader、Mock/Ollama 解句、保存与查看学习记录

## 下一步

恢复本机 XCTest Runner，加入固定测试 PDF 和端到端 UI 测试；随后运行真实 Qwen 0.5B 冒烟评测。

## 最近验证

- 日期：2026-09-01
- App `xcodebuild build`：通过
- JieJuLanguage：24 项离线测试通过
- App 单元测试：集成前 6 项通过；新增 Persistence 测试已编译
- App/UI 测试：当前机器的 Runner 卡在启动测试会话，待恢复后重跑
- 基线提交：`fbdf02f chore: create macOS project foundation`
- 模块集成提交：`3529d0f feat: build parallel reader language and storage modules`
