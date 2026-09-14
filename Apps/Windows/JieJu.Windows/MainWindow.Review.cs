using JieJu.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace JieJu.Windows;

public sealed partial class MainWindow
{
    private const int GentleReviewSessionSize = 10;
    private int sessionReviewedCount;
    private bool reviewShowsAnswer;
    private bool reviewSubmitting;

    private async Task ShowReviewContentsAsync()
    {
        try { library = await libraryStore.LoadAsync(); }
        catch (Exception error)
        {
            ShowError("无法读取温习卡片：" + error.Message);
            AddReviewFooter();
            return;
        }

        if (sessionReviewedCount >= GentleReviewSessionSize)
        {
            LibraryContent.Children.Add(new TextBlock { Text = "这次先看到这里", FontSize = 22, Margin = new Thickness(0, 96, 0, 0) });
            LibraryContent.Children.Add(new TextBlock
            {
                Text = "语言学习是一件长期的事，不急于一时。你可以继续阅读，也可以按自己的心情再看几张。",
                TextWrapping = TextWrapping.Wrap, Opacity = .65, MaxWidth = 620
            });
            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, Margin = new Thickness(0, 14, 0, 0) };
            actions.Children.Add(ReturnToReadingButton());
            var more = new Button { Content = "再看几张" };
            AutomationProperties.SetAutomationId(more, "review.continue");
            more.Click += async (_, _) => { sessionReviewedCount = 0; reviewShowsAnswer = false; await ShowLibrarySectionAsync(); };
            actions.Children.Add(more);
            LibraryContent.Children.Add(actions);
            AddReviewPhilosophy();
            return;
        }

        var item = LearningLibraryOperations.DueReviews(library, DateTimeOffset.UtcNow, 50).FirstOrDefault();
        if (item is null)
        {
            var hasVocabulary = library.VocabularyEntries.Length > 0;
            LibraryContent.Children.Add(new TextBlock
            {
                Text = hasVocabulary ? "先去读点喜欢的内容吧" : "还没有复习卡片",
                FontSize = 22, Margin = new Thickness(0, 96, 0, 0)
            });
            LibraryContent.Children.Add(new TextBlock
            {
                Text = hasVocabulary
                    ? "暂时没有适合重温的词。不必每天打卡，想起来时再回来。"
                    : "从阅读解句中收藏生词后，会自动生成第一张记忆卡片。",
                TextWrapping = TextWrapping.Wrap, Opacity = .6
            });
            AddReviewFooter();
            return;
        }

        var card = new StackPanel { Spacing = 10, Padding = new Thickness(24), MinHeight = 180, MaxWidth = 720, HorizontalAlignment = HorizontalAlignment.Stretch };
        var lemma = new TextBlock { Text = item.Entry.Lemma, FontSize = 36, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextAlignment = TextAlignment.Center, IsTextSelectionEnabled = true };
        AutomationProperties.SetAutomationId(lemma, "review.lemma");
        card.Children.Add(lemma);
        card.Children.Add(new TextBlock { Text = item.Entry.Language, FontSize = 12, Opacity = .55, TextAlignment = TextAlignment.Center });
        if (!reviewShowsAnswer)
            card.Children.Add(new TextBlock { Text = "回想它的含义" + (string.IsNullOrWhiteSpace(item.Entry.Reading) ? "" : "和读音"), Opacity = .65, TextAlignment = TextAlignment.Center });
        LibraryContent.Children.Add(card);

        if (!reviewShowsAnswer)
        {
            var reveal = new Button { Content = "显示答案", HorizontalAlignment = HorizontalAlignment.Center, Padding = new Thickness(20, 10, 20, 10) };
            AutomationProperties.SetAutomationId(reveal, "review.showAnswer");
            reveal.KeyboardAccelerators.Add(new KeyboardAccelerator { Key = VirtualKey.Space });
            reveal.Click += async (_, _) => { reviewShowsAnswer = true; await ShowLibrarySectionAsync(); };
            LibraryContent.Children.Add(reveal);
        }
        else
        {
            AddReviewAnswer(item);
            AddRatingButtons(item);
            LibraryContent.Children.Add(new TextBlock { Text = "按此刻的感觉选择就好，没有对错。", FontSize = 12, Opacity = .55, TextAlignment = TextAlignment.Center });
        }
        AddReviewFooter();
    }

    private void AddReviewAnswer(ReviewQueueItem item)
    {
        var answer = new StackPanel { Spacing = 10, Padding = new Thickness(18), MaxWidth = 720, HorizontalAlignment = HorizontalAlignment.Stretch };
        AutomationProperties.SetAutomationId(answer, "review.answer");
        if (!string.IsNullOrWhiteSpace(item.Entry.Reading)) AddLabeledReviewText(answer, "读音", item.Entry.Reading!);
        if (!string.IsNullOrWhiteSpace(item.Entry.PartOfSpeech)) AddLabeledReviewText(answer, "词形/词性", item.Entry.PartOfSpeech!);
        foreach (var sense in item.Entry.Senses)
            answer.Children.Add(new TextBlock { Text = sense.Meaning, FontSize = 19, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        var source = item.Entry.Sources.LastOrDefault();
        if (source is not null)
        {
            answer.Children.Add(new TextBlock { Text = source.Sentence, FontStyle = global::Windows.UI.Text.FontStyle.Italic, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, Margin = new Thickness(0, 8, 0, 0) });
            answer.Children.Add(new TextBlock { Text = source.Document.FileName, FontSize = 12, Opacity = .55 });
            var returnToSource = new Button { Content = "回到这处原文", HorizontalAlignment = HorizontalAlignment.Left };
            AutomationProperties.SetAutomationId(returnToSource, "review.returnToSource");
            returnToSource.Click += async (_, _) => await ReturnToSourceAsync(source);
            answer.Children.Add(returnToSource);
        }
        LibraryContent.Children.Add(answer);
    }

    private static void AddLabeledReviewText(Panel panel, string label, string value)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        row.Children.Add(new TextBlock { Text = label, Opacity = .55, MinWidth = 76 });
        row.Children.Add(new TextBlock { Text = value, IsTextSelectionEnabled = true, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(row);
    }

    private void AddRatingButtons(ReviewQueueItem item)
    {
        var ratings = new (ReviewRating Rating, string Title, VirtualKey Key)[]
        {
            (ReviewRating.Again, "没想起", VirtualKey.Number1),
            (ReviewRating.Hard, "有点模糊", VirtualKey.Number2),
            (ReviewRating.Good, "想起来了", VirtualKey.Number3),
            (ReviewRating.Easy, "很熟悉", VirtualKey.Number4)
        };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Center };
        foreach (var rating in ratings)
        {
            var button = new Button { Content = rating.Title, MinWidth = 110, IsEnabled = !reviewSubmitting };
            AutomationProperties.SetAutomationId(button, "review.rate." + rating.Rating.ToString().ToLowerInvariant());
            button.KeyboardAccelerators.Add(new KeyboardAccelerator { Key = rating.Key });
            button.Click += async (_, _) => await SubmitReviewAsync(item.Card.Id, rating.Rating);
            row.Children.Add(button);
        }
        LibraryContent.Children.Add(row);
    }

    private async Task SubmitReviewAsync(Guid cardId, ReviewRating rating)
    {
        if (reviewSubmitting) return;
        reviewSubmitting = true;
        try
        {
            library = LearningLibraryOperations.Review(await libraryStore.LoadAsync(), cardId, rating, DateTimeOffset.UtcNow);
            await libraryStore.SaveAsync(library);
            sessionReviewedCount++;
            reviewShowsAnswer = false;
            await ShowLibrarySectionAsync();
        }
        catch (Exception error) { ShowError("无法保存温习结果：" + error.Message); }
        finally { reviewSubmitting = false; }
    }

    private Button ReturnToReadingButton()
    {
        var button = new Button { Content = "回到阅读" };
        AutomationProperties.SetAutomationId(button, "review.returnToReading");
        button.Click += (_, _) => Navigation.SelectedItem = Navigation.MenuItems[0];
        return button;
    }

    private void AddReviewFooter()
    {
        LibraryContent.Children.Add(ReturnToReadingButton());
        AddReviewPhilosophy();
    }

    private void AddReviewPhilosophy() => LibraryContent.Children.Add(new TextBlock
    {
        Text = "语言不是一条需要赶完的路。读一点，记一点，忘了也没关系；在漫长的相遇里，它终会成为你的一部分。",
        TextWrapping = TextWrapping.Wrap, Opacity = .6, Margin = new Thickness(0, 64, 0, 0)
    });

    private async Task RunReviewSmokeAsync()
    {
        try
        {
            var now = DateTimeOffset.UtcNow;
            var entry = new VocabularyEntry(Guid.NewGuid(), "Japanese", "学校", ["学校"],
                [new VocabularySense(Guid.NewGuid(), "学校；学习的场所", "Chinese")],
                [new VocabularySource(Guid.NewGuid(), new Document("smoke-book", "smoke.epub"), "彼女は学校で本を読んでいます。", "学校", now)],
                now, now, "がっこう", "名词");
            library = LearningLibraryOperations.UpsertVocabulary(await libraryStore.LoadAsync(), entry, now);
            await libraryStore.SaveAsync(library);
            section = "review";
            await ShowLibrarySectionAsync();
            var left = LibraryContent.TransformToVisual(LibraryPage).TransformPoint(new global::Windows.Foundation.Point()).X;
            if (left > 16) throw new InvalidOperationException("Library content was not aligned to the left edge.");
            if (!HasAutomationId("review.showAnswer") || HasAutomationId("review.answer"))
                throw new InvalidOperationException("Recognition card front did not hide the answer.");

            reviewShowsAnswer = true;
            await ShowLibrarySectionAsync();
            if (!HasAutomationId("review.answer") || !HasAutomationId("review.rate.good"))
                throw new InvalidOperationException("Review answer or rating controls were not shown.");

            var cardId = AssertSingleDueCard();
            await SubmitReviewAsync(cardId, ReviewRating.Good);
            var saved = await libraryStore.LoadAsync();
            var log = saved.ReviewLogs.LastOrDefault();
            var card = saved.ReviewCards.Single(item => item.Id == cardId);
            if (log?.Rating != ReviewRating.Good || log.SchedulerVersion != ReviewScheduler.Version || card.IntervalDays != 2)
                throw new InvalidOperationException("Review result was not persisted with the macOS schedule.");

            sessionReviewedCount = GentleReviewSessionSize;
            await ShowLibrarySectionAsync();
            if (!HasAutomationId("review.continue"))
                throw new InvalidOperationException("Gentle pause was not shown after ten cards.");
            FinishSmoke(true, "recognition front, answer, rating log, and gentle pause");
        }
        catch (Exception error) { FinishSmoke(false, error.Message); }
    }

    private Guid AssertSingleDueCard()
    {
        var due = LearningLibraryOperations.DueReviews(library, DateTimeOffset.UtcNow.AddSeconds(1));
        return due.Length == 1 ? due[0].Card.Id : throw new InvalidOperationException("Expected one due review card.");
    }

    private bool HasAutomationId(string automationId) => Descendants(LibraryContent)
        .OfType<DependencyObject>()
        .Any(element => AutomationProperties.GetAutomationId(element) == automationId);

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        yield return root;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
            foreach (var descendant in Descendants(VisualTreeHelper.GetChild(root, index))) yield return descendant;
    }
}
