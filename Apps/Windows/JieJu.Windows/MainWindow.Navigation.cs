using JieJu.Domain;
using JieJu.Windows.Infrastructure;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;

namespace JieJu.Windows;

public sealed partial class MainWindow
{
    private void Navigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (ReaderPage is null) return;
        section = args.IsSettingsSelected ? "settings" : (args.SelectedItem as NavigationViewItem)?.Tag?.ToString() ?? "reader";
        ReaderPage.Visibility = section == "reader" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPage.Visibility = section == "settings" ? Visibility.Visible : Visibility.Collapsed;
        LibraryPage.Visibility = section is "records" or "vocabulary" or "review" ? Visibility.Visible : Visibility.Collapsed;
        if (LibraryPage.Visibility == Visibility.Visible) _ = ShowLibrarySectionAsync();
    }
    private async Task ShowLibrarySectionAsync()
    {
        LibraryContent.Children.Clear();
        var title = section == "records" ? "学习记录" : section == "vocabulary" ? "生词本" : "随手温习";
        LibraryContent.Children.Add(new TextBlock { Text = title, FontSize = 28, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        LibraryContent.Children.Add(new TextBlock { Text = section == "review" ? "想看几张都可以，随时回到阅读。" : "让阅读中值得留下的表达，在这里慢慢积累。", Opacity = .65 });
        if (section == "records")
        {
            try { library = await libraryStore.LoadAsync(); }
            catch (Exception error) { ShowError("无法读取学习记录：" + error.Message); }
            if (library.SavedExplanations.Length == 0)
            {
                LibraryContent.Children.Add(new TextBlock { Text = "还没有保存的解释", FontSize = 22, Margin = new Thickness(0, 96, 0, 0) });
                LibraryContent.Children.Add(new TextBlock { Text = "阅读时选中一段文字，完成解释后即可保存。", Opacity = .6 });
            }
            foreach (var record in library.SavedExplanations.OrderByDescending(item => item.UpdatedAt))
            {
                var content = new StackPanel { Spacing = 5 };
                content.Children.Add(new TextBlock { Text = record.Request.TargetText, FontSize = 17, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
                content.Children.Add(new TextBlock { Text = record.Explanation.Translation, Opacity = .72, TextWrapping = TextWrapping.Wrap });
                content.Children.Add(new TextBlock { Text = $"{record.Document.FileName} · {record.UpdatedAt.ToLocalTime():yyyy-MM-dd HH:mm}", FontSize = 11, Opacity = .5 });
                var button = new Button { Content = content, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(16, 13, 16, 13) };
                button.Click += (_, _) => ShowRecordDetail(record);
                LibraryContent.Children.Add(button);
            }
        }
        else if (section == "vocabulary")
        {
            try { library = await libraryStore.LoadAsync(); }
            catch (Exception error) { ShowError("无法读取生词本：" + error.Message); }
            if (library.VocabularyEntries.Length == 0)
            {
                LibraryContent.Children.Add(new TextBlock { Text = "还没有收藏生词", FontSize = 22, Margin = new Thickness(0, 96, 0, 0) });
                LibraryContent.Children.Add(new TextBlock { Text = "阅读时选中词语，点击“解释为词语”，完成后即可收藏。", Opacity = .6 });
            }
            foreach (var entry in library.VocabularyEntries.OrderByDescending(item => item.UpdatedAt))
            {
                var content = new StackPanel { Spacing = 5 };
                content.Children.Add(new TextBlock { Text = entry.Reading is { Length: > 0 } ? $"{entry.Lemma} · {entry.Reading}" : entry.Lemma, FontSize = 18, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
                content.Children.Add(new TextBlock { Text = entry.Senses.FirstOrDefault()?.Meaning ?? "", Opacity = .72, TextWrapping = TextWrapping.Wrap });
                content.Children.Add(new TextBlock { Text = $"{entry.PartOfSpeech} · {entry.Sources.Length} 个来源", FontSize = 11, Opacity = .5 });
                var button = new Button { Content = content, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(16, 13, 16, 13) };
                button.Click += (_, _) => ShowVocabularyDetail(entry);
                LibraryContent.Children.Add(button);
            }
        }
        else
        {
            await ShowReviewContentsAsync();
            return;
        }
        var back = new Button { Content = "回到阅读" };
        back.Click += (_, _) => Navigation.SelectedItem = Navigation.MenuItems[0];
        LibraryContent.Children.Add(back);
    }

    private void ShowRecordDetail(SavedExplanation record)
    {
        LibraryContent.Children.Clear();
        var list = new Button { Content = "← 返回学习记录" };
        list.Click += async (_, _) => await ShowLibrarySectionAsync();
        LibraryContent.Children.Add(list);
        LibraryContent.Children.Add(new TextBlock { Text = record.Request.TargetText, FontSize = 26, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        AddRecordSection("翻译", record.Explanation.Translation);
        AddRecordSection("句子主干", record.Explanation.SentenceCore);
        foreach (var point in record.Explanation.GrammarPoints) AddRecordSection(point.Title, point.Explanation);
        foreach (var phrase in record.Explanation.KeyPhrases) AddRecordSection(phrase.Text, phrase.Meaning);
        LibraryContent.Children.Add(new TextBlock { Text = $"来源：{record.Document.FileName} · 保存于 {record.UpdatedAt.ToLocalTime():yyyy-MM-dd HH:mm}", Opacity = .55, Margin = new Thickness(0, 10, 0, 0) });
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var source = new Button { Content = "回到原文" };
        source.Click += async (_, _) => await ReturnToSourceAsync(record);
        var delete = new Button { Content = "删除记录" };
        delete.Click += async (_, _) => await DeleteRecordAsync(record);
        actions.Children.Add(source); actions.Children.Add(delete); LibraryContent.Children.Add(actions);
    }

    private void AddRecordSection(string title, string body)
    {
        LibraryContent.Children.Add(new TextBlock { Text = title, FontSize = 17, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 10, 0, 0) });
        LibraryContent.Children.Add(new TextBlock { Text = body, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, Opacity = .76 });
    }

    private async Task DeleteRecordAsync(SavedExplanation record)
    {
        var dialog = new ContentDialog { Title = "删除这条学习记录？", Content = record.Request.TargetText, PrimaryButtonText = "删除", CloseButtonText = "取消", DefaultButton = ContentDialogButton.Close, XamlRoot = Content.XamlRoot };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try
        {
            library = LearningLibraryOperations.DeleteExplanation(await libraryStore.LoadAsync(), record.Id);
            await libraryStore.SaveAsync(library);
            await ShowLibrarySectionAsync();
        }
        catch (Exception error) { ShowError("无法删除学习记录：" + error.Message); }
    }

    private async Task ReturnToSourceAsync(SavedExplanation record)
    {
        var recent = device.RecentBooks.FirstOrDefault(item => item.Id == record.Document.Id && File.Exists(item.Path));
        if (recent is null) { ShowError("找不到原书，请先从阅读页重新打开这本 EPUB。"); return; }
        await OpenBook(recent.Path, record.Locator as EpubLocator);
    }

    private void ShowVocabularyDetail(VocabularyEntry entry)
    {
        LibraryContent.Children.Clear();
        var list = new Button { Content = "← 返回生词本" };
        list.Click += async (_, _) => await ShowLibrarySectionAsync(); LibraryContent.Children.Add(list);
        LibraryContent.Children.Add(new TextBlock { Text = entry.Reading is { Length: > 0 } ? $"{entry.Lemma} · {entry.Reading}" : entry.Lemma, FontSize = 28, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        if (!string.IsNullOrWhiteSpace(entry.PartOfSpeech)) AddRecordSection("词性", entry.PartOfSpeech);
        foreach (var sense in entry.Senses) AddRecordSection("释义", sense.Meaning);
        foreach (var source in entry.Sources.OrderByDescending(item => item.CreatedAt)) AddRecordSection(source.Document.FileName, source.Sentence);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, Margin = new Thickness(0, 12, 0, 0) };
        var sourceButton = new Button { Content = "回到最近来源", IsEnabled = entry.Sources.Length > 0 };
        sourceButton.Click += async (_, _) => await ReturnToSourceAsync(entry.Sources.OrderByDescending(item => item.CreatedAt).First());
        var delete = new Button { Content = "删除生词" };
        delete.Click += async (_, _) => await DeleteVocabularyAsync(entry);
        actions.Children.Add(sourceButton); actions.Children.Add(delete); LibraryContent.Children.Add(actions);
    }

    private async Task DeleteVocabularyAsync(VocabularyEntry entry)
    {
        var dialog = new ContentDialog { Title = "删除这个生词？", Content = entry.Lemma, PrimaryButtonText = "删除", CloseButtonText = "取消", DefaultButton = ContentDialogButton.Close, XamlRoot = Content.XamlRoot };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try
        {
            library = LearningLibraryOperations.DeleteVocabulary(await libraryStore.LoadAsync(), entry.Id);
            await libraryStore.SaveAsync(library); await ShowLibrarySectionAsync();
        }
        catch (Exception error) { ShowError("无法删除生词：" + error.Message); }
    }

    private async Task ReturnToSourceAsync(VocabularySource source)
    {
        var recent = device.RecentBooks.FirstOrDefault(item => item.Id == source.Document.Id && File.Exists(item.Path));
        if (recent is null) { ShowError("找不到原书，请先从阅读页重新打开这本 EPUB。"); return; }
        await OpenBook(recent.Path, source.Locator as EpubLocator);
    }
    private async void OpenBook_Click(object sender, RoutedEventArgs args)
    {
        try
        {
            var picker = new FileOpenPicker();
            WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
            picker.FileTypeFilter.Add(".epub");
            picker.FileTypeFilter.Add(".pdf");
            var file = await picker.PickSingleFileAsync();
            if (file is not null) await OpenDocument(file.Path);
        }
        catch (Exception e) { ShowError("无法打开文件选择器：" + e.Message); }
    }
    private Task OpenDocument(string path) => string.Equals(Path.GetExtension(path), ".pdf", StringComparison.OrdinalIgnoreCase)
        ? OpenPdf(path) : OpenBook(path);

    private async Task OpenPdf(string path)
    {
        if (!OpenButton.IsEnabled) return;
        OpenButton.IsEnabled = false;
        try
        {
            var loaded = await Task.Run(() => PdfBook.Open(path));
            if (closed) return;
            ResetExplanation();
            pdf = loaded; pdfUrl = ReaderHostPolicy.CurrentPdf; book = null; bookPath = path;
            var recent = device.RecentBooks.FirstOrDefault(item => item.Id == pdf.Id && item.Kind == "pdf");
            pdfPageIndex = Math.Max(0, recent?.Chapter ?? 0);
            WelcomePanel.Visibility = Visibility.Collapsed;
            CloseBookButton.Visibility = Visibility.Visible;
            ReaderToolbar.Visibility = Visibility.Collapsed;
            BookTitle.Text = pdf.Title; BookSubtitle.Text = "PDF · 文本型文档";
            Navigation.SelectedItem = Navigation.MenuItems[0];
            Status.Text = "正在载入 PDF 文字层…";
            device = DeviceStateStore.Remember(device, new RecentBook(pdf.Id, path, pdf.Title, pdfPageIndex, 0, DateTimeOffset.UtcNow, "pdf"));
            deviceStore.Save(device);
            pdfNavigationGeneration++;
            Reader.CoreWebView2?.Navigate(ReaderHostPolicy.PdfPage);
        }
        catch (Exception error) { ShowError("无法打开这份 PDF：" + error.Message); if (smokePdf) FinishSmoke(false, error.Message); }
        finally { OpenButton.IsEnabled = true; }
    }
    private async Task OpenBook(string path, EpubLocator? preferredLocator = null)
    {
        if (!OpenButton.IsEnabled) return;
        OpenButton.IsEnabled = false;
        try
        {
            var loaded = await Task.Run(() => EpubBook.Open(path));
            if (closed) return;
            book = loaded; pdf = null; pdfUrl = null; bookPath = path;
            var recent = device.RecentBooks.FirstOrDefault(b => b.Id == book.Id);
            chapterIndex = Math.Clamp(recent?.Chapter ?? 0, 0, book.Chapters.Count - 1);
            pendingProgress = Math.Clamp(recent?.Progress ?? 0, 0, 1);
            if (preferredLocator is not null)
            {
                var locatedChapter = book.Chapters.ToList().FindIndex(chapter => chapter.Href == preferredLocator.ChapterHref);
                if (locatedChapter >= 0) chapterIndex = locatedChapter;
                pendingProgress = ReadProgress(preferredLocator.TextAnchor) ?? pendingProgress;
            }
            changingChapter = true; ChapterPicker.ItemsSource = book.Chapters; ChapterPicker.SelectedIndex = chapterIndex; changingChapter = false;
            WelcomePanel.Visibility = Visibility.Collapsed;
            CloseBookButton.Visibility = ReaderToolbar.Visibility = Visibility.Visible;
            BookTitle.Text = book.Title; BookSubtitle.Text = book.Language == "und" ? "EPUB · 可重排阅读" : $"EPUB · {book.Language}";
            Navigation.SelectedItem = Navigation.MenuItems[0];
            NavigateChapter(); Remember(pendingProgress);
        }
        catch (Exception error) { ShowError("无法打开这本书：" + error.Message); }
        finally { OpenButton.IsEnabled = true; }
    }
    private static double? ReadProgress(string? textAnchor)
    {
        if (string.IsNullOrWhiteSpace(textAnchor)) return null;
        try
        {
            using var anchor = System.Text.Json.JsonDocument.Parse(textAnchor);
            return anchor.RootElement.TryGetProperty("progress", out var value) && value.TryGetDouble(out var progress) ? Math.Clamp(progress, 0, 1) : null;
        }
        catch (System.Text.Json.JsonException) { return null; }
    }
    private void NavigateChapter()
    {
        if (book is null || Reader.CoreWebView2 is null) return;
        PreviousChapterButton.IsEnabled = chapterIndex > 0; NextChapterButton.IsEnabled = chapterIndex + 1 < book.Chapters.Count;
        chapterNavigationPending = true;
        Reader.NavigateToString(System.Text.Encoding.UTF8.GetString(book.RenderChapter(chapterIndex, japaneseMorphology)));
    }
    private void ChapterPicker_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (changingChapter || book is null || ChapterPicker.SelectedIndex < 0) return;
        chapterIndex = ChapterPicker.SelectedIndex; pendingProgress = 0; NavigateChapter(); Remember(0);
    }
    private void PreviousChapter_Click(object sender, RoutedEventArgs args) { if (chapterIndex > 0) ChapterPicker.SelectedIndex--; }
    private void NextChapter_Click(object sender, RoutedEventArgs args) { if (book is not null && chapterIndex + 1 < book.Chapters.Count) ChapterPicker.SelectedIndex++; }
    private void FuriganaToolbarToggle_Click(object sender, RoutedEventArgs args)
    {
        var enabled = FuriganaToolbarToggle.IsChecked == true;
        RubyToggle.IsOn = enabled;
        try
        {
            device = device with { Settings = device.Settings with { ShowsFurigana = enabled } };
            deviceStore.Save(device);
            ApplyReadingSettings();
            UpdateSelectedFurigana();
            Status.Text = enabled ? "已显示日语汉字注音。" : "已隐藏日语汉字注音。";
        }
        catch (Exception error) { ShowError("无法保存注音设置：" + error.Message); }
    }
    private void CloseBook_Click(object sender, RoutedEventArgs args)
    {
        book = null; pdf = null; pdfUrl = null; bookPath = null; WelcomePanel.Visibility = Visibility.Visible;
        CloseBookButton.Visibility = ReaderToolbar.Visibility = Visibility.Collapsed;
        BookTitle.Text = "回到阅读"; BookSubtitle.Text = "从一本喜欢的书开始，在阅读中慢慢理解。";
        Reader.CoreWebView2?.Navigate(ReaderHostPolicy.StartPage); RefreshRecentBooks();
    }
    private void Remember(double progress)
    {
        if (book is null || bookPath is null || !double.IsFinite(progress)) return;
        device = DeviceStateStore.Remember(device, new RecentBook(book.Id, bookPath, book.Title, chapterIndex, Math.Clamp(progress, 0, 1), DateTimeOffset.UtcNow));
        try { deviceStore.Save(device); } catch (Exception e) { ShowError("无法保存阅读位置：" + e.Message); }
    }
    private void RememberPdf(int pageIndex)
    {
        if (pdf is null || bookPath is null || pageIndex < 0 || pageIndex == pdfPageIndex) return;
        pdfPageIndex = pageIndex;
        Status.Text = $"PDF · 第 {pageIndex + 1} 页";
        device = DeviceStateStore.Remember(device, new RecentBook(pdf.Id, bookPath, pdf.Title, pageIndex, 0, DateTimeOffset.UtcNow, "pdf"));
        try { deviceStore.Save(device); } catch (Exception error) { ShowError("无法保存 PDF 阅读位置：" + error.Message); }
    }
    private void RefreshRecentBooks()
    {
        RecentBooksPanel.Children.Clear();
        if (device.RecentBooks.Length == 0) RecentBooksPanel.Children.Add(new TextBlock { Text = "还没有最近阅读的书籍。", Opacity = .5 });
        foreach (var recent in device.RecentBooks)
        {
            var position = recent.Kind == "pdf" ? "PDF" : $"第 {recent.Chapter + 1} 章";
            var button = new Button { Content = $"{recent.Title}  ·  {position}", HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left, Padding = new Thickness(16, 12, 16, 12) };
            button.Click += async (_, _) => await OpenDocument(recent.Path); RecentBooksPanel.Children.Add(button);
        }
    }
    private void LoadSettingsControls()
    {
        var s = device.Settings;
        ThemePicker.SelectedIndex = Array.IndexOf(new[] { "paper", "night", "sepia", "sage" }, s.Theme);
        FontSlider.Value = s.FontSize; LineSlider.Value = s.LineHeight; MarginSlider.Value = s.HorizontalMargin;
        RubyToggle.IsOn = s.ShowsFurigana; FuriganaToolbarToggle.IsChecked = s.ShowsFurigana; OllamaAddress.Text = s.OllamaUrl; ModelName.Text = s.Model; TargetLanguage.Text = s.ExplanationLanguage;
        AIProviderPicker.SelectedIndex = s.Provider == "cloud" ? 1 : 0; CloudAddress.Text = s.CloudUrl; CloudModelName.Text = s.CloudModel; CloudApiKey.Password = apiKeyStore.Load(); UpdateProviderSettings();
        ExplanationPresentationPicker.SelectedIndex = s.ExplanationPresentation == "popup" ? 1 : 0;
        settingsControlsLoaded = true;
        UpdateReadingPreview(s);
    }
    private void ReadingAppearance_Changed(object sender, RoutedEventArgs args)
    {
        if (!settingsControlsLoaded || ThemePicker.SelectedItem is not ComboBoxItem theme) return;
        var appearance = DeviceStateStore.Normalize(device.Settings with
        {
            FontSize = FontSlider.Value,
            LineHeight = LineSlider.Value,
            HorizontalMargin = MarginSlider.Value,
            Theme = theme.Tag?.ToString() ?? "paper"
        });
        UpdateReadingPreview(appearance);
        ApplyReadingSettings(appearance);
        SettingsStatus.Text = "排版已实时应用到预览和当前 EPUB；保存后会在下次启动时保留。";
    }
    private void UpdateReadingPreview(ReadingSettings settings)
    {
        var colors = settings.Theme switch
        {
            "night" => (Paper: global::Windows.UI.Color.FromArgb(255, 22, 24, 29), Ink: global::Windows.UI.Color.FromArgb(255, 229, 231, 235)),
            "sepia" => (Paper: global::Windows.UI.Color.FromArgb(255, 244, 236, 216), Ink: global::Windows.UI.Color.FromArgb(255, 67, 60, 48)),
            "sage" => (Paper: global::Windows.UI.Color.FromArgb(255, 221, 232, 213), Ink: global::Windows.UI.Color.FromArgb(255, 41, 58, 41)),
            _ => (Paper: global::Windows.UI.Color.FromArgb(255, 250, 250, 248), Ink: global::Windows.UI.Color.FromArgb(255, 41, 44, 41))
        };
        ReadingPreview.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(colors.Paper);
        var ink = new Microsoft.UI.Xaml.Media.SolidColorBrush(colors.Ink);
        ReadingPreviewLabel.Foreground = ink;
        ReadingPreviewText.Foreground = ink;
        ReadingPreviewText.FontSize = settings.FontSize;
        ReadingPreviewText.LineHeight = settings.FontSize * settings.LineHeight;
        ReadingPreviewPage.Padding = new Thickness(settings.HorizontalMargin, 24, settings.HorizontalMargin, 28);
    }
    private void SaveSettings_Click(object sender, RoutedEventArgs args)
    {
        var provider = ((ComboBoxItem)AIProviderPicker.SelectedItem).Tag.ToString()!;
        var serviceAddress = provider == "cloud" ? CloudAddress.Text.Trim() : OllamaAddress.Text.Trim();
        var serviceModel = provider == "cloud" ? CloudModelName.Text.Trim() : ModelName.Text.Trim();
        if (!Uri.TryCreate(serviceAddress, UriKind.Absolute, out var address) || address.Scheme is not ("http" or "https") || string.IsNullOrWhiteSpace(serviceModel) || string.IsNullOrWhiteSpace(TargetLanguage.Text) || provider == "cloud" && string.IsNullOrWhiteSpace(CloudApiKey.Password))
        { SettingsStatus.Text = provider == "cloud" ? "请输入有效的 API 地址、API Key、模型名和解释语言。" : "请输入有效的 Ollama 地址、模型名和解释语言。"; return; }
        var settings = DeviceStateStore.Normalize(new ReadingSettings(FontSlider.Value, LineSlider.Value, MarginSlider.Value,
            ((ComboBoxItem)ThemePicker.SelectedItem).Tag.ToString()!, RubyToggle.IsOn, OllamaAddress.Text.Trim().TrimEnd('/'), ModelName.Text.Trim(), TargetLanguage.Text.Trim(),
            ((ComboBoxItem)ExplanationPresentationPicker.SelectedItem).Tag.ToString()!, provider, CloudAddress.Text.Trim(), CloudModelName.Text.Trim()));
        try { if (provider == "cloud") apiKeyStore.Save(CloudApiKey.Password); var next = device with { Settings = settings }; deviceStore.Save(next); device = next; FuriganaToolbarToggle.IsChecked = settings.ShowsFurigana; ApplyReadingSettings(); UpdateSelectedFurigana(); if (ExplanationPane.Visibility == Visibility.Visible) PresentExplanationPane(); SettingsStatus.Text = "设置已保存，当前阅读会话继续保留。"; }
        catch (Exception e) { SettingsStatus.Text = "设置保存失败：" + e.Message; }
    }
    private async void CheckConnection_Click(object sender, RoutedEventArgs args)
    {
        SettingsStatus.Text = "正在检查模型…";
        try
        {
            if (((ComboBoxItem)AIProviderPicker.SelectedItem).Tag.ToString() == "cloud")
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
                var provider = new OpenAICompatibleReadingAI(client, CloudAddress.Text, CloudApiKey.Password, CloudModelName.Text);
                await provider.CheckAvailabilityAsync(); SettingsStatus.Text = $"云端 API 已连接：{CloudModelName.Text.Trim()}";
            }
            else SettingsStatus.Text = await OllamaConnection.CheckAsync(OllamaAddress.Text, ModelName.Text);
        }
        catch (Exception e) { SettingsStatus.Text = "无法连接模型：" + e.Message; }
    }

    private void AIProviderPicker_SelectionChanged(object sender, SelectionChangedEventArgs args) => UpdateProviderSettings();
    private void UpdateProviderSettings()
    {
        if (AIProviderPicker?.SelectedItem is not ComboBoxItem item || OllamaSettings is null || CloudSettings is null) return;
        var cloud = item.Tag?.ToString() == "cloud";
        OllamaSettings.Visibility = cloud ? Visibility.Collapsed : Visibility.Visible;
        CloudSettings.Visibility = cloud ? Visibility.Visible : Visibility.Collapsed;
    }

    private string ActiveModelName() => device.Settings.Provider == "cloud" ? device.Settings.CloudModel : device.Settings.Model;
}
