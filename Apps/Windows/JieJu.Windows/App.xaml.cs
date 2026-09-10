using Microsoft.UI.Xaml;
using JieJu.Windows.Infrastructure;

namespace JieJu.Windows;

public partial class App : Application
{
    private Window? window;
    private readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(70) };
    public App() => InitializeComponent();
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        window = new MainWindow(settings => new OllamaReadingAI(http, settings.OllamaUrl, settings.Model));
        window.Activate();
    }
}
