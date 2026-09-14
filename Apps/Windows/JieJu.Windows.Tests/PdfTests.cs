using JieJu.Windows.Infrastructure;
using Xunit;

namespace JieJu.Windows.Tests;

public sealed class PdfTests
{
    [Fact]
    public void OpensPdfWithStableContentIdentity()
    {
        var path = TemporaryPath(".pdf");
        try
        {
            File.WriteAllText(path, "%PDF-1.7\n1 0 obj<<>>endobj\n%%EOF");

            var first = PdfBook.Open(path);
            var second = PdfBook.Open(path);

            Assert.Equal(64, first.Id.Length);
            Assert.Equal(first.Id, second.Id);
            Assert.Equal(Path.GetFileNameWithoutExtension(path), first.Title);
            Assert.Equal(Path.GetFullPath(path), first.Path);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void RejectsWrongExtensionAndInvalidSignature()
    {
        var text = TemporaryPath(".txt");
        var pdf = TemporaryPath(".pdf");
        try
        {
            File.WriteAllText(text, "%PDF-1.7\n%%EOF");
            File.WriteAllText(pdf, "not a pdf");
            Assert.Throws<InvalidDataException>(() => PdfBook.Open(text));
            Assert.Throws<InvalidDataException>(() => PdfBook.Open(pdf));
        }
        finally { File.Delete(text); File.Delete(pdf); }
    }

    [Fact]
    public void RejectsPdfLargerThanConfiguredLimitWithoutReadingIt()
    {
        var path = TemporaryPath(".pdf");
        try
        {
            using (var file = File.Create(path)) file.SetLength(250L * 1024 * 1024 + 1);
            Assert.Throws<InvalidDataException>(() => PdfBook.Open(path));
        }
        finally { File.Delete(path); }
    }

    private static string TemporaryPath(string extension) =>
        Path.Combine(Path.GetTempPath(), "jieju-pdf-test-" + Guid.NewGuid() + extension);
}
