namespace JieJu.Windows;

internal static class ReaderHostPolicy
{
    public const string HostName = "reader.jieju.invalid";
    public const string StartPage = "https://reader.jieju.invalid/index.html";
    public const string PdfPage = "https://reader.jieju.invalid/pdf.html";
    public const string CurrentPdf = "https://document.jieju.invalid/current.pdf";

    public static bool AllowsResource(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri)
        && uri.Scheme == Uri.UriSchemeHttps && uri.Host == HostName && uri.IsDefaultPort
        && uri.UserInfo.Length == 0;

    public static bool AllowsNavigation(string value) => AllowsResource(value)
        && new Uri(value).AbsolutePath is "/index.html" or "/pdf.html" && new Uri(value).Query.Length == 0;
}
