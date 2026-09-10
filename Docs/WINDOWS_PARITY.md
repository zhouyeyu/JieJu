# Windows 与 macOS 功能对齐任务

按独立、可验证的小任务依次交付。基线为 `91222f2`，开发分支为 `codex/windows-development`。

## 1. 阅读与图形界面

- [x] `WIN-101` 原生侧栏：阅读、学习记录、生词本、随手温习、设置；切换页面保留阅读会话
- [x] `WIN-102` EPUB ZIP/XML 解析、manifest/spine、书名和语言、包内资源与大小限制
- [x] `WIN-103` 打开 EPUB、章节目录、前后章节、正文排版和原书 Ruby
- [x] `WIN-104` 四种主题、字号、行距、边距、注音显示与本地设置
- [x] `WIN-105` 最近阅读、重新打开与设备本地阅读位置

## 2. 解句与学习资料

- [x] `WIN-201` 选区清洗、前后语境、解句侧栏、取消与错误状态
- [ ] `WIN-202` Ollama 流式解句、结构校验、模型连接检查
- [ ] `WIN-203` 保存解释、学习记录详情、删除与回到原文
- [ ] `WIN-204` 独立词语解释、生词收藏、合并与详情
- [ ] `WIN-205` 识别卡、四档熟悉程度、每轮十张温和暂停、只追加复习日志

## 3. 完整阅读与高级功能

- [ ] `WIN-301` EPUB 分页、窗口/字体重排、稳定正文锚点；逐模块迁入 Shared/ReaderWeb
- [ ] `WIN-302` PDF.js 阅读、页码、选区、位置恢复与来源跳转
- [ ] `WIN-303` 深入句法分析与侧栏/弹窗解释方式
- [ ] `WIN-304` OpenAI-compatible Provider、SSE 与 Windows Credential Manager
- [ ] `WIN-305` 本地日语形态分析和自动假名注入
- [ ] `WIN-306` 固定 EPUB/PDF 的端到端 UI 回归、可访问性、发布包

## 每项验收

Windows build/test、Node 共享测试、涉及界面的真机检查。更新本清单及 TODO/PROGRESS/HANDOFF。
仅在对应验收通过后勾选；Windows 不具备的功能不得用演示数据冒充已实现。

`WIN-202` 的 NDJSON 流客户端、结构校验和连接检查已实现并由离线 HTTP Stub 覆盖；当前 Windows
主机尚未安装 Ollama，需完成真实模型推理与 GPU 利用率验证后再勾选。
