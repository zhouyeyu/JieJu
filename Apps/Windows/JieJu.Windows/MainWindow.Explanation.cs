using System.Text.Json;
using JieJu.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace JieJu.Windows;

public sealed partial class MainWindow
{
    private ExplanationRequest? selectionRequest;
    private Explanation? completedExplanation;
    private WordExplanation? completedWordExplanation;
    private string selectionSentence = "";
    private SelectionKind selectionKind = SelectionKind.Ambiguous;
    private SelectionBoundarySuggestion? boundarySuggestion;
    private EpubLocator? selectionLocator;
    private CancellationTokenSource? explanationCancellation;

    private void HandleSelection(JsonElement payload)
    {
        var target = payload.TryGetProperty("targetText", out var value) ? ExplanationValidation.Clean(value.GetString()) : "";
        explanationCancellation?.Cancel();
        if (target.Length == 0) return;
        string? Read(string name) => payload.TryGetProperty(name, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() : null;
        selectionRequest = ExplanationValidation.Normalize(new ExplanationRequest
        {
            TargetText = target, PrecedingContext = Read("precedingContext"), FollowingContext = Read("followingContext"),
            SourceLanguage = book?.Language ?? "Auto", ExplanationLanguage = device.Settings.ExplanationLanguage
        });
        completedExplanation = null;
        completedWordExplanation = null;
        selectionLocator = ReadLocator(payload);
        SelectedText.Text = selectionRequest.TargetText;
        UpdateSelectedFurigana();
        selectionSentence = Read("containingSentence") is { Length: > 0 } sentence ? ExplanationValidation.Clean(sentence) : target;
        selectionKind = SelectionClassifier.Classify(target, selectionRequest.SourceLanguage);
        boundarySuggestion = SelectionClassifier.SuggestBoundary(target, selectionSentence, selectionRequest.SourceLanguage, japaneseMorphology);
        SelectionContext.Text = selectionSentence != target ? "所在句：" + selectionSentence : "";
        ExplainButton.Content = boundarySuggestion is null ? SelectionClassifier.ActionTitle(selectionKind) : $"查“{boundarySuggestion.SuggestedText}”";
        ExplainWordButton.Content = SelectionClassifier.IsLexical(selectionKind) ? "按句子解释" : "按词语解释";
        BoundarySuggestionPanel.Visibility = boundarySuggestion is null ? Visibility.Collapsed : Visibility.Visible;
        BoundarySuggestionText.Text = boundarySuggestion is null ? "" : $"选区可能不完整，建议按“{boundarySuggestion.SuggestedText}”解释。";
        ExplanationContent.Children.Clear(); ExplanationStatus.Text = "准备好后，点击“解释这段”。";
        DeepAnalysisContent.Children.Clear(); AnalyzeDeepButton.Visibility = DeepAnalysisStatus.Visibility = Visibility.Collapsed;
        SaveExplanationButton.Visibility = Visibility.Collapsed; SaveExplanationButton.IsEnabled = false;
        SaveVocabularyButton.Visibility = Visibility.Collapsed; SaveVocabularyButton.IsEnabled = false;
        PresentExplanationPane();
        ExplainButton.IsEnabled = true;
        if (smokeWord) ExplainWord_Click(this, new RoutedEventArgs());
        else if (smokeInference) ExplainSelection_Click(this, new RoutedEventArgs());
        else if (smokeSelection) FinishSmoke(true, "EPUB selection bridge and explanation pane");
    }

    private void ExplainPrimary_Click(object sender, RoutedEventArgs args)
    {
        if (boundarySuggestion is not null) UseBoundarySuggestion();
        if (SelectionClassifier.IsLexical(selectionKind)) ExplainWord_Click(sender, args);
        else ExplainSelection_Click(sender, args);
    }

    private void ExplainAlternative_Click(object sender, RoutedEventArgs args)
    {
        if (SelectionClassifier.IsLexical(selectionKind)) ExplainSelection_Click(sender, args);
        else ExplainWord_Click(sender, args);
    }

    private void UseBoundarySuggestion_Click(object sender, RoutedEventArgs args) => UseBoundarySuggestion();
    private void UseBoundarySuggestion()
    {
        if (selectionRequest is null || boundarySuggestion is null) return;
        selectionRequest = selectionRequest with { TargetText = boundarySuggestion.SuggestedText };
        SelectedText.Text = selectionRequest.TargetText;
        UpdateSelectedFurigana();
        selectionKind = SelectionClassifier.Classify(selectionRequest.TargetText, selectionRequest.SourceLanguage);
        boundarySuggestion = null; BoundarySuggestionPanel.Visibility = Visibility.Collapsed;
        ExplainButton.Content = SelectionClassifier.ActionTitle(selectionKind);
        ExplainWordButton.Content = SelectionClassifier.IsLexical(selectionKind) ? "按句子解释" : "按词语解释";
    }

    private async void ExplainSelection_Click(object sender, RoutedEventArgs args)
    {
        if (selectionRequest is null) return;
        explanationCancellation?.Cancel(); explanationCancellation = new CancellationTokenSource();
        ExplainButton.IsEnabled = ExplainWordButton.IsEnabled = false; CancelExplanationButton.Visibility = Visibility.Visible;
        completedWordExplanation = null; SaveVocabularyButton.Visibility = Visibility.Collapsed;
        ExplanationProgressRing.IsActive = true; ExplanationContent.Children.Clear(); ExplanationStatus.Text = "正在连接本地 Ollama…";
        try
        {
            await foreach (var update in readingAIFactory(device.Settings).ExplainStreamAsync(selectionRequest, explanationCancellation.Token))
            {
                ExplanationStatus.Text = update.Result is null ? "正在生成解释…" : "解释完成";
                if (update.Preview is not null) ShowExplanationPreview(update.Preview);
                if (update.Result is not null) ShowExplanation(update.Result);
            }
        }
        catch (OperationCanceledException) { ExplanationStatus.Text = "已停止。"; }
        catch (Exception error) { ExplanationStatus.Text = "解释失败：" + error.Message; if (smokeInference) FinishSmoke(false, error.Message); }
        finally { ExplanationProgressRing.IsActive = false; CancelExplanationButton.Visibility = Visibility.Collapsed; ExplainButton.IsEnabled = ExplainWordButton.IsEnabled = selectionRequest is not null; }
    }

    private async void ExplainWord_Click(object sender, RoutedEventArgs args)
    {
        if (selectionRequest is null) return;
        explanationCancellation?.Cancel(); explanationCancellation = new CancellationTokenSource();
        ExplainButton.IsEnabled = ExplainWordButton.IsEnabled = false;
        CancelExplanationButton.Visibility = Visibility.Visible; ExplanationProgressRing.IsActive = true;
        ExplanationContent.Children.Clear(); SaveExplanationButton.Visibility = Visibility.Collapsed;
        SaveVocabularyButton.Visibility = Visibility.Collapsed; ExplanationStatus.Text = "正在解释词语…";
        try
        {
            var request = new WordExplanationRequest
            {
                SelectedText = selectionRequest.TargetText, SentenceContext = selectionSentence,
                PrecedingContext = selectionRequest.PrecedingContext, FollowingContext = selectionRequest.FollowingContext,
                SourceLanguage = selectionRequest.SourceLanguage, ExplanationLanguage = selectionRequest.ExplanationLanguage
            };
            completedWordExplanation = await vocabularyAIFactory(device.Settings).ExplainWordAsync(request, explanationCancellation.Token);
            completedExplanation = null; ShowWordExplanation(completedWordExplanation); ExplanationStatus.Text = "词语解释完成";
        }
        catch (OperationCanceledException) { ExplanationStatus.Text = "已停止。"; }
        catch (Exception error) { ExplanationStatus.Text = "词语解释失败：" + error.Message; }
        finally
        {
            ExplanationProgressRing.IsActive = false; CancelExplanationButton.Visibility = Visibility.Collapsed;
            ExplainButton.IsEnabled = ExplainWordButton.IsEnabled = selectionRequest is not null;
        }
    }

    private void ShowWordExplanation(WordExplanation result)
    {
        if (selectionRequest is not null && JapaneseLanguage.IsJapanese(selectionRequest.SourceLanguage, result.Surface) && device.Settings.ShowsFurigana)
            AddJapaneseSection(ExplanationContent, result.Surface, $"原形：{result.Lemma}　词性：{result.PartOfSpeech}");
        else AddSection(result.Reading is { Length: > 0 } ? $"{result.Lemma} · {result.Reading}" : result.Lemma, result.PartOfSpeech);
        AddSection("当前语境", result.ContextualMeaning);
        if (result.BriefMeaning != result.ContextualMeaning) AddSection("简明释义", result.BriefMeaning);
        if (!string.IsNullOrWhiteSpace(result.Inflection)) AddSection("词形", result.Inflection);
        foreach (var item in result.Collocations) AddSection(item.Text, item.Meaning);
        SaveVocabularyButton.Visibility = Visibility.Visible; SaveVocabularyButton.IsEnabled = true;
        if (smokeWord) FinishSmoke(true, "Local Ollama word: " + result.ContextualMeaning);
    }

    private void ShowExplanation(Explanation result)
    {
        completedExplanation = result;
        ExplanationContent.Children.Clear();
        AddSection("翻译", result.Translation); AddSection("句子主干", result.SentenceCore);
        foreach (var point in result.GrammarPoints) AddSection(point.Text, point.Explanation);
        foreach (var phrase in result.KeyPhrases) AddSection(phrase.Text, phrase.Meaning);
        SaveExplanationButton.Visibility = Visibility.Visible; SaveExplanationButton.IsEnabled = true;
        AnalyzeDeepButton.Visibility = Visibility.Visible; AnalyzeDeepButton.IsEnabled = true;
        if (smokeDeep) AnalyzeDeep_Click(this, new RoutedEventArgs());
        else if (smokeInference) FinishSmoke(true, "Local Ollama: " + result.Translation);
    }

    private async void AnalyzeDeep_Click(object sender, RoutedEventArgs args)
    {
        if (selectionRequest is null) return;
        explanationCancellation?.Cancel(); explanationCancellation = new CancellationTokenSource();
        var provider = readingAIFactory(device.Settings);
        if (provider is not IDeepReadingAI deep)
        {
            DeepAnalysisStatus.Text = "当前解释服务不支持深入解析。"; DeepAnalysisStatus.Visibility = Visibility.Visible; return;
        }
        AnalyzeDeepButton.IsEnabled = false; DeepAnalysisContent.Children.Clear();
        DeepAnalysisStatus.Text = "正在深入分析句式、成分和从句…"; DeepAnalysisStatus.Visibility = Visibility.Visible;
        try
        {
            var result = await deep.AnalyzeDeepAsync(selectionRequest, explanationCancellation.Token);
            ShowDeepAnalysis(result); DeepAnalysisStatus.Text = "深入解析完成";
        }
        catch (OperationCanceledException) { DeepAnalysisStatus.Text = "已停止深入解析。"; }
        catch (Exception error) { DeepAnalysisStatus.Text = "深入解析失败：" + error.Message; }
        finally { AnalyzeDeepButton.IsEnabled = selectionRequest is not null; }
    }

    private void ShowDeepAnalysis(DeepAnalysis result)
    {
        AddDeepSection("句子类型", result.SentenceType);
        AddDeepSection("句型结构", result.SentencePattern);
        foreach (var component in result.Components)
            AddDeepSection($"{component.Text} · {component.Role}", component.Explanation + (string.IsNullOrWhiteSpace(component.Modifies) ? "" : $"\n修饰：{component.Modifies}"));
        foreach (var clause in result.Clauses) AddDeepSection($"{clause.Text} · {clause.Type}", $"{clause.Function}\n{clause.Explanation}");
        foreach (var point in result.GrammarPoints) AddDeepSection("深度语法 · " + point.Text, point.Explanation);
        if (result.JapaneseWords is { Length: > 0 })
        {
            DeepAnalysisContent.Children.Add(new TextBlock { Text = "日语词形与读音（本地词典）", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
            foreach (var word in result.JapaneseWords)
                AddJapaneseWordSection(word);
            DeepAnalysisContent.Children.Add(new TextBlock { Text = "读音、原形和词性来自本地 MeCab/IPADic，不依赖语言模型。", FontSize = 11, Opacity = .6, TextWrapping = TextWrapping.Wrap });
        }
        AddDeepSection("整句理解", result.Interpretation);
        if (smokeDeep) FinishSmoke(true, "Local Ollama deep: " + result.SentencePattern);
    }

    private void AddDeepSection(string title, string body)
    {
        var card = new StackPanel { Spacing = 5, Padding = new Thickness(12) };
        card.Children.Add(new TextBlock { Text = title, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        card.Children.Add(new TextBlock { Text = body, Opacity = .75, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        DeepAnalysisContent.Children.Add(card);
    }

    private void UpdateSelectedFurigana()
    {
        SelectedFurigana.Children.Clear();
        var show = selectionRequest is not null && device.Settings.ShowsFurigana &&
            JapaneseLanguage.IsJapanese(selectionRequest.SourceLanguage, selectionRequest.TargetText);
        SelectedText.Visibility = show ? Visibility.Collapsed : Visibility.Visible;
        SelectedFurigana.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        if (show) SelectedFurigana.Children.Add(CreateFuriganaView(selectionRequest!.TargetText, 16));
    }

    private void AddJapaneseSection(StackPanel destination, string text, string body)
    {
        var card = new StackPanel { Spacing = 5, Padding = new Thickness(12) };
        card.Children.Add(CreateFuriganaView(text, 17));
        card.Children.Add(new TextBlock { Text = body, Opacity = .75, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        destination.Children.Add(card);
    }

    private void AddJapaneseWordSection(JapaneseWord word)
    {
        var card = new StackPanel { Spacing = 5, Padding = new Thickness(12) };
        card.Children.Add(CreateFuriganaView(word.Text, 17));
        card.Children.Add(new TextBlock { Text = $"原形：{word.BaseForm}　{word.GrammaticalFunction}\n{word.InflectionType}", Opacity = .75, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        var save = new Button { Content = "加入生词本", HorizontalAlignment = HorizontalAlignment.Left };
        save.Click += async (_, _) => await SaveJapaneseWordAsync(word, save);
        card.Children.Add(save); DeepAnalysisContent.Children.Add(card);
    }

    private async Task SaveJapaneseWordAsync(JapaneseWord word, Button button)
    {
        if (selectionRequest is null || book is null) return;
        button.IsEnabled = false;
        try
        {
            library = await libraryStore.LoadAsync();
            var now = DateTimeOffset.UtcNow;
            var entry = new VocabularyEntry(Guid.NewGuid(), selectionRequest.SourceLanguage, word.BaseForm, [word.Text],
                [new VocabularySense(Guid.NewGuid(), word.GrammaticalFunction, selectionRequest.ExplanationLanguage)],
                [new VocabularySource(Guid.NewGuid(), new Document(book.Id, book.FileName), selectionSentence, word.Text, now, Locator: selectionLocator)],
                now, now, word.Reading, word.InflectionType);
            library = LearningLibraryOperations.UpsertVocabulary(library, entry);
            await libraryStore.SaveAsync(library);
            button.Content = "已加入生词本";
        }
        catch (Exception error) { ShowError("无法收藏日语词形：" + error.Message); button.IsEnabled = true; }
    }

    private StackPanel CreateFuriganaView(string text, double fontSize)
    {
        var root = new StackPanel { Spacing = 5 };
        var row = NewRow();
        root.Children.Add(row);
        var width = 0;
        foreach (var segment in japaneseMorphology.ReadingSegments(text))
        {
            var length = Math.Max(1, segment.Surface.Length);
            if (width > 0 && width + length > 18) { row = NewRow(); root.Children.Add(row); width = 0; }
            var token = new StackPanel { Spacing = 0, VerticalAlignment = VerticalAlignment.Bottom };
            token.Children.Add(new TextBlock { Text = segment.Reading ?? " ", FontSize = Math.Max(9, fontSize * .58), Opacity = segment.Reading is null ? 0 : .72, HorizontalAlignment = HorizontalAlignment.Center });
            token.Children.Add(new TextBlock { Text = segment.Surface, FontSize = fontSize, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, IsTextSelectionEnabled = true });
            row.Children.Add(token); width += length;
        }
        return root;

        static StackPanel NewRow() => new() { Orientation = Orientation.Horizontal, Spacing = 1 };
    }

    private void ShowExplanationPreview(ExplanationPreview preview)
    {
        ExplanationContent.Children.Clear();
        if (!string.IsNullOrWhiteSpace(preview.Translation)) AddSection("翻译", preview.Translation);
        if (!string.IsNullOrWhiteSpace(preview.SentenceCore)) AddSection("句子主干", preview.SentenceCore);
        foreach (var point in preview.GrammarPoints) AddSection(point.Text, point.Explanation);
        foreach (var phrase in preview.KeyPhrases) AddSection(phrase.Text, phrase.Meaning);
    }

    private static EpubLocator? ReadLocator(JsonElement payload)
    {
        if (!payload.TryGetProperty("locator", out var value) || value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return null;
        try { return JsonSerializer.Deserialize<DocumentLocator>(value.GetRawText(), ContractJson.Options) as EpubLocator; }
        catch (JsonException) { return null; }
    }

    private async void SaveExplanation_Click(object sender, RoutedEventArgs args)
    {
        if (selectionRequest is null || completedExplanation is null || book is null) return;
        SaveExplanationButton.IsEnabled = false;
        ExplanationStatus.Text = "正在保存…";
        try
        {
            library = await libraryStore.LoadAsync();
            var now = DateTimeOffset.UtcNow;
            var record = new SavedExplanation(
                Guid.NewGuid(), new Document(book.Id, book.FileName), selectionRequest,
                new PersistedExplanation(
                    completedExplanation.Translation,
                    completedExplanation.SentenceCore,
                    completedExplanation.GrammarPoints.Select(point => new PersistedGrammarPoint(point.Text, point.Explanation)).ToArray(),
                    completedExplanation.KeyPhrases.Select(phrase => new PersistedKeyPhrase(phrase.Text, phrase.Meaning)).ToArray(),
                    ActiveModelName()),
                now, now, Locator: selectionLocator);
            library = LearningLibraryOperations.UpsertExplanation(library, record);
            await libraryStore.SaveAsync(library);
            ExplanationStatus.Text = "已保存到学习记录。";
            Notice.Message = "解释已保存到学习记录。"; Notice.Severity = InfoBarSeverity.Success; Notice.IsOpen = true;
        }
        catch (Exception error) { ExplanationStatus.Text = "保存失败：" + error.Message; }
        finally { SaveExplanationButton.IsEnabled = completedExplanation is not null; }
    }

    private async void SaveVocabulary_Click(object sender, RoutedEventArgs args)
    {
        if (completedWordExplanation is null || selectionRequest is null || book is null) return;
        SaveVocabularyButton.IsEnabled = false; ExplanationStatus.Text = "正在收藏…";
        try
        {
            library = await libraryStore.LoadAsync();
            var now = DateTimeOffset.UtcNow;
            var word = completedWordExplanation;
            var entry = new VocabularyEntry(
                Guid.NewGuid(), selectionRequest.SourceLanguage, word.Lemma, [word.Surface],
                [new VocabularySense(Guid.NewGuid(), word.ContextualMeaning, selectionRequest.ExplanationLanguage)],
                [new VocabularySource(Guid.NewGuid(), new Document(book.Id, book.FileName), selectionSentence, word.Surface, now, Locator: selectionLocator)],
                now, now, word.Reading, word.PartOfSpeech);
            library = LearningLibraryOperations.UpsertVocabulary(library, entry);
            await libraryStore.SaveAsync(library);
            ExplanationStatus.Text = "已收藏到生词本。";
            Notice.Message = "词语已收藏到生词本。"; Notice.Severity = InfoBarSeverity.Success; Notice.IsOpen = true;
        }
        catch (Exception error) { ExplanationStatus.Text = "收藏失败：" + error.Message; }
        finally { SaveVocabularyButton.IsEnabled = completedWordExplanation is not null; }
    }

    private void AddSection(string title, string body)
    {
        var card = new StackPanel { Spacing = 5, Padding = new Thickness(12) };
        card.Children.Add(new TextBlock { Text = title, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        card.Children.Add(new TextBlock { Text = body, Opacity = .75, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        ExplanationContent.Children.Add(card);
    }

    private void CancelExplanation_Click(object sender, RoutedEventArgs args) => explanationCancellation?.Cancel();
    private void PresentExplanationPane()
    {
        ExplanationPane.Visibility = Visibility.Visible;
        if (device.Settings.ExplanationPresentation == "popup")
        {
            ExplanationColumn.Width = new GridLength(0); Grid.SetColumn(ExplanationPane, 0); Canvas.SetZIndex(ExplanationPane, 10);
            ExplanationPane.Width = 420; ExplanationPane.MaxHeight = 700; ExplanationPane.HorizontalAlignment = HorizontalAlignment.Right;
            ExplanationPane.VerticalAlignment = VerticalAlignment.Top; ExplanationPane.Margin = new Thickness(24);
        }
        else
        {
            ExplanationColumn.Width = new GridLength(360); Grid.SetColumn(ExplanationPane, 1); Canvas.SetZIndex(ExplanationPane, 0);
            ExplanationPane.Width = double.NaN; ExplanationPane.MaxHeight = double.PositiveInfinity; ExplanationPane.HorizontalAlignment = HorizontalAlignment.Stretch;
            ExplanationPane.VerticalAlignment = VerticalAlignment.Stretch; ExplanationPane.Margin = new Thickness(0);
        }
    }
    private void CloseExplanation_Click(object sender, RoutedEventArgs args)
    {
        explanationCancellation?.Cancel(); selectionRequest = null; completedExplanation = null; completedWordExplanation = null; selectionLocator = null; selectionSentence = ""; boundarySuggestion = null;
        BoundarySuggestionPanel.Visibility = Visibility.Collapsed;
        SaveExplanationButton.Visibility = Visibility.Collapsed; SaveExplanationButton.IsEnabled = false;
        SaveVocabularyButton.Visibility = Visibility.Collapsed; SaveVocabularyButton.IsEnabled = false;
        AnalyzeDeepButton.Visibility = DeepAnalysisStatus.Visibility = Visibility.Collapsed; DeepAnalysisContent.Children.Clear();
        ExplanationPane.Visibility = Visibility.Collapsed; ExplanationColumn.Width = new GridLength(0); Send("clearSelection", new { });
    }
}
