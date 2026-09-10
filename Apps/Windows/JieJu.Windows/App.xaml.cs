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
        var japanese = new MeCabJapaneseMorphology();
        var credentials = new WindowsCredentialStore();
        window = new MainWindow(
            settings => new LocalJapaneseReadingAI(settings.Provider == "cloud"
                ? new OpenAICompatibleReadingAI(http, settings.CloudUrl, credentials.Load(), settings.CloudModel)
                : new OllamaReadingAI(http, settings.OllamaUrl, settings.Model), japanese),
            settings => new LocalJapaneseVocabularyAI(settings.Provider == "cloud"
                ? new OpenAICompatibleVocabularyAI(http, settings.CloudUrl, credentials.Load(), settings.CloudModel)
                : new OllamaVocabularyAI(http, settings.OllamaUrl, settings.Model), japanese),
            japanese, credentials);
        window.Activate();
    }
}
