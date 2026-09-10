using System.Text.Json;
using JieJu.Domain;
using Microsoft.UI.Xaml;
using Microsoft.Web.WebView2.Core;

namespace JieJu.Windows;

public sealed partial class MainWindow : Window
{
    private bool initialized;
    private bool closed;
    private readonly string? smokeResult;

    public MainWindow()
    {
        InitializeComponent();
        AppWindow.Resize(new global::Windows.Graphics.SizeInt32(1100, 760));
        var arguments = Environment.GetCommandLineArgs();
        var index = Array.IndexOf(arguments, "--smoke-result");
        if (index >= 0 && index + 1 < arguments.Length) smokeResult = arguments[index + 1];
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
            core.SetVirtualHostNameToFolderMapping(ReaderHostPolicy.HostName,
                Path.Combine(AppContext.BaseDirectory, "ReaderHost"), CoreWebView2HostResourceAccessKind.DenyCors);
            core.NavigationStarting += (_, e) => e.Cancel = !ReaderHostPolicy.AllowsNavigation(e.Uri);
            core.NewWindowRequested += (_, e) => e.Handled = true;
            core.DownloadStarting += (_, e) => e.Cancel = true;
            core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += (_, e) =>
            {
                if (!ReaderHostPolicy.AllowsResource(e.Request.Uri))
                    e.Response = environment.CreateWebResourceResponse(null, 403, "Forbidden", "");
            };
            core.WebMessageReceived += (_, e) =>
            {
                if (!ReaderHostPolicy.AllowsNavigation(e.Source)) return;
                try
                {
                    var message = ContractJson.Deserialize<ReaderMessage<ReaderReady>>(e.WebMessageAsJson);
                    if (message.ContractVersion != 1 || message.Type != "ready" || message.Payload.ReaderKind != "epub") return;
                    Status.Text = "阅读区域已就绪 · Windows 开发预览";
                    FinishSmoke(true, environment.BrowserVersionString);
                }
                catch (JsonException) { Status.Text = "阅读区域消息无法识别，请重新启动。"; }
            };
            core.NavigationCompleted += (_, e) =>
            {
                if (!e.IsSuccess) Fail("阅读区域加载失败，请重新启动。", e.WebErrorStatus.ToString());
            };
            core.ProcessFailed += (_, e) => Fail("阅读区域意外关闭，请重新启动。", e.ProcessFailedKind.ToString());
            core.Navigate(ReaderHostPolicy.StartPage);
        }
        catch (Exception error)
        {
            if (!closed) Fail("无法启动阅读区域。请确认已安装 Microsoft Edge WebView2 Runtime。", error.GetType().Name);
        }
    }

    private void Fail(string text, string detail)
    {
        Status.Text = text;
        FinishSmoke(false, detail);
    }

    private void FinishSmoke(bool ready, string detail)
    {
        if (smokeResult is null) return;
        File.WriteAllText(smokeResult, JsonSerializer.Serialize(new { ready, detail }));
        DispatcherQueue.TryEnqueue(Close);
    }
}
