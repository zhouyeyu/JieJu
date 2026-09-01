# JieJu Language Evaluation

`smoke.jsonl` 是本地语言引擎的首批冒烟评测集。每行是一个独立请求，可由 `JieJuAILab batch` 运行。

人工评审每项使用 0–2 分：

- `translationAccuracy`：翻译是否准确自然；
- `sentenceCoreAccuracy`：主干是否识别正确；
- `grammarAccuracy`：语法说明是否正确且不误导；
- `phraseValue`：短语是否值得学习；
- `hallucination`：0 表示无幻觉，1 表示轻微，2 表示严重；
- `jsonValid`：结构化输出是否可解析。

进入 App 的最低门槛：结构化成功率至少 95%，且普通句翻译与语法解释不存在系统性错误。

