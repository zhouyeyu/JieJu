# 日语读音引擎评估

## 结论

JieJu 的正文假名不能以小语言模型输出作为真值。首版使用 `JapaneseReadingProviding` 隔离读音来源，
内置词典只覆盖少量高频词，未知汉字保持原样。模型读音只出现在深入解释的“AI 参考”区域。

正式版本优先评估 Sudachi（词典与多粒度分词质量较好）和 MeCab + UniDic。两者都不是原生 Swift：
Sudachi 的 Rust/Java/Python 实现需要桥接，MeCab 需要 C/C++ 封装；完整词典会显著增加 App 体积。
Apple NaturalLanguage 可用于语言识别和部分分词，但不提供可作为日语假名真值的公开读音词典。

## 接入门槛

- 完全离线，许可允许随开源 macOS App 分发；
- 返回表层形、原形、读音、词性和活用信息；
- 能将词典 token 稳定对齐回原文，不能用 HTML 作为持久化格式；
- 在 `japanese-reading-smoke.jsonl` 的常用词、活用、日期与熟字训上评测；
- 姓名和未知词允许“不注音”，不得静默猜测；
- 词典体积、首次加载时间和每千字耗时需单独记录。

当前 `LocalJapaneseReadingProvider` 是接口验证实现，不是完整形态分析器。后续替换 Provider 时，
SwiftUI Ruby 组件、设置和 AI 解句接口不需要重写。
