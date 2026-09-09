# JieJu 隐私说明

JieJu 采用本地优先设计。应用可以完全使用本机 Ollama 工作；云端模型是用户主动配置的可选能力。

## 本地保存的数据

- 阅读进度、学习记录、生词与复习状态保存在 `~/Library/Application Support/JieJu/library.json`。
- 阅读器偏好和最近阅读使用 macOS `UserDefaults` 保存。最近阅读包含文件显示名、文档类型、最后
  位置、打开时间、回退路径和用于持续访问本地文件的 security-scoped bookmark；最多保存 12 条。
- OpenAI-compatible Provider 的 API Key 保存在 macOS 钥匙串，服务名为 `com.jieju.reader.ai`；它不会写入 JSON 数据库。
- 当前源码不包含产品分析、广告或第三方遥测 SDK。

操作系统、Xcode 调试器或用户自行安装的崩溃收集工具仍可能记录应用运行信息，这不属于 JieJu 主动上传的数据。

## 网络请求

### Ollama 模式

选中的目标文本、前后文、源语言和讲解语言发送到用户配置的 Ollama 地址。默认地址是本机服务。若用户把地址改为局域网或远程主机，请自行确认该主机的隐私策略。

### OpenAI-compatible 模式

只有在用户主动选择并配置该 Provider 后，解释请求才会发送至指定 Base URL。请求可能包含选中的单词或句子、当前句和有限的前后文，以及生成结构化讲解所需的提示词。数据如何存储和使用取决于该服务提供方。

打开文档、翻页、保存生词和本地复习本身不需要云端请求。书籍内嵌内容不应自行访问网络。

## 用户控制

- 可以随时切回 Ollama 或 Mock Provider，停止后续云端解释请求。
- 在设置中清空云端 API Key，可从钥匙串移除相应凭据；也可在“钥匙串访问”中搜索 `com.jieju.reader.ai`。
- 如需删除本地学习数据，请先退出 JieJu，并在确认无需备份后删除 `~/Library/Application Support/JieJu/library.json`。
- 应用偏好可通过删除 bundle identifier `com.jieju.reader` 对应的 macOS 偏好数据重置。
- 最近阅读中的单本记录也可以直接从阅读页菜单移除；移除不会删除原 PDF / EPUB 文件。

删除操作不可撤销。若学习记录仍有价值，请先复制 `library.json` 备份。

## 分享问题报告

提交 Issue、截图或 EPUB 兼容性样本前，请移除姓名、路径、API Key、私人批注和无权公开的书籍正文。项目维护者不会主动要求完整的受版权保护电子书。

本说明描述当前源码行为。若未来加入同步、遥测或新的云端数据流，必须先更新本文件并在产品中明确告知用户。
