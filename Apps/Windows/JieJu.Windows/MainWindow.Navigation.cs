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
        if (LibraryPage.Visibility == Visibility.Visible) ShowLibrarySection();
    }
    private void ShowLibrarySection()
    {
        LibraryContent.Children.Clear();
        var title = section == "records" ? "学习记录" : section == "vocabulary" ? "生词本" : "随手温习";
        LibraryContent.Children.Add(new TextBlock { Text = title, FontSize = 28, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        LibraryContent.Children.Add(new TextBlock { Text = section == "review" ? "想看几张都可以，随时回到阅读。" : "让阅读中值得留下的表达，在这里慢慢积累。", Opacity = .65 });
        LibraryContent.Children.Add(new TextBlock { Text = "还没有保存的内容", FontSize = 22, Margin = new Thickness(0, 96, 0, 0) });
        LibraryContent.Children.Add(new TextBlock { Text = "从阅读中开始。选句解读和收藏功能将在下一阶段接入。", Opacity = .6 });
        var back = new Button { Content = "回到阅读" };
        back.Click += (_, _) => Navigation.SelectedItem = Navigation.MenuItems[0];
        LibraryContent.Children.Add(back);
        if (section == "review") LibraryContent.Children.Add(new TextBlock { Text = "语言不是一条需要赶完的路。读一点，记一点，忘了也没关系；在漫长的相遇里，它终会成为你的一部分。", TextWrapping = TextWrapping.Wrap, Opacity = .6, Margin = new Thickness(0, 64, 0, 0) });
    }
    private async void OpenBook_Click(object sender, RoutedEventArgs args)
    {
        try
        {
            var picker = new FileOpenPicker();
            WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
            picker.FileTypeFilter.Add(".epub");
            var file = await picker.PickSingleFileAsync();
            if (file is not null) await OpenBook(file.Path);
        }
        catch (Exception e) { ShowError("无法打开文件选择器：" + e.Message); }
    }
    private async Task OpenBook(string path)
    {
        if (!OpenButton.IsEnabled) return;
        OpenButton.IsEnabled = false;
        try
        {
            var loaded = await Task.Run(() => EpubBook.Open(path));
            if (closed) return;
            book = loaded; bookPath = path;
            var recent = device.RecentBooks.FirstOrDefault(b => b.Id == book.Id);
            chapterIndex = Math.Clamp(recent?.Chapter ?? 0, 0, book.Chapters.Count - 1);
            pendingProgress = Math.Clamp(recent?.Progress ?? 0, 0, 1);
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
    private void NavigateChapter()
    {
        if (book is null || Reader.CoreWebView2 is null) return;
        PreviousChapterButton.IsEnabled = chapterIndex > 0; NextChapterButton.IsEnabled = chapterIndex + 1 < book.Chapters.Count;
        chapterNavigationPending = true;
        Reader.NavigateToString(System.Text.Encoding.UTF8.GetString(book.RenderChapter(chapterIndex)));
    }
    private void ChapterPicker_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (changingChapter || book is null || ChapterPicker.SelectedIndex < 0) return;
        chapterIndex = ChapterPicker.SelectedIndex; pendingProgress = 0; NavigateChapter(); Remember(0);
    }
    private void PreviousChapter_Click(object sender, RoutedEventArgs args) { if (chapterIndex > 0) ChapterPicker.SelectedIndex--; }
    private void NextChapter_Click(object sender, RoutedEventArgs args) { if (book is not null && chapterIndex + 1 < book.Chapters.Count) ChapterPicker.SelectedIndex++; }
    private void CloseBook_Click(object sender, RoutedEventArgs args)
    {
        book = null; bookPath = null; WelcomePanel.Visibility = Visibility.Visible;
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
    private void RefreshRecentBooks()
    {
        RecentBooksPanel.Children.Clear();
        if (device.RecentBooks.Length == 0) RecentBooksPanel.Children.Add(new TextBlock { Text = "还没有最近阅读的书籍。", Opacity = .5 });
        foreach (var recent in device.RecentBooks)
        {
            var button = new Button { Content = $"{recent.Title}  ·  第 {recent.Chapter + 1} 章", HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left, Padding = new Thickness(16, 12, 16, 12) };
            button.Click += async (_, _) => await OpenBook(recent.Path); RecentBooksPanel.Children.Add(button);
        }
    }
    private void LoadSettingsControls()
    {
        var s = device.Settings;
        ThemePicker.SelectedIndex = Array.IndexOf(new[] { "paper", "night", "sepia", "sage" }, s.Theme);
        FontSlider.Value = s.FontSize; LineSlider.Value = s.LineHeight; MarginSlider.Value = s.HorizontalMargin;
        RubyToggle.IsOn = s.ShowsFurigana; OllamaAddress.Text = s.OllamaUrl; ModelName.Text = s.Model; TargetLanguage.Text = s.ExplanationLanguage;
    }
    private void SaveSettings_Click(object sender, RoutedEventArgs args)
    {
        if (!Uri.TryCreate(OllamaAddress.Text.Trim(), UriKind.Absolute, out var address) || address.Scheme is not ("http" or "https") || string.IsNullOrWhiteSpace(ModelName.Text) || string.IsNullOrWhiteSpace(TargetLanguage.Text))
        { SettingsStatus.Text = "请输入有效的 HTTP 服务地址、模型名和解释语言。"; return; }
        var settings = DeviceStateStore.Normalize(new ReadingSettings(FontSlider.Value, LineSlider.Value, MarginSlider.Value,
            ((ComboBoxItem)ThemePicker.SelectedItem).Tag.ToString()!, RubyToggle.IsOn, address.ToString().TrimEnd('/'), ModelName.Text.Trim(), TargetLanguage.Text.Trim()));
        try { var next = device with { Settings = settings }; deviceStore.Save(next); device = next; ApplyReadingSettings(); SettingsStatus.Text = "设置已保存，当前阅读会话继续保留。"; }
        catch (Exception e) { SettingsStatus.Text = "设置保存失败：" + e.Message; }
    }
    private async void CheckConnection_Click(object sender, RoutedEventArgs args)
    {
        SettingsStatus.Text = "正在检查模型…";
        try { SettingsStatus.Text = await OllamaConnection.CheckAsync(OllamaAddress.Text, ModelName.Text); }
        catch (Exception e) { SettingsStatus.Text = "无法连接模型：" + e.Message; }
    }
}
