# JieJu Language Evaluation

`smoke.jsonl` 是本地语言引擎的首批冒烟评测集。每行是一个独立请求，可由 `JieJuAILab batch` 运行。

`deep-syntax-smoke.jsonl` 是深入解析评测集，覆盖简单句、复合句、非谓语、倒装、省略和指代。
可将其中每行的请求字段交给 `JieJuAILab deep`；深度结果需额外检查句型、成分边界、
从句关系、修饰对象和整句理解是否准确。指代句允许模型明确指出歧义，不应强行给出唯一答案。

人工评审每项使用 0–2 分：

- `translationAccuracy`：翻译是否准确自然；
- `sentenceCoreAccuracy`：主干是否识别正确；
- `grammarAccuracy`：语法说明是否正确且不误导；
- `phraseValue`：短语是否值得学习；
- `hallucination`：0 表示无幻觉，1 表示轻微，2 表示严重；
- `jsonValid`：结构化输出是否可解析。

进入 App 的最低门槛：结构化成功率至少 95%，且普通句翻译与语法解释不存在系统性错误。
