# 日语读音引擎评估

## 已采用方案

JieJu 的正文假名不能以小语言模型输出作为真值。首版使用 `JapaneseReadingProviding` 隔离读音来源，
内置词典只覆盖少量高频词，未知汉字保持原样。模型读音只出现在深入解释的“AI 参考”区域。

首个正式版本采用 [Mecab-Swift](https://github.com/shinjukunian/Mecab-Swift) + 内置 IPADic，并固定到
revision `1f096492e37fc05fc2e7304091f54889974c5368`。它直接提供 Swift Package、词典读音、词性、
原形和汉字注音区间；依赖在当前 Xcode/Swift 环境下通过上游 21 项测试。IPADic Bundle 约 51MB，
Debug App 当前约 136MB，发布构建需重新测量体积。

未采用 [Lindera](https://github.com/lindera/lindera) 或
[Sudachi](https://github.com/WorksApplications/Sudachi) 的主要原因是当前项目需要额外维护 Rust/C ABI
或进程桥接。它们仍是未来提升新词、姓名及分词质量的候选。Apple NaturalLanguage 可用于语言识别
和部分分词，但不提供可作为日语假名真值的公开读音词典。

## 接入门槛

- 完全离线，许可允许随开源 macOS App 分发；
- 返回表层形、原形、读音、词性和活用信息；
- 能将词典 token 稳定对齐回原文，不能用 HTML 作为持久化格式；
- 在 `japanese-reading-smoke.jsonl` 的常用词、活用、日期与熟字训上评测；
- 姓名和未知词允许“不注音”，不得静默猜测；
- 词典体积、首次加载时间和每千字耗时需单独记录。

`MeCabJapaneseReadingProvider` 是默认实现，并通过锁串行访问 tokenizer；`LocalJapaneseReadingProvider`
只在词典初始化失败时回退。EPUB 注入使用 DOM Text Node，不改写 HTML 字符串；已有 Ruby、脚本、
样式、标题和文本输入节点会跳过。同一章节中读音不唯一的表层词不会自动注音。

## 已知边界

- IPADic 较旧，新词、人名和部分专有名词可能缺失或切分不理想；
- 当前公开包装只暴露词性与词典原形，没有完整活用形名称；`isInflected` 通过表层形与原形比较；
- EPUB 的唯一读音保护按章节统计，跨章节同形异音不互相污染；
- 模型给出的读音只在“AI 参考”区域展示，不覆盖本地词典。

## 深入语法策略

1.5B 实测难以同时稳定生成句式、成分、助词、词形和读音，失败后的整次重试还会放大等待时间。
因此日语深入解析采用本地确定性路径：MeCab 负责 token、词性和原形，规则层生成助词功能、
句式骨架和常见谓语活用，通常在几十毫秒内完成。Ollama 继续负责上方自然语言翻译，但不阻塞
日语语法卡片。后续扩充规则时应新增明确测试，不能重新以模型输出替代助词和词形真值。
