using System.IO.Compression;
using System.Text;
using System.Xml.Linq;
using JieJu.Domain;
using JieJu.Windows.Infrastructure;
using Xunit;

namespace JieJu.Windows.Tests;

public sealed class EpubTests
{
    [Theory]
    [InlineData("../outside")]
    [InlineData("%2e%2e/outside")]
    [InlineData("C:/private")]
    [InlineData("//example.com/a")]
    [InlineData("https://example.com/a")]
    [InlineData("folder\\a")]
    public void RejectsUnsafePaths(string path) => Assert.Throws<InvalidDataException>(() => EpubBook.ResolvePath("", path));

    [Fact]
    public void ResolvesValidParentRelativeResourceAndUnicode()
    {
        Assert.Equal("OPS/Images/表紙.png", EpubBook.ResolvePath("OPS/Text/", "../Images/%E8%A1%A8%E7%B4%99.png"));
    }

    [Fact]
    public void ReadsBookMetadataSpineAndOnlyDeclaredResources()
    {
        WithBook(null, path =>
        {
            var book = EpubBook.Open(path);
            Assert.Equal("A quiet afternoon", book.Title);
            Assert.Equal("en", book.Language);
            Assert.Equal(2, book.Chapters.Count);
            Assert.Equal("OPS/second.xhtml", book.Chapters[1].Href);
            Assert.Equal(64, book.Id.Length);
            Assert.DoesNotContain("private.txt", book.Resources.Keys);
        });
    }

    [Fact]
    public void ReplacesUnknownHtmlTitleWithFirstConciseBodyBlock()
    {
        WithBook((_, files) => files["OPS/first.xhtml"] =
            "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Unknown</title></head><body><p>第一章</p><p>これは章の本文です。</p></body></html>", path =>
        {
            var book = EpubBook.Open(path);
            Assert.Equal("第一章", book.Chapters[0].Title);
        });
    }

    [Fact]
    public void UsesNcxNavigationLabelBeforeGenericDocumentTitle()
    {
        WithBook((_, files) =>
        {
            files["OPS/package.opf"] = files["OPS/package.opf"]
                .Replace("<manifest>", "<manifest><item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>")
                .Replace("<spine>", "<spine toc=\"ncx\">");
            files["OPS/toc.ncx"] = "<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\"><navMap><navPoint><navLabel><text>森の入口</text></navLabel><content src=\"first.xhtml\"/></navPoint></navMap></ncx>";
            files["OPS/first.xhtml"] = "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Unknown</title></head><body><p>本文</p></body></html>";
        }, path => Assert.Equal("森の入口", EpubBook.Open(path).Chapters[0].Title));
    }

    [Fact]
    public void RemovesActiveBookContentAndPreservesRubyAndImages()
    {
        WithBook(null, path =>
        {
            var html = Encoding.UTF8.GetString(EpubBook.Open(path).RenderChapter(0));
            Assert.DoesNotContain("alert(", html);
            Assert.DoesNotContain("onclick", html);
            Assert.DoesNotContain("<iframe", html);
            Assert.Contains("<ruby>", html);
            Assert.Contains("book.css", html);
            Assert.Contains("book.mjs", html);
            Assert.Contains("Content-Security-Policy", html);
            Assert.Contains("charset=\"utf-8\"", html);
            Assert.Contains("https://reader.jieju.invalid/book/OPS/", html);
        });
    }

    [Fact]
    public void MissingSpineReferenceFailsClearly() => WithBook((_, files) => files["OPS/package.opf"] = files["OPS/package.opf"].Replace("idref=\"second\"", "idref=\"missing\""), path => Assert.Throws<InvalidDataException>(() => EpubBook.Open(path)));

    [Fact]
    public void ArchiveTraversalFailsBeforeServingResources() => WithBook((_, files) => files["../private"] = "bad", path => Assert.Throws<InvalidDataException>(() => EpubBook.Open(path)));

    [Fact]
    public void InvalidXmlCannotExpandExternalEntities() => Assert.ThrowsAny<Exception>(() => EpubBook.ParseXml(Encoding.UTF8.GetBytes("<!DOCTYPE a [<!ENTITY x SYSTEM 'file:///private'>]><a>&x;</a>")));

    [Fact]
    public void GeneratesRubyOnlyForJapaneseTextAndKeepsExistingRuby()
    {
        var document = XDocument.Parse("<html lang=\"ja\"><head><title>本</title></head><body><p>彼女は本を読む。</p><p><ruby>今日<rt>きょう</rt></ruby></p><script>学校</script></body></html>");
        var morphology = new StubMorphology(new Dictionary<string, JapaneseToken[]>
        {
            ["彼女は本を読む。"] = [Token("彼女", "かのじょ"), Token("は", "は"), Token("本", "ほん"), Token("を", "を"), Token("読む", "よむ"), Token("。", "。")]
        });

        Assert.True(EpubFuriganaAnnotator.Annotate(document, "ja", morphology));
        var generated = document.Descendants("ruby").Where(element => (string?)element.Attribute("data-jieju-generated") == "true").ToArray();
        Assert.Equal(["彼女", "本", "読む"], generated.Select(element => ((XText)element.FirstNode!).Value));
        Assert.Single(document.Descendants("rt"), element => element.Value == "きょう");
        Assert.Equal("学校", document.Descendants("script").Single().Value);
    }

    [Fact]
    public void SkipsAmbiguousReadingsAndNonJapaneseChapters()
    {
        var ambiguous = XDocument.Parse("<html lang=\"ja\"><body><p>今日 今日</p></body></html>");
        var morphology = new StubMorphology(new Dictionary<string, JapaneseToken[]>
        {
            ["今日 今日"] = [Token("今日", "きょう"), Token("今日", "こんにち")]
        });
        Assert.False(EpubFuriganaAnnotator.Annotate(ambiguous, "ja", morphology));
        Assert.Empty(ambiguous.Descendants("ruby"));

        var chinese = XDocument.Parse("<html lang=\"zh-CN\"><body><p>今天学习中文，也引用日本語。</p></body></html>");
        Assert.False(EpubFuriganaAnnotator.Annotate(chinese, "zh-CN", morphology));
    }

    [Fact]
    public void StrongJapaneseTextOverridesIncorrectEnglishMetadata()
    {
        Assert.True(EpubFuriganaAnnotator.IsJapaneseChapter("en", "en", "彼女は東京の学校で日本語を勉強していました。明日も先生と本を読みます。"));
        Assert.False(EpubFuriganaAnnotator.IsJapaneseChapter("en", "en", "This English text only quotes 日本語 once."));
    }

    [Fact]
    public void RenderedJapaneseChapterContainsLocalDictionaryRuby()
    {
        WithBook((_, files) =>
        {
            files["OPS/package.opf"] = files["OPS/package.opf"].Replace("<language>en</language>", "<language>ja</language>");
            files["OPS/first.xhtml"] = "<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"ja\"><head><title>読書</title></head><body><p>彼女は本を読みます。</p></body></html>";
        }, path =>
        {
            using var morphology = new MeCabJapaneseMorphology();
            var html = Encoding.UTF8.GetString(EpubBook.Open(path).RenderChapter(0, morphology));
            Assert.Contains("data-jieju-generated=\"true\"", html);
            Assert.Contains("<rt>かのじょ</rt>", html);
            Assert.Contains("<rt>ほん</rt>", html);
        });
    }

    private static void WithBook(Action<string, Dictionary<string, string>>? modify, Action<string> assertion)
    {
        var path = Path.Combine(Path.GetTempPath(), "jieju-test-" + Guid.NewGuid() + ".epub");
        var files = DemoFiles(); modify?.Invoke(path, files);
        try
        {
            using (var zip = ZipFile.Open(path, ZipArchiveMode.Create))
                foreach (var pair in files) { using var writer = new StreamWriter(zip.CreateEntry(pair.Key).Open()); writer.Write(pair.Value); }
            assertion(path);
        }
        finally { File.Delete(path); }
    }

    public static Dictionary<string, string> DemoFiles() => new()
    {
        ["META-INF/container.xml"] = "<container><rootfiles><rootfile full-path=\"OPS/package.opf\"/></rootfiles></container>",
        ["OPS/package.opf"] = "<package><metadata><title>A quiet afternoon</title><language>en</language></metadata><manifest><item id=\"first\" href=\"first.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"second\" href=\"second.xhtml\" media-type=\"application/xhtml+xml\"/></manifest><spine><itemref idref=\"first\"/><itemref idref=\"second\"/></spine></package>",
        ["OPS/first.xhtml"] = "<html xmlns=\"http://www.w3.org/1999/xhtml\" onload=\"alert('root')\"><head><title>A quiet afternoon</title><script>alert('bad')</script></head><body><h1>A quiet afternoon</h1><p onclick=\"alert('bad')\">She opened the book and found a world waiting between its pages.</p><p>Outside, the rain softened the sound of the city. She had nowhere else to be.</p><p>Learning a language takes time. A little reading, a little remembering, and a little forgetting are all part of the journey.</p><p>彼女は<ruby>本<rt>ほん</rt></ruby>を読みます。</p><iframe src=\"https://example.com\"/></body></html>",
        ["OPS/second.xhtml"] = "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>The next page</title></head><body><h1>The next page</h1><p>Every page offers another chance to understand.</p></body></html>",
        ["private.txt"] = "not declared"
    };

    private static JapaneseToken Token(string surface, string reading) => new(surface, reading, surface, "noun", false);

    private sealed class StubMorphology(Dictionary<string, JapaneseToken[]> values) : IJapaneseMorphology
    {
        public IReadOnlyList<JapaneseToken> Tokenize(string text) => values.GetValueOrDefault(text, []);
        public IReadOnlyList<JapaneseReadingSegment> ReadingSegments(string text) => [];
    }
}
