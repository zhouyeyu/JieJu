# JieJu

JieJu 是一个面向 macOS 的语言学习型 PDF/EPUB 阅读器。项目目前处于工程基础阶段，MVP 优先实现 PDF 阅读、划线解句和学习内容沉淀。

## 开始开发

1. 阅读 `AGENTS.md`、`PRODUCT.md` 和 `ARCHITECTURE.md`。
2. 使用 Xcode 打开 `JieJu.xcodeproj`。
3. 选择 `JieJu` Scheme 运行应用。
4. 在终端运行 `./scripts/test-all.sh` 执行自动测试。

任务状态见 `TODO.md`，最近进度见 `PROGRESS.md`，跨 Agent 交接见 `HANDOFF.md`。

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
