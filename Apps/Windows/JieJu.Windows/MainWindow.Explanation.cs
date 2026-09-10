using System.Text.Json;
using JieJu.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace JieJu.Windows;

public sealed partial class MainWindow
{
    private ExplanationRequest? selectionRequest;
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
        SelectedText.Text = selectionRequest.TargetText;
        SelectionContext.Text = Read("containingSentence") is { Length: > 0 } sentence && sentence != target ? "所在句：" + sentence : "";
        ExplanationContent.Children.Clear(); ExplanationStatus.Text = "准备好后，点击“解释这段”。";
        ExplanationColumn.Width = new GridLength(360); ExplanationPane.Visibility = Visibility.Visible;
        ExplainButton.IsEnabled = true;
        if (smokeInference) ExplainSelection_Click(this, new RoutedEventArgs());
        else if (smokeSelection) FinishSmoke(true, "EPUB selection bridge and explanation pane");
    }

    private async void ExplainSelection_Click(object sender, RoutedEventArgs args)
    {
        if (selectionRequest is null) return;
        explanationCancellation?.Cancel(); explanationCancellation = new CancellationTokenSource();
        ExplainButton.IsEnabled = false; CancelExplanationButton.Visibility = Visibility.Visible;
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
        finally { ExplanationProgressRing.IsActive = false; CancelExplanationButton.Visibility = Visibility.Collapsed; ExplainButton.IsEnabled = selectionRequest is not null; }
    }

    private void ShowExplanation(Explanation result)
    {
        AddSection("翻译", result.Translation); AddSection("句子主干", result.SentenceCore);
        foreach (var point in result.GrammarPoints) AddSection(point.Text, point.Explanation);
        foreach (var phrase in result.KeyPhrases) AddSection(phrase.Text, phrase.Meaning);
        if (smokeInference) FinishSmoke(true, "Local Ollama: " + result.Translation);
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
        explanationCancellation?.Cancel(); selectionRequest = null; ExplanationPane.Visibility = Visibility.Collapsed; ExplanationColumn.Width = new GridLength(0); Send("clearSelection", new { });
    }
}
