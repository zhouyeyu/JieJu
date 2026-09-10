using System.Text.Json.Serialization;

namespace JieJu.Domain;

[JsonPolymorphic(TypeDiscriminatorPropertyName = "kind")]
[JsonDerivedType(typeof(PdfLocator), "pdf")]
[JsonDerivedType(typeof(EpubLocator), "epub")]
public abstract record DocumentLocator;
public sealed record PdfLocator(int PageIndex, int? TextOffset = null, string? TextHash = null) : DocumentLocator;
// textAnchor is an opaque string in v1. Do not replace it with a platform object.
public sealed record EpubLocator(string ChapterHref, string? Cfi = null, string? TextAnchor = null,
    int? DisplayPageIndex = null) : DocumentLocator;
public sealed record ReaderRect(double X, double Y, double Width, double Height);
public sealed record ReaderReady(string ReaderKind);
public sealed record ReaderMessage<T>(int ContractVersion, string Type, T Payload);
