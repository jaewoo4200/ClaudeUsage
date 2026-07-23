using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Xml.Linq;
using ClaudeUsage.Core.History;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using ClaudeUsage.Windows.Views;

namespace ClaudeUsage.Windows.Tests;

public sealed class SettingsWindowParityTests
{
    [Fact]
    public void SettingsScrollIndicatorOverlaysWithoutReducingTheContentViewport()
    {
        RunOnStaThread(() =>
        {
            var historyPath = Path.Combine(
                Path.GetTempPath(),
                $"claudeusage-settings-overlay-{Guid.NewGuid():N}.json");
            var settings = new AppSettings
            {
                Appearance = AppearanceMode.Light,
                Language = AppLanguage.English,
            };
            var usage = new UsageViewModel(settings);
            var companion = new CompanionViewModel(language: AppLanguage.English);
            var history = new UsageHistoryService(new UsageHistoryStore(historyPath));
            using var viewModel = new SettingsViewModel(
                settings,
                usage,
                history,
                companion,
                persistChanges: false);
            var window = new SettingsWindow(viewModel);

            try
            {
                var surface = Assert.IsType<Grid>(window.FindName("SettingsSurface"));
                var scroll = Assert.IsType<ScrollViewer>(window.FindName("SettingsScroll"));
                surface.Measure(new Size(420, 600));
                surface.Arrange(new Rect(0, 0, 420, 600));
                surface.UpdateLayout();
                _ = scroll.ApplyTemplate();
                scroll.UpdateLayout();

                var presenter = Assert.IsType<ScrollContentPresenter>(
                    scroll.Template.FindName("PART_ScrollContentPresenter", scroll));
                var indicator = Assert.IsType<ScrollBar>(
                    scroll.Template.FindName("PART_VerticalScrollBar", scroll));

                Assert.Equal(420, scroll.ActualWidth, precision: 3);
                Assert.Equal(scroll.ActualWidth, presenter.ActualWidth, precision: 3);
                Assert.Equal(5, indicator.ActualWidth, precision: 3);
                Assert.True(
                    presenter.ActualWidth + indicator.ActualWidth > scroll.ActualWidth,
                    "The vertical indicator must overlay the viewport instead of reserving a column.");
                Assert.Equal(Visibility.Visible, indicator.Visibility);
                Assert.False(indicator.Focusable);
                Assert.False(indicator.IsTabStop);

                Assert.True(scroll.ScrollableHeight > 0);
                scroll.LineDown();
                scroll.UpdateLayout();
                Assert.True(scroll.VerticalOffset > 0);
            }
            finally
            {
                window.Close();
                ThemeResourceManager.Shutdown();
                if (File.Exists(historyPath))
                {
                    File.Delete(historyPath);
                }
            }
        });
    }

    [Fact]
    public void SettingsOverlayIndicatorUsesTheFullSystemThumbInHighContrast()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace xaml = "http://schemas.microsoft.com/winfx/2006/xaml";
        var document = LoadSettingsXaml();
        var scrollBarStyle = LocalStyle(document, presentation, xaml, "SettingsOverlayScrollBar");
        var highContrastTrigger = scrollBarStyle.Descendants(presentation + "DataTrigger").Single(trigger =>
            ((string?)trigger.Attribute("Binding"))?.Contains(
                "SystemParameters.HighContrast",
                StringComparison.Ordinal) == true);

        Assert.Contains(highContrastTrigger.Elements(presentation + "Setter"), setter =>
            (string?)setter.Attribute("TargetName") == "ThumbChrome"
            && (string?)setter.Attribute("Property") == "Width"
            && (string?)setter.Attribute("Value") == "5");
        Assert.Contains(highContrastTrigger.Elements(presentation + "Setter"), setter =>
            (string?)setter.Attribute("TargetName") == "ThumbChrome"
            && (string?)setter.Attribute("Property") == "Opacity"
            && (string?)setter.Attribute("Value") == "1");
    }

    [Fact]
    public void CompanionSelectorMatchesTheMacSelectionAndTypographyContract()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace xaml = "http://schemas.microsoft.com/winfx/2006/xaml";
        var document = LoadSettingsXaml();

        var companionStyle = document.Descendants(presentation + "Style").Single(element =>
            (string?)element.Attribute(xaml + "Key") == "CompanionItem");
        var selectionFill = companionStyle.Descendants(presentation + "Border").Single(element =>
            (string?)element.Attribute(xaml + "Name") == "CompanionSelectionFill");
        var outline = companionStyle.Descendants(presentation + "Border").Single(element =>
            (string?)element.Attribute(xaml + "Name") == "CompanionBorder");
        var selectedTrigger = companionStyle.Descendants(presentation + "Trigger").Single(element =>
            (string?)element.Attribute("Property") == "IsSelected"
            && (string?)element.Attribute("Value") == "True");

        Assert.Equal("{DynamicResource AccentBrush}", (string?)selectionFill.Attribute("Background"));
        Assert.Equal("0", (string?)selectionFill.Attribute("Opacity"));
        Assert.Equal("6", (string?)selectionFill.Attribute("CornerRadius"));
        Assert.Equal("6", (string?)outline.Attribute("CornerRadius"));
        Assert.Contains(selectedTrigger.Elements(presentation + "Setter"), setter =>
            (string?)setter.Attribute("TargetName") == "CompanionSelectionFill"
            && (string?)setter.Attribute("Property") == "Opacity"
            && (string?)setter.Attribute("Value") == "0.12");
        Assert.Contains(selectedTrigger.Elements(presentation + "Setter"), setter =>
            (string?)setter.Attribute("TargetName") == "CompanionBorder"
            && (string?)setter.Attribute("Property") == "BorderBrush"
            && (string?)setter.Attribute("Value") == "{DynamicResource AccentBrush}");
        Assert.Contains(selectedTrigger.Elements(presentation + "Setter"), setter =>
            (string?)setter.Attribute("TargetName") == "CompanionBorder"
            && (string?)setter.Attribute("Property") == "BorderThickness"
            && (string?)setter.Attribute("Value") == "1.5");

        var selectorHeader = document.Descendants(presentation + "Grid").Single(element =>
            (string?)element.Attribute(xaml + "Name") == "CompanionSelectorHeader");
        Assert.Equal("12,12,12,5", (string?)selectorHeader.Attribute("Margin"));
        Assert.Equal("3", SetterValue(companionStyle, presentation, "Margin"));
        Assert.Equal(
            "10",
            (string?)selectorHeader.Elements(presentation + "Grid.ColumnDefinitions")
                .Elements(presentation + "ColumnDefinition")
                .ElementAt(1)
                .Attribute("Width"));

        var headerDescriptionStyle = LocalStyle(document, presentation, xaml, "CompanionSelectorDescription");
        var selectedDescriptionStyle = LocalStyle(document, presentation, xaml, "SelectedCompanionDescription");
        var sectionHeaderStyle = LocalStyle(document, presentation, xaml, "SectionHeader");
        Assert.Equal("10", SetterValue(headerDescriptionStyle, presentation, "FontSize"));
        Assert.Equal("Medium", SetterValue(selectedDescriptionStyle, presentation, "FontWeight"));
        Assert.Equal("SemiExpanded", SetterValue(sectionHeaderStyle, presentation, "FontStretch"));

        var selectedDescription = document.Descendants(presentation + "TextBlock").Single(element =>
            (string?)element.Attribute(xaml + "Name") == "SelectedCompanionDescriptionText");
        Assert.Equal(
            "{StaticResource SelectedCompanionDescription}",
            (string?)selectedDescription.Attribute("Style"));
        foreach (var pickerDescriptionName in new[]
                 {
                     "CompanionSensitivityDescriptionText",
                     "CompanionAnimationDescriptionText",
                 })
        {
            var pickerDescription = document.Descendants(presentation + "TextBlock").Single(element =>
                (string?)element.Attribute(xaml + "Name") == pickerDescriptionName);
            Assert.Equal(
                "{StaticResource CompanionSelectorDescription}",
                (string?)pickerDescription.Attribute("Style"));
        }
        Assert.Equal("13", SetterValue(headerDescriptionStyle, presentation, "LineHeight"));
    }

    [Fact]
    public void SettingsActionIconsUseSemanticDecorativeVectors()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace xaml = "http://schemas.microsoft.com/winfx/2006/xaml";
        var settingsPath = FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Views",
            "SettingsWindow.xaml");
        var settingsText = File.ReadAllText(settingsPath);
        var document = XDocument.Parse(settingsText);

        foreach (var forbiddenGlyph in new[] { "↗", "⌫" })
        {
            Assert.DoesNotContain(forbiddenGlyph, settingsText, StringComparison.Ordinal);
        }

        var iconSpecs = new[]
        {
            (
                ButtonName: "OpenHistoryButton",
                IconName: "OpenHistoryChartIcon",
                AutomationName: "{DynamicResource Settings.OpenHistory}",
                Style: "{StaticResource SettingsPlainIconButton}",
                Margin: (string?)"0,0,3,0",
                MinimumFigures: 2),
            (
                ButtonName: "ClearHistoryButton",
                IconName: "ClearHistoryTrashIcon",
                AutomationName: "{DynamicResource Settings.ClearHistory}",
                Style: "{StaticResource SettingsPlainIconButton}",
                Margin: (string?)"0,0,12,0",
                MinimumFigures: 5),
            (
                ButtonName: "OpenCodexUsageButton",
                IconName: "OpenCodexExternalLinkIcon",
                AutomationName: "{DynamicResource Settings.OpenUsagePage}",
                Style: "{StaticResource CompactButton}",
                Margin: (string?)null,
                MinimumFigures: 3),
        };

        foreach (var spec in iconSpecs)
        {
            var button = document.Descendants(presentation + "Button").Single(element =>
                (string?)element.Attribute(xaml + "Name") == spec.ButtonName);
            Assert.Null(button.Attribute("Content"));
            Assert.Equal(spec.Style, (string?)button.Attribute("Style"));
            Assert.Equal(spec.Margin, (string?)button.Attribute("Margin"));
            Assert.Equal(
                spec.AutomationName,
                (string?)button.Attribute("AutomationProperties.Name"));
            Assert.Equal(spec.AutomationName, (string?)button.Attribute("ToolTip"));

            var icon = button.Elements(presentation + "Path").Single();
            Assert.Equal(spec.IconName, (string?)icon.Attribute(xaml + "Name"));
            Assert.Equal("12", (string?)icon.Attribute("Width"));
            Assert.Equal("12", (string?)icon.Attribute("Height"));
            Assert.Equal("Uniform", (string?)icon.Attribute("Stretch"));
            Assert.Equal(
                "{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}",
                (string?)icon.Attribute("Stroke"));
            Assert.Equal("1.5", (string?)icon.Attribute("StrokeThickness"));
            Assert.Equal("Round", (string?)icon.Attribute("StrokeStartLineCap"));
            Assert.Equal("Round", (string?)icon.Attribute("StrokeEndLineCap"));
            Assert.Equal("Round", (string?)icon.Attribute("StrokeLineJoin"));
            Assert.Equal("False", (string?)icon.Attribute("Focusable"));
            Assert.Equal("False", (string?)icon.Attribute("IsHitTestVisible"));
            Assert.DoesNotContain(
                icon.Attributes(),
                attribute => attribute.Name.LocalName.StartsWith(
                    "AutomationProperties.",
                    StringComparison.Ordinal));

            var data = Assert.IsType<string>((string?)icon.Attribute("Data"));
            var geometry = System.Windows.Media.Geometry.Parse(data).GetFlattenedPathGeometry();
            Assert.True(
                geometry.Figures.Count >= spec.MinimumFigures,
                $"{spec.IconName} should retain its semantic vector detail.");
            Assert.True(
                geometry.Bounds.Width >= 8 && geometry.Bounds.Height >= 8,
                $"{spec.IconName} should occupy the 12x12 icon canvas.");
        }
    }

    private static XDocument LoadSettingsXaml() => XDocument.Load(FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Views",
            "SettingsWindow.xaml"));

    private static XElement LocalStyle(
        XDocument document,
        XNamespace presentation,
        XNamespace xaml,
        string key) => document.Descendants(presentation + "Style").Single(element =>
            (string?)element.Attribute(xaml + "Key") == key);

    private static string? SetterValue(
        XElement style,
        XNamespace presentation,
        string property) => (string?)style.Elements(presentation + "Setter")
        .Single(setter => (string?)setter.Attribute("Property") == property)
        .Attribute("Value");

    private static string FindRepositoryFile(params string[] segments)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine([directory.FullName, .. segments]);
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException($"Could not locate {Path.Combine(segments)}.");
    }

    private static void RunOnStaThread(Action action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                action();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
        })
        {
            IsBackground = true,
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(30)), "The Settings window test timed out.");

        if (failure is not null)
        {
            System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }
}
