using Xunit;

namespace JieJu.Windows.Tests;

public class ReaderHostPolicyTests
{
    [Theory]
    [InlineData("https://reader.jieju.invalid/index.html", true)]
    [InlineData("https://reader.jieju.invalid/pdf.html", true)]
    [InlineData("https://reader.jieju.invalid/shell.mjs", true)]
    [InlineData("https://reader.jieju.invalid.evil.example/index.html", false)]
    [InlineData("https://reader.jieju.invalid@evil.example/index.html", false)]
    [InlineData("https://user@reader.jieju.invalid/index.html", false)]
    [InlineData("https://reader.jieju.invalid:8443/index.html", false)]
    [InlineData("http://reader.jieju.invalid/index.html", false)]
    [InlineData("http://127.0.0.1:11434", false)]
    [InlineData("file:///C:/private/book.epub", false)]
    [InlineData("data:text/html,hello", false)]
    public void OnlyPackagedReaderResourcesAreAllowed(string uri, bool allowed)
        => Assert.Equal(allowed, ReaderHostPolicy.AllowsResource(uri));

    [Theory]
    [InlineData("https://reader.jieju.invalid/index.html", true)]
    [InlineData("https://reader.jieju.invalid/index.html#reading", true)]
    [InlineData("https://reader.jieju.invalid/index.html?remote=true", false)]
    [InlineData("https://reader.jieju.invalid/shell.mjs", false)]
    [InlineData("https://document.jieju.invalid/current.pdf", false)]
    [InlineData("https://example.com/", false)]
    public void NavigationStaysOnTheReaderPage(string uri, bool allowed)
        => Assert.Equal(allowed, ReaderHostPolicy.AllowsNavigation(uri));
}
