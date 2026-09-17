# 发布流程

v0.0.1 提供 Apple Silicon macOS 开发预览 DMG，具体限制见 [发布说明](RELEASE-v0.0.1.md)。
正式签名、公证发布仍按下方清单验收，CI 与自动签名另行规划。

## 开发预览打包

```bash
xcodebuild build -project JieJu.xcodeproj -scheme JieJu -configuration Release \
  -derivedDataPath build/macos-v0.0.1 -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
bash scripts/package-macos-dmg.sh 0.0.1
```

产物位于 `build/releases/`（不提交 Git），通过 GitHub Release 附件分发并附 SHA-256。
ad-hoc 签名只用于开发预览，不能替代 Developer ID 与公证。

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

- [x] 提供 `scripts/build-{macos,windows}` 与 `package-{macos,windows}` 可重复 Release 构建入口；
      开发预览统一生成 ZIP 和 SHA-256，详见 [BUILDING.md](BUILDING.md)。
- [x] Windows Alpha ZIP 附带当前用户安装/卸载脚本、第三方归属摘要、包内说明和 SHA-256；
      `test-windows-package.ps1` 实际验证安装后启动、默认保留数据和显式清除数据。
- [ ] 使用项目所有者的 Developer ID 签名；不要在仓库保存证书或密码。
- [ ] 开启 Hardened Runtime，并检查 App Sandbox / entitlement 是否与实际文件访问一致。
- [ ] 向 Apple 提交公证并执行 stapling。
- [ ] 在干净的受支持 macOS 账户上验证首次启动和 Gatekeeper。
- [ ] 生成校验和并随安装包发布。

Windows 开发预览包由 `package-windows.ps1` 生成，包含自包含 .NET / Windows App SDK、当前用户
安装/卸载脚本、第三方归属摘要、许可说明、构建提交和校验和；目标机器仍需 WebView2 Runtime。
macOS 脚本默认关闭签名，公开发布时不得把未签名预览
冒充已完成 Developer ID 签名和 Apple 公证的正式包。

正式发布前必须补充稳定的签名、公证和升级策略；未经这些步骤的构建应明确标为开发预览，不建议普通用户绕过系统安全提示。

## 发布后

- [ ] 创建带注释的版本 tag，不改写已发布 tag。
- [ ] 发布安装包、校验和、变更摘要、系统要求和已知问题。
- [ ] 更新 README 的下载方式和支持版本。
- [ ] 验证安全报告入口与 Issue 模板可用。
- [ ] 记录发布验证结果和后续问题。
