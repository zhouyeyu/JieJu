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
    private bool initialized, closed, changingChapter, chapterNavigationPending, settingsControlsLoaded, smokeFinished;
    private readonly string? smokeResult;
    private readonly bool smokeSelection;
    private readonly bool smokeInference;
    private readonly bool smokeWord;
    private readonly bool smokeDeep;
    private readonly bool smokePopup;
    private readonly bool smokeFurigana;
    private readonly bool smokeCloudSettings;
    private readonly bool smokeReadingSettings;
    private readonly bool smokePagination;
    private readonly bool smokeReview;
    private readonly bool smokePdf;
    private readonly bool smokePdfLearning;
    private readonly int? smokePdfPage;
    private bool smokePdfReopened, smokePdfLearningReturning;
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
    private string? lastPdfRequest;
    private string? bookPath;
    private int chapterIndex, epubPageIndex, epubPageCount = 1, pdfPageIndex, pdfNavigationGeneration, pdfReadyGeneration, pdfOutlineCount;
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
        smokeReadingSettings = arguments.Contains("--smoke-reading-settings");
        smokePagination = arguments.Contains("--smoke-pagination");
        smokeReview = arguments.Contains("--smoke-review");
        smokePdf = arguments.Contains("--smoke-pdf");
        smokePdfLearning = arguments.Contains("--smoke-pdf-learning");
        var smokePdfPageIndex = Array.IndexOf(arguments, "--smoke-pdf-page");
        smokePdfPage = smokePdfPageIndex >= 0 && smokePdfPageIndex + 1 < arguments.Length && int.TryParse(arguments[smokePdfPageIndex + 1], out var requestedSmokePage)
            ? Math.Max(0, requestedSmokePage) : null;
        var dataIndex = Array.IndexOf(arguments, "--data-directory");
        var dataDirectory = dataIndex >= 0 && dataIndex + 1 < arguments.Length
            ? Path.GetFullPath(arguments[dataIndex + 1])
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JieJu");
        Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", Path.Combine(dataDirectory, "WebView2"));
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
                if (e.Request.Uri.Contains("current.pdf", StringComparison.OrdinalIgnoreCase)) lastPdfRequest = e.Request.Uri;
                if (Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var requestedUri) &&
                    requestedUri.Host == "document.jieju.invalid" && requestedUri.AbsolutePath == "/current.pdf" && pdf is not null)
                {
                    var deferral = e.GetDeferral();
                    try
                    {
                        var stream = await FileRandomAccessStream.OpenAsync(pdf.Path, global::Windows.Storage.FileAccessMode.Read);
                        e.Response = environment.CreateWebResourceResponse(stream, 200, "OK",
                            $"Content-Type: application/pdf\r\nContent-Length: {pdf.Length}\r\nAccess-Control-Allow-Origin: https://reader.jieju.invalid\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store");
                    }
                    catch (Exception error)
                    {
                        ShowError("PDF 载入失败：" + error.Message);
                        e.Response = environment.CreateWebResourceResponse(null, 500, "Read failed", "");
                        if (smokePdf) FinishSmoke(false, "PDF response failed: " + error);
                    }
                    finally { deferral.Complete(); }
                }
                else if (e.Request.Uri.StartsWith(BookPrefix, StringComparison.Ordinal))
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
                            if (pdf is not null)
                            {
                                pdfReadyGeneration = pdfNavigationGeneration;
                                var readyPayload = root.GetProperty("payload");
                                pdfOutlineCount = readyPayload.TryGetProperty("outlineCount", out var outlineCount) && outlineCount.TryGetInt32(out var count) ? count : 0;
                                BookSubtitle.Text = pdfOutlineCount > 0 ? $"PDF · {pdfOutlineCount} 个目录条目" : "PDF · 无目录";
                            }
                            Status.Text = pdf is not null ? $"PDF · 第 {pdfPageIndex + 1} 页" : book is null ? "选择一本 EPUB，开始阅读。" : $"第 {chapterIndex + 1} / {book.Chapters.Count} 章";
                            ApplyReadingSettings();
                            if (book is not null) Send("restoreLocation", new { locator = new EpubLocator(book.Chapters[chapterIndex].Href, TextAnchor: JsonSerializer.Serialize(new { progress = pendingProgress })) });
                            else if (pdf is not null) Send("restoreLocation", new { locator = new PdfLocator(pdfPageIndex) });
                            if (smokePdfLearningReturning && pdf is not null)
                            {
                                await Task.Delay(200);
                                var actualPageJson = await core.ExecuteScriptAsync("document.querySelector('#pageNumber')?.value ?? ''");
                                var actualPage = JsonSerializer.Deserialize<string>(actualPageJson);
                                var expectedPage = (smokePdfPage ?? 0) + 1;
                                FinishSmoke(actualPage == expectedPage.ToString(), actualPage == expectedPage.ToString()
                                    ? "PDF explanation and vocabulary saved with page locator and returned to source"
                                    : $"PDF source return restored page {actualPage} instead of {expectedPage}");
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
                                else
                                {
                                    await core.ExecuteScriptAsync($"window.__jiejuSmokeZoom?.({(smokePdfPage ?? 0) + 1}); true");
                                    var zoomReady = false;
                                    for (var attempt = 0; attempt < 70 && !zoomReady; attempt++)
                                    {
                                        await Task.Delay(100);
                                        zoomReady = await core.ExecuteScriptAsync("window.__jiejuSmokeZoomResult === true") == "true";
                                    }
                                    if (!zoomReady)
                                    {
                                        var zoomState = await core.ExecuteScriptAsync($"(()=>{{const c=document.querySelector('.page[data-page-number=\"{(smokePdfPage ?? 0) + 1}\"] canvas');return c?{{width:c.width,height:c.height,clientWidth:c.clientWidth,clientHeight:c.clientHeight,dpr:devicePixelRatio}}:null}})()");
                                        FinishSmoke(false, "PDF canvas did not rerender sharply at 400% zoom: " + zoomState); return;
                                    }
                                    await core.ExecuteScriptAsync($"window.__jiejuSmokeSelect?.({(smokePdfPage ?? 0) + 1}); true");
                                    for (var attempt = 0; attempt < 60 && !smokeFinished; attempt++) await Task.Delay(100);
                                    if (!smokeFinished)
                                    {
                                        var layerState = await core.ExecuteScriptAsync("JSON.stringify({pages:document.querySelectorAll('.page').length,layers:document.querySelectorAll('.textLayer').length,spans:[...document.querySelectorAll('.textLayer span')].slice(0,3).map(x=>x.textContent),pageNumbers:[...document.querySelectorAll('.page')].slice(0,3).map(x=>x.dataset.pageNumber)})");
                                        FinishSmoke(false, "PDF text layer did not become selectable: " + layerState);
                                    }
                                }
                            }
                            else if (smokePagination && book is not null)
                            {
                                await Task.Delay(500);
                                var beforeJson = await core.ExecuteScriptAsync("JSON.stringify(window.__jiejuPaginationState ?? null)");
                                using var beforeDocument = JsonDocument.Parse(JsonSerializer.Deserialize<string>(beforeJson) ?? "null");
                                var before = beforeDocument.RootElement;
                                await core.ExecuteScriptAsync("dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}));true");
                                await Task.Delay(200);
                                FontSlider.Value = 26;
                                await Task.Delay(500);
                                var afterJson = await core.ExecuteScriptAsync("JSON.stringify(window.__jiejuPaginationState ?? null)");
                                using var afterDocument = JsonDocument.Parse(JsonSerializer.Deserialize<string>(afterJson) ?? "null");
                                var after = afterDocument.RootElement;
                                var ready = before.ValueKind == JsonValueKind.Object && after.ValueKind == JsonValueKind.Object
                                    && before.GetProperty("pageCount").GetInt32() > 2
                                    && after.GetProperty("page").GetInt32() > 0
                                    && after.GetProperty("pageCount").GetInt32() > 1
                                    && !after.GetProperty("isReflowing").GetBoolean()
                                    && PreviousPageButton.IsEnabled && Status.Text.Contains("本章", StringComparison.Ordinal);
                                FinishSmoke(ready, ready ? "horizontal EPUB pagination, keyboard turn, and reflow state" : $"EPUB pagination failed: before={before} after={after} status={Status.Text}");
                            }
                            else if (smokeReadingSettings && book is not null)
                            {
                                ThemePicker.SelectedIndex = 2;
                                FontSlider.Value = 27;
                                LineSlider.Value = 2.15;
                                MarginSlider.Value = 88;
                                await Task.Delay(200);
                                var json = await core.ExecuteScriptAsync("(()=>{const s=getComputedStyle(document.body);return {fontSize:s.fontSize,lineHeight:s.lineHeight,paddingLeft:s.paddingLeft,background:s.backgroundColor}})()");
                                using var styles = JsonDocument.Parse(json);
                                var result = styles.RootElement;
                                var readerReady = result.GetProperty("fontSize").GetString() == "27px" &&
                                    result.GetProperty("paddingLeft").GetString() == "88px" &&
                                    result.GetProperty("background").GetString() == "rgb(244, 236, 216)";
                                var previewReady = Math.Abs(ReadingPreviewText.FontSize - 27) < .01 &&
                                    Math.Abs(ReadingPreviewText.LineHeight - 58.05) < .01 &&
                                    Math.Abs(ReadingPreviewPage.Padding.Left - 88) < .01;
                                FinishSmoke(readerReady && previewReady, readerReady && previewReady ? "live EPUB typography and settings preview updated" : "Reading appearance did not update live");
                            }
                            else if (smokeFurigana && book is not null)
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
                            else if (smokeCloudSettings)
                            {
                                var left = SettingsContent.TransformToVisual(SettingsPage).TransformPoint(new global::Windows.Foundation.Point()).X;
                                var ready = CloudSettings.Visibility == Visibility.Visible && OllamaSettings.Visibility == Visibility.Collapsed && left <= 16;
                                FinishSmoke(ready, ready ? "Cloud provider settings visible and left aligned" : "Cloud settings layout was incorrect");
                            }
                            else if (smokeReview) await RunReviewSmokeAsync();
                            else FinishSmoke(true, environment.BrowserVersionString);
                            break;
                        case "paginationChanged":
                            if (book is null) break;
                            var pagination = root.GetProperty("payload");
                            epubPageIndex = pagination.TryGetProperty("pageIndex", out var pageIndexValue) && pageIndexValue.TryGetInt32(out var currentPage) ? Math.Max(0, currentPage) : 0;
                            epubPageCount = pagination.TryGetProperty("pageCount", out var pageCountValue) && pageCountValue.TryGetInt32(out var totalPages) ? Math.Max(1, totalPages) : 1;
                            var isReflowing = pagination.TryGetProperty("isReflowing", out var reflowingValue) && reflowingValue.ValueKind == JsonValueKind.True;
                            Status.Text = isReflowing
                                ? $"第 {chapterIndex + 1} / {book.Chapters.Count} 章 · 正在重新排版…"
                                : $"第 {chapterIndex + 1} / {book.Chapters.Count} 章 · 本章 {epubPageIndex + 1} / {epubPageCount} 页";
                            UpdatePageButtons();
                            break;
                        case "locationChanged":
                            if (pdf is not null)
                            {
                                var pdfLocator = root.GetProperty("payload").GetProperty("locator");
                                if (pdfLocator.TryGetProperty("pageIndex", out var page) && page.TryGetInt32(out var index)) RememberPdf(index);
                                var locationPayload = root.GetProperty("payload");
                                if (locationPayload.TryGetProperty("chapterTitle", out var chapterTitle) && chapterTitle.ValueKind == JsonValueKind.String)
                                    BookSubtitle.Text = $"PDF · {chapterTitle.GetString()}";
                                break;
                            }
                            if (book is null) break;
                            var locator = root.GetProperty("payload").GetProperty("locator");
                            if (locator.GetProperty("chapterHref").GetString() != book.Chapters[chapterIndex].Href) break;
                            using (var anchor = JsonDocument.Parse(locator.GetProperty("textAnchor").GetString() ?? "{}")) Remember(anchor.RootElement.GetProperty("progress").GetDouble());
                            break;
                        case "selectionChanged": HandleSelection(root.GetProperty("payload")); break;
                        case "error":
                            var readerError = root.GetProperty("payload").GetProperty("message").GetString() ?? "未知错误";
                            ShowError("阅读区域错误：" + readerError);
                            if (smokePdf) FinishSmoke(false, readerError + " | request=" + (lastPdfRequest ?? "none"));
                            break;
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
                    var generation = pdfNavigationGeneration;
                    await Task.Delay(5000);
                    if (generation == pdfNavigationGeneration && pdfReadyGeneration != generation)
                    {
                        var detail = await core.ExecuteScriptAsync("document.querySelector('#message')?.textContent || document.body?.innerText?.slice(0,200) || location.href");
                        FinishSmoke(false, "PDF reader did not become ready: " + detail);
                    }
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
    private void ApplyReadingSettings() => ApplyReadingSettings(device.Settings);
    private void ApplyReadingSettings(ReadingSettings s) => Send("configure", new { s.FontSize, s.LineHeight, s.HorizontalMargin, s.Theme, s.ShowsFurigana });
    private void ShowError(string text) { Notice.Message = text; Notice.Severity = InfoBarSeverity.Error; Notice.IsOpen = true; }
    private void FinishSmoke(bool ready, string detail) { if (smokeResult is null || smokeFinished) return; smokeFinished = true; File.WriteAllText(smokeResult, JsonSerializer.Serialize(new { ready, detail })); DispatcherQueue.TryEnqueue(Close); }
}
