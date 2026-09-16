# 构建与打包 / Build and package

仓库提供可重复的命令行入口，产物统一写入未纳入 Git 的 `artifacts/`。脚本不会下载 Ollama 模型，
也不会调用任何云端 AI。第一次还原依赖可能访问 NuGet 或 Swift Package 源；依赖已缓存时可使用
Windows 的 `-NoRestore` 避免再次还原。

The repository provides repeatable command-line entry points. All outputs are written to the Git-ignored
`artifacts/` directory. These scripts do not download Ollama models or call cloud AI services.

## Windows

要求 Windows 10 1809 或更高版本、PowerShell 和 `Apps/Windows/global.json` 指定的 .NET SDK。
构建出的应用包含 .NET 和 Windows App SDK 运行时；目标机器仍需 Microsoft Edge WebView2 Runtime。

```powershell
# 生成可直接运行的 Release 文件夹
.\scripts\build-windows.ps1

# 生成 ZIP 和对应 SHA-256 文件
.\scripts\package-windows.ps1 -Version 0.1.0-alpha

# 验证校验和、包内容、安装、启动、卸载和用户数据策略
.\scripts\test-windows-package.ps1 -Version 0.1.0-alpha
```

可运行目录位于 `artifacts/windows/win-x64/JieJu/`，压缩包位于 `artifacts/packages/`。首次成功还原
依赖后，可追加 `-NoRestore`；若已经运行过构建脚本，打包时可用 `-SkipBuild`。

The runnable folder is created at `artifacts/windows/win-x64/JieJu/`, and ZIP/checksum files are created
under `artifacts/packages/`. Use `-NoRestore` after dependencies are cached or `-SkipBuild` to package an
existing build.

打包脚本会在 ZIP 内创建单独的 `JieJu` 文件夹，并使用独立暂存目录，只收集发布文件；即使曾从发布目录运行应用，也不会把 WebView2 用户数据或缓存写入 ZIP。每次正常构建会先清理仓库 `artifacts/` 下对应输出目录，避免旧版本文件残留。解压后既可直接运行，也可执行以下命令安装到当前用户的 `%LOCALAPPDATA%\Programs\JieJu` 并创建开始菜单快捷方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

安装目录中的 `uninstall.ps1` 会删除程序与快捷方式并保留 `%LOCALAPPDATA%\JieJu` 阅读数据；明确追加
`-RemoveUserData` 才会删除这些数据。WebView2 数据也位于该用户数据目录，不会污染或锁住程序目录。

The ZIP contains one top-level `JieJu` folder. Packaging uses an isolated staging directory so WebView2
user data created by local smoke tests cannot enter the archive. Run `install.ps1` to install for the current
user and create a Start menu shortcut. The installed `uninstall.ps1` keeps reading data under
`%LOCALAPPDATA%\JieJu` unless `-RemoveUserData` is explicitly supplied.

## macOS

要求 macOS 14 或更高版本和 Xcode 16。以下脚本生成未签名开发预览，适合本机测试和审阅：

```bash
# 生成 JieJu.app
./scripts/build-macos.sh

# 重新构建并生成 ZIP 和 SHA-256
./scripts/package-macos.sh 0.1.0-alpha
```

应用位于 `artifacts/macos/JieJu.app`，压缩包位于 `artifacts/packages/`。公开发布仍需使用项目所有者的
Developer ID 完成签名、公证和 stapling；脚本不会读取或保存证书。

These commands produce an unsigned development preview. A public macOS release still requires Developer ID
signing, notarization, and stapling as described in [RELEASE.md](RELEASE.md).

## 校验下载 / Verify a package

Windows：

```powershell
Get-FileHash .\artifacts\packages\JieJu-Windows-x64-0.1.0-alpha.zip -Algorithm SHA256
```

macOS：

```bash
shasum -a 256 artifacts/packages/JieJu-macOS-0.1.0-alpha.zip
```

输出应与同名 `.sha256` 文件一致。开发预览包不会包含用户书籍、学习记录、API Key 或 Ollama 模型。
