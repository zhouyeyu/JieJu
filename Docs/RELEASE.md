# 发布流程

JieJu 当前尚未提供公开安装包。本清单用于未来手工发布，CI 与自动签名另行规划。

## 版本策略

- 使用语义化版本。Alpha 阶段允许 `0.x.y` 快速迭代，但持久化和公开契约仍需兼容。
- `MARKETING_VERSION`、更新日志标题、Git tag 和 Release 名称保持一致。
- 破坏 `Shared/Contracts/v1` 的变化必须创建新版本，不能原地改写。

## 发布前

- [ ] 明确本次范围，完成对应 TODO 和验收标准。
- [ ] 检查 `git status`，确认没有私有书籍、密钥、个人路径或无关文件。
- [ ] 运行 `./scripts/test-all.sh`，保存完整结果。
- [ ] 用一份自编 PDF 和一份可公开 EPUB 手工验证打开、翻页、选择、解释、保存、重启恢复和复习。
- [ ] 分别检查浅色、深色和护眼主题，以及假名注音开关。
- [ ] 验证 Ollama 离线流程；如发布云端 Provider，验证 Keychain 保存与清空。
- [ ] 检查依赖许可证、`NOTICE`、[PRIVACY.md](../PRIVACY.md) 和 [SECURITY.md](../SECURITY.md)。
- [ ] 将 `CHANGELOG.md` 的 Unreleased 内容整理进目标版本。

## 构建与分发

- [ ] 使用 Release 配置构建归档。
- [ ] 使用项目所有者的 Developer ID 签名；不要在仓库保存证书或密码。
- [ ] 开启 Hardened Runtime，并检查 App Sandbox / entitlement 是否与实际文件访问一致。
- [ ] 向 Apple 提交公证并执行 stapling。
- [ ] 在干净的受支持 macOS 账户上验证首次启动和 Gatekeeper。
- [ ] 生成校验和并随安装包发布。

正式发布前必须补充稳定的签名、公证和升级策略；未经这些步骤的构建应明确标为开发预览，不建议普通用户绕过系统安全提示。

## 发布后

- [ ] 创建带注释的版本 tag，不改写已发布 tag。
- [ ] 发布安装包、校验和、变更摘要、系统要求和已知问题。
- [ ] 更新 README 的下载方式和支持版本。
- [ ] 验证安全报告入口与 Issue 模板可用。
- [ ] 记录发布验证结果和后续问题。
