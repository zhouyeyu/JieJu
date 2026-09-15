using System.Security.Cryptography;

namespace JieJu.Windows.Infrastructure;

public sealed record PdfBook(string Id, string Title, string FileName, string Path, long Length)
{
    private const long MaximumLength = 250L * 1024 * 1024;

    public static PdfBook Open(string path)
    {
        var fullPath = System.IO.Path.GetFullPath(path);
        if (!string.Equals(System.IO.Path.GetExtension(fullPath), ".pdf", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("请选择 PDF 文件。");
        using var stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length < 5) throw new InvalidDataException("PDF 文件为空或不完整。");
        if (stream.Length > MaximumLength) throw new InvalidDataException("PDF 超过当前支持的 250 MB，请先使用较小的文件。");
        Span<byte> signature = stackalloc byte[5];
        if (stream.Read(signature) != signature.Length || !signature.SequenceEqual("%PDF-"u8))
            throw new InvalidDataException("文件不是有效的 PDF。");
        stream.Position = 0;
        var id = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        var fileName = System.IO.Path.GetFileName(fullPath);
        return new PdfBook(id, System.IO.Path.GetFileNameWithoutExtension(fileName), fileName, fullPath, stream.Length);
    }
}
