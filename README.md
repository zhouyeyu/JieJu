# JieJu

JieJu 是一个面向 macOS 的语言学习型 PDF/EPUB 阅读器。项目目前处于工程基础阶段，MVP 优先实现 PDF 阅读、划线解句和学习内容沉淀。

解句结果中的重点表达、日语词形以及直接划选的单词可以收藏到独立生词本；重复词条会合并多个
来源语境。每个新生词会生成识别卡，“随手温习”会在合适的时候让词语再次出现；它不设提醒、
红点、连续打卡或必须清空的任务。每轮默认看 10 张，也可以随时停下回到阅读。

## 开始开发

1. 阅读 `AGENTS.md`、`PRODUCT.md` 和 `ARCHITECTURE.md`。
2. 使用 Xcode 打开 `JieJu.xcodeproj`。
3. 选择 `JieJu` Scheme 运行应用。
4. 在终端运行 `./scripts/test-all.sh` 执行自动测试。

任务状态见 `TODO.md`，最近进度见 `PROGRESS.md`，跨 Agent 交接见 `HANDOFF.md`。

跨平台规范位于 `Shared/Contracts`，EPUB Web 共享层位于 `Shared/ReaderWeb`，Windows 接入边界位于
`Apps/Windows`。当前 macOS 工程暂不搬迁；后续步骤见 `Docs/CROSS_PLATFORM.md`。

## 推理服务

默认使用本机 Ollama。在 App 的“设置 → 解释服务”中也可以选择“云端 API（OpenAI 兼容）”，
填写 API 版本根地址、API Key 和模型名称后检查连接。云端模式会发送选中句及前后文；API Key
只保存在 macOS 系统钥匙串，不写入项目配置或学习记录。

## 本地语言实验

启动 Ollama 并安装 `qwen2.5:0.5b-instruct` 后：

```bash
swift run --package-path Packages/JieJuLanguage JieJuAILab explain \
  --text "Although she was tired, she continued working." \
  --before "It was already midnight." \
  --after "The report was due the next morning."
```

观察流式解句各阶段耗时：

```bash
swift run --package-path Packages/JieJuLanguage JieJuAILab stream \
  --text "Although she was tired, she continued working."
```

批量运行冒烟评测：

```bash
swift run --package-path Packages/JieJuLanguage JieJuAILab batch \
  --input Evaluation/smoke.jsonl \
  --output Evaluation/results.jsonl \
  --report Evaluation/report.md
```
