namespace JieJu.Domain;

public static class JapaneseGrammarAnalyzer
{
    private static readonly IReadOnlyDictionary<string, string> ParticleExplanations = new Dictionary<string, string>
    {
        ["は"] = "提示主题，说明后面的判断或动作围绕此前项展开；它强调话题，不等同于单纯标记主语的「が」。",
        ["が"] = "标记主语或新信息，指出是谁／什么执行动作或处于某种状态。",
        ["を"] = "标记动作直接作用的对象，连接宾语与后面的动词。",
        ["に"] = "标记到达点、存在位置、具体时间或动作指向的对象，需结合谓语判断。",
        ["で"] = "标记动作发生的场所、采用的手段或原因，需结合前项名词与谓语判断。",
        ["の"] = "连接两个名词，使前项限定后项，可表示所属、种类、内容等关系。",
        ["と"] = "标记共同参与者、引用内容或并列对象，具体作用由后面的谓语决定。",
        ["も"] = "表示“也／连……也”，在已有话题或同类项目上追加信息。",
        ["へ"] = "标记移动方向，侧重朝向；「に」通常更侧重明确到达点。",
        ["から"] = "标记时间、空间或原因的起点。",
        ["まで"] = "标记时间或空间的终点、范围上限。"
    };

    public static DeepAnalysis LocalAnalysis(ExplanationRequest request, IJapaneseMorphology morphology)
    {
        var tokens = morphology.Tokenize(request.TargetText);
        var grammar = GrammarPoints(tokens, request.TargetText);
        var (pattern, components) = Structure(tokens);
        var words = tokens.Where(token => ContainsHan(token.Surface) && token.PartOfSpeech is not ("particle" or "symbol"))
            .Take(12).Select(token => new JapaneseWord(token.Surface, token.DictionaryForm, token.Reading,
                token.IsInflected ? $"活用形（原形：{token.DictionaryForm}）" : "基本形／无活用",
                GrammaticalFunction(token.PartOfSpeech))).ToArray();
        return new DeepAnalysis
        {
            SentenceType = "日语句",
            SentencePattern = string.IsNullOrEmpty(pattern) ? "单一谓语结构" : pattern,
            Components = components,
            Clauses = [],
            GrammarPoints = grammar,
            Interpretation = "本地解析展示句式、助词和谓语功能；句意请结合上方翻译理解。",
            JapaneseWords = words
        };
    }

    private static GrammarPoint[] GrammarPoints(IReadOnlyList<JapaneseToken> tokens, string text)
    {
        var result = new List<GrammarPoint>();
        for (var index = 0; index < tokens.Count; index++)
        {
            if (!IsSemanticParticle(index, tokens)) continue;
            var token = tokens[index];
            var explanation = IsAgeConnectorDe(index, tokens)
                ? "这里不是表示场所或手段的格助词，而是名词判断「十八だ」的连接形式「十八で」，相当于“十八岁，并且……”。"
                : ParticleExplanations.GetValueOrDefault(token.Surface);
            if (explanation is not null && result.All(item => item.Text != token.Surface)) result.Add(new GrammarPoint(token.Surface, explanation));
        }
        var constructions = new (string Form, string Explanation)[]
        {
            ("でいます", "动词て形（浊音形式「で」）＋「いる」的礼貌形式，依动词语义表示动作正在进行、反复持续或结果状态。"),
            ("ています", "「て形＋いる」的礼貌形式，依动词语义表示动作正在进行、反复持续或结果状态。"),
            ("ている", "「て形＋いる」表示动作正在进行、反复持续或动作完成后的结果状态。"),
            ("ません", "「ます」的否定形式，使谓语成为礼貌体现在／将来否定。"),
            ("ました", "「ます」的过去形式，使谓语成为礼貌体过去／完成表达。"),
            ("たばかり", "「动词た形＋ばかり」表示动作刚刚完成；后接「だった」时，整句以过去视角说明当时处于“刚做完”的状态。"),
            ("たい", "接在动词连用形后表示说话者想做某事。")
        };
        foreach (var item in constructions.Where(item => text.Contains(item.Form, StringComparison.Ordinal)))
        {
            if (result.Count >= 6) break;
            result.Add(new GrammarPoint(item.Form, item.Explanation));
        }
        return result.ToArray();
    }

    private static (string Pattern, SentenceComponent[] Components) Structure(IReadOnlyList<JapaneseToken> tokens)
    {
        var labels = new Dictionary<string, string> { ["は"] = "主题", ["が"] = "主语", ["を"] = "宾语", ["に"] = "目标／时间", ["で"] = "场所／手段", ["の"] = "连体修饰", ["と"] = "引用／共同者", ["も"] = "追加主题", ["へ"] = "方向", ["から"] = "起点", ["まで"] = "终点" };
        var parts = new List<string>();
        var components = new List<SentenceComponent>();
        var consumed = new HashSet<int>();
        for (var index = 1; index < tokens.Count; index++)
        {
            if (!IsSemanticParticle(index, tokens) || !labels.TryGetValue(tokens[index].Surface, out var role) || consumed.Contains(index - 1)) continue;
            if (IsAgeConnectorDe(index, tokens)) role = "年龄状态／连接";
            var start = PhraseStart(index - 1, tokens);
            var surface = string.Concat(tokens.Skip(start).Take(index - start + 1).Select(token => token.Surface));
            parts.Add($"{role}({surface})");
            components.Add(new SentenceComponent(surface, role,
                role == "年龄状态／连接" ? $"「{surface}」连接年龄判断与后续叙述，不表示动作场所或手段。" : $"由助词「{tokens[index].Surface}」标记的{role}成分。"));
            for (var consumedIndex = start; consumedIndex <= index; consumedIndex++) consumed.Add(consumedIndex);
        }
        var verbIndex = Enumerable.Range(0, tokens.Count).FirstOrDefault(index => tokens[index].PartOfSpeech == "verb", -1);
        if (verbIndex >= 0)
        {
            var predicate = string.Concat(tokens.Skip(verbIndex).Select(token => token.Surface));
            parts.Add($"谓语({predicate})");
            components.Add(new SentenceComponent(predicate, "谓语", "句子的核心述语，表达动作、变化或状态。"));
        }
        return (string.Join("＋", parts), components.Take(8).ToArray());
    }

    private static bool IsSemanticParticle(int index, IReadOnlyList<JapaneseToken> tokens) =>
        tokens[index].PartOfSpeech == "particle" && !(tokens[index].Surface == "で" && index > 0 && tokens[index - 1].PartOfSpeech == "verb");

    private static int PhraseStart(int end, IReadOnlyList<JapaneseToken> tokens)
    {
        var start = end;
        while (start > 0 && tokens[start - 1].PartOfSpeech is not ("particle" or "symbol" or "verb")) start--;
        return start;
    }

    private static bool IsAgeConnectorDe(int index, IReadOnlyList<JapaneseToken> tokens)
    {
        if (tokens[index].Surface != "で" || index == 0) return false;
        var phrase = string.Concat(tokens.Skip(PhraseStart(index - 1, tokens)).Take(index - PhraseStart(index - 1, tokens)).Select(token => token.Surface));
        const string ageCharacters = "0123456789〇零一二三四五六七八九十百千歳";
        return phrase.Length > 0 && phrase.All(ageCharacters.Contains);
    }

    private static string GrammaticalFunction(string partOfSpeech) => partOfSpeech switch
    {
        "noun" => "名词性成分", "verb" => "谓语动词", "adjective" => "形容词性成分", "adverb" => "副词性修饰语", "prefix" => "接头成分", _ => "句中词语"
    };

    private static bool ContainsHan(string value) => value.Any(character => character is >= '\u3400' and <= '\u9fff');
}
