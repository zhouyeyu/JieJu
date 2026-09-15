# 参与 JieJu

[English](CONTRIBUTING.en.md) · 简体中文

感谢你愿意帮助 JieJu。项目欢迎代码、文档、测试、模型评测案例，以及不含版权或隐私风险的最小复现样本。

## 开始之前

1. 阅读 [PRODUCT.md](PRODUCT.md)、[ARCHITECTURE.md](ARCHITECTURE.md) 和 [TODO.md](TODO.md)。
2. 多 Agent 或自动化开发还应遵守 [AGENTS.md](AGENTS.md)，并查看 [HANDOFF.md](HANDOFF.md)。
3. 先搜索已有 Issue；较大的产品或架构变化应先创建讨论 Issue。
4. 一个 PR 只解决一个边界明确的问题，避免混入无关格式化或重构。
5. 修改公开项目介绍、能力矩阵或安装说明时，同时更新 `README.md` 与 `README.en.md`，确保两种语言表达同一事实；不要添加无法验证的性能、兼容性或完成度声明。

## 本地环境

- macOS 14+
- Xcode 16+ / Swift 6
- Node.js 20+
- Ollama（仅本地模型集成测试或手工验证需要）

打开 `JieJu.xcodeproj` 可运行 App。完整测试命令为：

```bash
./scripts/test-all.sh
```

UI 测试需要开启 macOS 开发者模式；无法运行时，请在 PR 中写明已运行的测试、阻塞原因和人工验证步骤。

## 分支与提交

建议使用 `feature/<topic>`、`fix/<topic>` 或 `docs/<topic>`。提交采用简洁的 Conventional Commits 风格，例如：

```text
feat: add EPUB theme preview
fix: preserve reading position on reopen
test: cover malformed model response
docs: clarify local data storage
```

请勿改写他人的提交历史，也不要提交真实书籍、API Key、个人路径、模型产物或 Xcode 构建目录。

## 代码边界

- SwiftUI 视图不直接调用网络、Ollama 或持久化实现。
- AI 能力通过 `ReadingAI` 协议访问；自动测试优先使用确定性 Mock。
- `Shared/Contracts/v1` 是已发布字段的稳定事实来源；破坏性变化应新建版本。
- 新增业务逻辑需要单元测试，关键阅读流程应考虑 UI 测试。
- 改动 EPUB 脚本、AI DTO、持久化格式或跨平台消息前，先读 [Docs/CROSS_PLATFORM.md](Docs/CROSS_PLATFORM.md)。

## 模型与 EPUB 复现材料

- 模型错误案例应包含输入语言、期望解释、模型名与必要上下文，不要包含整章文本。
- EPUB 问题优先提供可自由再分发的最小样本；不能公开原文件时，请描述 OPF、CSS 和 XHTML 的相关结构。
- 截图必须隐藏书名、用户名、文件路径、API Key 和受版权保护的大段正文。

## Pull Request 检查

- [ ] 改动有明确的用户价值和验收标准。
- [ ] 相关测试已添加并通过。
- [ ] `./scripts/test-all.sh` 已运行，或已说明环境阻塞。
- [ ] 文档、TODO 和架构决策按需更新。
- [ ] 没有提交密钥、私有文档或无关改动。
- [ ] 已说明 AI 辅助生成内容中经过人工验证的部分。

使用 AI 工具并不会降低贡献价值，但提交者仍对代码、版权、测试和安全性负责。请阅读并理解准备合并的每一处改动。

## 许可证

提交贡献即表示你同意按本项目的 [Apache License 2.0](LICENSE) 提供该贡献。若你无权按此许可证提供某段代码或素材，请勿提交。
