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
        selectionSentence = Read("containingSentence") is { Length: > 0 } sentence ? ExplanationValidation.Clean(sentence) : target;
        SelectionContext.Text = selectionSentence != target ? "所在句：" + selectionSentence : "";
        ExplanationContent.Children.Clear(); ExplanationStatus.Text = "准备好后，点击“解释这段”。";
        SaveExplanationButton.Visibility = Visibility.Collapsed; SaveExplanationButton.IsEnabled = false;
        SaveVocabularyButton.Visibility = Visibility.Collapsed; SaveVocabularyButton.IsEnabled = false;
        ExplanationColumn.Width = new GridLength(360); ExplanationPane.Visibility = Visibility.Visible;
        ExplainButton.IsEnabled = true;
        if (smokeWord) ExplainWord_Click(this, new RoutedEventArgs());
        else if (smokeInference) ExplainSelection_Click(this, new RoutedEventArgs());
        else if (smokeSelection) FinishSmoke(true, "EPUB selection bridge and explanation pane");
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
                ExplanationStatus.Text = update.Result is null ? $"正在生成… {update.GeneratedText.Length} 字符" : "解释完成";
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
        AddSection(result.Reading is { Length: > 0 } ? $"{result.Lemma} · {result.Reading}" : result.Lemma, result.PartOfSpeech);
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
        AddSection("翻译", result.Translation); AddSection("句子主干", result.SentenceCore);
        foreach (var point in result.GrammarPoints) AddSection(point.Text, point.Explanation);
        foreach (var phrase in result.KeyPhrases) AddSection(phrase.Text, phrase.Meaning);
        SaveExplanationButton.Visibility = Visibility.Visible; SaveExplanationButton.IsEnabled = true;
        if (smokeInference) FinishSmoke(true, "Local Ollama: " + result.Translation);
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
                    device.Settings.Model),
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
    private void CloseExplanation_Click(object sender, RoutedEventArgs args)
    {
        explanationCancellation?.Cancel(); selectionRequest = null; completedExplanation = null; completedWordExplanation = null; selectionLocator = null; selectionSentence = "";
        SaveExplanationButton.Visibility = Visibility.Collapsed; SaveExplanationButton.IsEnabled = false;
        SaveVocabularyButton.Visibility = Visibility.Collapsed; SaveVocabularyButton.IsEnabled = false;
        ExplanationPane.Visibility = Visibility.Collapsed; ExplanationColumn.Width = new GridLength(0); Send("clearSelection", new { });
    }
}
