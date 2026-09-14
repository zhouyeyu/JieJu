namespace JieJu.Windows;

internal static class ReaderHostPolicy
{
    public const string HostName = "reader.jieju.invalid";
    public const string StartPage = "https://reader.jieju.invalid/index.html";

    public static bool AllowsResource(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri)
        && uri.Scheme == Uri.UriSchemeHttps && uri.Host == HostName && uri.IsDefaultPort
        && uri.UserInfo.Length == 0;

    public static bool AllowsNavigation(string value) => AllowsResource(value)
        && new Uri(value).AbsolutePath == "/index.html" && new Uri(value).Query.Length == 0;
}
