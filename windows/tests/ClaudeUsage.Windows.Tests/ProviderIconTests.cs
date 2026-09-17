using ClaudeUsage.Windows.Controls;

namespace ClaudeUsage.Windows.Tests;

public sealed class ProviderIconTests
{
    [Fact]
    public void CodexPaletteRejectsGenericMonochromeApplicationIcons()
    {
        var pixels = Enumerable.Repeat(new byte[] { 180, 180, 180, 255 }, 100)
            .SelectMany(pixel => pixel)
            .ToArray();

        Assert.False(ProviderBrandIconLoader.HasCodexBrandPalette(pixels));
    }

    [Fact]
    public void CodexPaletteAcceptsTheBluePurpleProviderMark()
    {
        var pixels = Enumerable.Repeat(new byte[] { 245, 245, 245, 255 }, 97)
            .SelectMany(pixel => pixel)
            .Concat(Enumerable.Repeat(new byte[] { 244, 75, 53, 255 }, 3)
                .SelectMany(pixel => pixel))
            .ToArray();

        Assert.True(ProviderBrandIconLoader.HasCodexBrandPalette(pixels));
    }
}
