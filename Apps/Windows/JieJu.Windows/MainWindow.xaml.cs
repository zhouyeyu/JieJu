using System.Text.Json;
using JieJu.Domain;
using JieJu.Windows.Infrastructure;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using global::Windows.Storage.Streams;

namespace JieJu.Windows;

public sealed partial class MainWindow : Window
{
    private bool initialized, closed, changingChapter, chapterNavigationPending;
    private readonly string? smokeResult;
    private readonly bool smokeSelection;
    private readonly bool smokeInference;
    private readonly bool smokeWord;
    private readonly bool smokeDeep;
    private readonly bool smokePopup;
    private readonly bool smokeFurigana;
    private readonly bool smokeCloudSettings;
    private readonly bool smokeReview;
    private readonly bool smokePdf;
    private bool smokePdfReopened;
    private readonly DeviceStateStore deviceStore;
    private readonly ILearningLibraryStore libraryStore;
    private readonly Func<ReadingSettings, IStreamingReadingAI> readingAIFactory;
    private readonly Func<ReadingSettings, IVocabularyAI> vocabularyAIFactory;
    private readonly IJapaneseMorphology japaneseMorphology;
    private readonly IAPIKeyStore apiKeyStore;
    private DeviceState device = new(new(), []);
    private LearningLibrary library = LearningLibrary.Empty;
    private EpubBook? book;
    private PdfBook? pdf;
    private string? pdfUrl;
    private string? bookPath;
    private int chapterIndex;
    private double pendingProgress;
    private string section = "reader";
    private const string BookPrefix = "https://reader.jieju.invalid/book/";
    private const string HtmlDataPrefix = "data:text/html;charset=utf-8;base64,";

    public MainWindow(Func<ReadingSettings, IStreamingReadingAI> readingAIFactory, Func<ReadingSettings, IVocabularyAI> vocabularyAIFactory, IJapaneseMorphology japaneseMorphology, IAPIKeyStore apiKeyStore)
    {
        this.readingAIFactory = readingAIFactory;
        this.vocabularyAIFactory = vocabularyAIFactory;
        this.japaneseMorphology = japaneseMorphology;
        this.apiKeyStore = apiKeyStore;
        InitializeComponent();
        AppWindow.Resize(new global::Windows.Graphics.SizeInt32(1280, 860));
        var arguments = Environment.GetCommandLineArgs();
        var index = Array.IndexOf(arguments, "--smoke-result");
        if (index >= 0 && index + 1 < arguments.Length) smokeResult = arguments[index + 1];
        smokeSelection = arguments.Contains("--smoke-selection");
        smokeInference = arguments.Contains("--smoke-inference");
        smokeWord = arguments.Contains("--smoke-word");
        smokeDeep = arguments.Contains("--smoke-deep");
        smokePopup = arguments.Contains("--smoke-popup");
        smokeFurigana = arguments.Contains("--smoke-furigana");
        smokeCloudSettings = arguments.Contains("--smoke-cloud-settings");
        smokeReview = arguments.Contains("--smoke-review");
        smokePdf = arguments.Contains("--smoke-pdf");
        var dataIndex = Array.IndexOf(arguments, "--data-directory");
        var dataDirectory = dataIndex >= 0 && dataIndex + 1 < arguments.Length
            ? Path.GetFullPath(arguments[dataIndex + 1])
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JieJu");
        deviceStore = new DeviceStateStore(dataDirectory);
        libraryStore = new JsonLearningLibraryStore(dataDirectory);
        try { device = deviceStore.Load(); }
        catch (Exception e) { Status.Text = "无法读取设置：" + e.Message; }
        if (smokeFurigana) device = device with { Settings = device.Settings with { ShowsFurigana = true } };
        LoadSettingsControls(); RefreshRecentBooks();
        if (smokeCloudSettings) AIProviderPicker.SelectedIndex = 1;
        Navigation.SelectedItem = Navigation.MenuItems[0];
        Closed += (_, _) => { closed = true; Reader.Close(); };
    }

    private async void Reader_Loaded(object sender, RoutedEventArgs args)
    {
        if (initialized) return;
        initialized = true;
        try
        {
            await Reader.EnsureCoreWebView2Async();
            if (closed) return;
            var core = Reader.CoreWebView2;
            var environment = core.Environment;
            core.Settings.AreHostObjectsAllowed = false;
            core.Settings.IsPasswordAutosaveEnabled = false;
            core.Settings.IsGeneralAutofillEnabled = false;
            core.SetVirtualHostNameToFolderMapping(ReaderHostPolicy.HostName, Path.Combine(AppContext.BaseDirectory, "ReaderHost"), CoreWebView2HostResourceAccessKind.Allow);
            core.NavigationStarting += (_, e) =>
            {
                e.Cancel = !AllowsPage(e.Uri);
                if (e.Uri.StartsWith(HtmlDataPrefix, StringComparison.Ordinal)) chapterNavigationPending = false;
            };
            core.NewWindowRequested += (_, e) => e.Handled = true;
            core.DownloadStarting += (_, e) => e.Cancel = true;
            core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += async (_, e) =>
            {
                if (e.Request.Uri.StartsWith(BookPrefix, StringComparison.Ordinal))
                {
                    var deferral = e.GetDeferral();
                    try
                    {
                        var path = EpubBook.ResolvePath("", new Uri(e.Request.Uri).AbsolutePath["/book/".Length..]);
                        if (book is not null && book.Resources.TryGetValue(path, out var resource) && !book.Chapters.Any(c => c.Href == path))
                        {
                            var stream = new InMemoryRandomAccessStream();
                            using (var writer = new DataWriter(stream)) { writer.WriteBytes(resource.Bytes); await writer.StoreAsync(); writer.DetachStream(); }
                            stream.Seek(0);
                            e.Response = environment.CreateWebResourceResponse(stream, 200, "OK",
                                $"Content-Type: {resource.MediaType}\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store");
                            return;
                        }
                        e.Response = environment.CreateWebResourceResponse(null, 404, "Not Found", "");
                    }
                    catch (Exception error) { ShowError("章节加载失败：" + error.Message); e.Response = environment.CreateWebResourceResponse(null, 400, "Bad Request", ""); }
                    finally { deferral.Complete(); }
                }
                else if (e.Request.Uri != pdfUrl && !ReaderHostPolicy.AllowsResource(e.Request.Uri)) e.Response = environment.CreateWebResourceResponse(null, 403, "Forbidden", "");
            };
            core.WebMessageReceived += async (_, e) =>
            {
                if (!AllowsMessageSource(e.Source)) { FinishSmoke(false, "Rejected message source: " + e.Source); return; }
                try
                {
                    using var message = JsonDocument.Parse(e.WebMessageAsJson);
                    var root = message.RootElement;
                    if (root.GetProperty("contractVersion").GetInt32() != 1) return;
                    switch (root.GetProperty("type").GetString())
                    {
                        case "ready":
                            Status.Text = book is null ? "选择一本 EPUB，开始阅读。" : $"第 {chapterIndex + 1} / {book.Chapters.Count} 章";
                            ApplyReadingSettings();
                            if (book is not null) Send("restoreLocation", new { locator = new EpubLocator(book.Chapters[chapterIndex].Href, TextAnchor: JsonSerializer.Serialize(new { progress = pendingProgress })) });
                            if (smokeFurigana && book is not null)
                            {
                                var json = await core.ExecuteScriptAsync("(()=>{const rt=document.querySelector('ruby[data-jieju-generated=\\\"true\\\"] rt');return rt?{reading:rt.textContent,display:getComputedStyle(rt).display,enabled:document.documentElement.dataset.ruby}:null})()");
                                using var visibleRuby = JsonDocument.Parse(json);
                                var rubyResult = visibleRuby.RootElement;
                                var reading = rubyResult.ValueKind == JsonValueKind.Object && rubyResult.TryGetProperty("reading", out var readingValue) ? readingValue.GetString() ?? "" : "";
                                var visible = reading.Length > 0 && rubyResult.GetProperty("display").GetString() != "none" && rubyResult.GetProperty("enabled").GetString() == "true" && FuriganaToolbarToggle.IsChecked == true;
                                FinishSmoke(visible, visible ? "Visible local furigana: " + reading : "Generated furigana was not visible");
                            }
                            else if (smokeSelection && book is not null)
                                await core.ExecuteScriptAsync($"const p=document.querySelector('{(smokeWord ? "p ruby" : "p")}');const r=document.createRange();r.selectNodeContents(p);const s=getSelection();s.removeAllRanges();s.addRange(r);document.dispatchEvent(new Event('selectionchange'));");
                            else if (smokeCloudSettings) FinishSmoke(CloudSettings.Visibility == Visibility.Visible && OllamaSettings.Visibility == Visibility.Collapsed, "Cloud provider settings visible");
                            else if (smokeReview) await RunReviewSmokeAsync();
                            else FinishSmoke(true, environment.BrowserVersionString);
                            break;
                        case "locationChanged":
                            if (book is null) break;
                            var locator = root.GetProperty("payload").GetProperty("locator");
                            if (locator.GetProperty("chapterHref").GetString() != book.Chapters[chapterIndex].Href) break;
                            using (var anchor = JsonDocument.Parse(locator.GetProperty("textAnchor").GetString() ?? "{}")) Remember(anchor.RootElement.GetProperty("progress").GetDouble());
                            break;
                        case "selectionChanged": HandleSelection(root.GetProperty("payload")); break;
                    }
                }
                catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException) { Status.Text = "阅读区域消息无法识别。"; }
            };
            core.NavigationCompleted += async (_, e) =>
            {
                if (!e.IsSuccess)
                {
                    if (e.WebErrorStatus != CoreWebView2WebErrorStatus.OperationCanceled) ShowError("阅读区域加载失败：" + e.WebErrorStatus);
                }
                else if (smokePdf && pdf is not null)
                {
                    if (!smokePdfReopened)
                    {
                        var recent = device.RecentBooks.FirstOrDefault(item => item.Id == pdf.Id && item.Kind == "pdf");
                        if (recent is null) { FinishSmoke(false, "PDF was not added to recent reading."); return; }
                        smokePdfReopened = true;
                        await OpenDocument(recent.Path);
                    }
                    else FinishSmoke(true, "restricted local PDF rendered and reopened from recent reading");
                }
            };
            core.ProcessFailed += (_, e) => ShowError("阅读区域意外关闭，请重新启动。" + e.ProcessFailedKind);
            var argsList = Environment.GetCommandLineArgs();
            var openIndex = Array.IndexOf(argsList, "--open");
            if (openIndex >= 0 && openIndex + 1 < argsList.Length) await OpenDocument(argsList[openIndex + 1]);
            else core.Navigate(ReaderHostPolicy.StartPage);
        }
        catch (Exception error) { if (!closed) { ShowError("无法启动阅读区域：" + error.Message); FinishSmoke(false, error.GetType().Name); } }
    }
    private bool AllowsPage(string value) => ReaderHostPolicy.AllowsNavigation(value) || pdf is not null && value == pdfUrl || (book is not null && (chapterNavigationPending && value.StartsWith(HtmlDataPrefix, StringComparison.Ordinal) || ReaderHostPolicy.AllowsResource(value) && book.Chapters.Any(c => BookUrl(c.Href) == value.Split('#')[0])));
    private bool AllowsMessageSource(string value) => AllowsPage(value) || (book is not null && (value == "about:blank" || value.StartsWith(HtmlDataPrefix, StringComparison.Ordinal)));
    private static string BookUrl(string href) => BookPrefix + string.Join('/', href.Split('/').Select(Uri.EscapeDataString));
    private void Send(string type, object payload) => Reader.CoreWebView2?.PostWebMessageAsJson(JsonSerializer.Serialize(new { contractVersion = 1, type, payload }, ContractJson.Options));
    private void ApplyReadingSettings() { var s = device.Settings; Send("configure", new { s.FontSize, s.LineHeight, s.HorizontalMargin, s.Theme, s.ShowsFurigana }); }
    private void ShowError(string text) { Notice.Message = text; Notice.Severity = InfoBarSeverity.Error; Notice.IsOpen = true; }
    private void FinishSmoke(bool ready, string detail) { if (smokeResult is null) return; File.WriteAllText(smokeResult, JsonSerializer.Serialize(new { ready, detail })); DispatcherQueue.TryEnqueue(Close); }
}
