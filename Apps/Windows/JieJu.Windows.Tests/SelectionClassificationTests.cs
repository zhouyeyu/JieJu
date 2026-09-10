using JieJu.Domain;
using Xunit;

namespace JieJu.Windows.Tests;

public sealed class SelectionClassificationTests
{
    [Theory]
    [InlineData("book", "English", SelectionKind.Word)]
    [InlineData("take part in", "English", SelectionKind.Expression)]
    [InlineData("She opened the book.", "English", SelectionKind.Sentence)]
    [InlineData("One sentence. Another sentence.", "English", SelectionKind.Passage)]
    [InlineData("飛行機", "ja", SelectionKind.Word)]
    [InlineData("本を読んで", "ja", SelectionKind.Expression)]
    public void ClassifiesCommonSelections(string text, string language, SelectionKind expected) =>
        Assert.Equal(expected, SelectionClassifier.Classify(text, language));

    [Fact]
    public void SuggestsACompleteEnglishTokenConservatively()
    {
        var result = SelectionClassifier.SuggestBoundary("light", "The flight arrived early.", "English");
        Assert.Equal("flight", result?.SuggestedText);
        Assert.Null(SelectionClassifier.SuggestBoundary("the", "the word and the book", "English"));
        Assert.Null(SelectionClassifier.SuggestBoundary("行機", "その飛行機は降下した。", "ja"));
    }
}
