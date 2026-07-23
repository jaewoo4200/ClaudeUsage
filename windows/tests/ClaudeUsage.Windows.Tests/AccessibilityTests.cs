using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Media;
using System.Xml;
using System.Xml.Linq;
using ClaudeUsage.Windows.Accessibility;
using ClaudeUsage.Windows.Controls;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using ClaudeUsage.Core.Models;

namespace ClaudeUsage.Windows.Tests;

public sealed class AccessibilityTests
{
    private static readonly string[] HighContrastBrushKeys =
    [
        "WindowBackgroundBrush",
        "SurfaceBrush",
        "WidgetPanelBackgroundBrush",
        "SecondarySurfaceBrush",
        "WidgetSecondarySurfaceBrush",
        "MetricCardBackgroundBrush",
        "PrimaryTextBrush",
        "SecondaryTextBrush",
        "TertiaryTextBrush",
        "TrackBrush",
        "BorderBrush",
        "DividerBrush",
        "AccentBrush",
        "AccentSecondaryBrush",
        "AccentMutedBrush",
        "AccentForegroundBrush",
        "SwitchThumbBrush",
        "WarningBrush",
        "DangerBrush",
        "SuccessBrush",
        "MetricTrackBrush",
        "WarningTrackBrush",
        "DangerTrackBrush",
        "ClaudeProviderBrush",
        "CodexProviderBrush",
        "AppIconGradientBrush",
        "AccentGradientBrush",
        "WarningGradientBrush",
        "DangerGradientBrush",
        "LoginWindowBackgroundBrush",
        "LoginChromeBackgroundBrush",
        "LoginBorderBrush",
        "LoginPrimaryTextBrush",
        "LoginSecondaryTextBrush",
        "LoginNoticeBackgroundBrush",
        "LoginNoticeBorderBrush",
        "LoginNoticeTextBrush",
        "LoginWebSurfaceBrush",
        "LoginWebBorderBrush",
    ];

    [Fact]
    public void HighContrastOverlayLoadsLastAndProvidesEverySemanticBrush()
    {
        RunSta(() =>
        {
            var resources = new ResourceDictionary();
            var settings = new AppSettings
            {
                Appearance = AppearanceMode.Light,
                Theme = ThemeKind.Hybrid,
                Language = AppLanguage.English,
            };

            ThemeResourceManager.ApplyResources(resources, settings, highContrast: true);

            Assert.Equal(4, resources.MergedDictionaries.Count);
            var overlay = resources.MergedDictionaries[^1];
            Assert.EndsWith(
                ThemeResourceManager.HighContrastDictionaryPath,
                ThemeResourceManager.GetResourcePath(overlay),
                StringComparison.OrdinalIgnoreCase);

            foreach (var key in HighContrastBrushKeys)
            {
                Assert.True(overlay.Contains(key), $"Missing High Contrast resource: {key}");
                Assert.IsAssignableFrom<Brush>(overlay[key]);
            }

            Assert.Equal(
                SystemColors.WindowColor,
                Assert.IsType<SolidColorBrush>(overlay["WindowBackgroundBrush"]).Color);
            Assert.Equal(
                SystemColors.WindowTextColor,
                Assert.IsType<SolidColorBrush>(overlay["PrimaryTextBrush"]).Color);
            Assert.Equal(
                SystemColors.HighlightColor,
                Assert.IsType<SolidColorBrush>(overlay["AccentBrush"]).Color);
            Assert.Equal(
                SystemColors.HighlightTextColor,
                Assert.IsType<SolidColorBrush>(overlay["AccentForegroundBrush"]).Color);

            foreach (var gradientKey in new[]
                     {
                         "AppIconGradientBrush",
                         "AccentGradientBrush",
                         "WarningGradientBrush",
                         "DangerGradientBrush",
                     })
            {
                var gradient = Assert.IsType<LinearGradientBrush>(overlay[gradientKey]);
                Assert.Equal(2, gradient.GradientStops.Count);
                Assert.Equal(gradient.GradientStops[0].Color, gradient.GradientStops[1].Color);
            }
        });
    }

    [Fact]
    public void HighContrastPropertyChangeSwapsOnlyTheLastOverlayLive()
    {
        RunSta(() =>
        {
            var resources = new ResourceDictionary();
            var settings = new AppSettings
            {
                Appearance = AppearanceMode.Dark,
                Theme = ThemeKind.Daangn,
                Language = AppLanguage.Korean,
            };

            ThemeResourceManager.ApplyResources(resources, settings, highContrast: false);
            Assert.Equal(3, resources.MergedDictionaries.Count);
            Assert.DoesNotContain(
                resources.MergedDictionaries,
                dictionary => IsHighContrastDictionary(dictionary));

            Assert.False(ThemeResourceManager.ProcessSystemParametersChange(
                resources,
                settings,
                nameof(SystemParameters.MenuAnimation),
                highContrast: true));
            Assert.Equal(3, resources.MergedDictionaries.Count);

            Assert.True(ThemeResourceManager.ProcessSystemParametersChange(
                resources,
                settings,
                nameof(SystemParameters.HighContrast),
                highContrast: true));
            Assert.Equal(4, resources.MergedDictionaries.Count);
            Assert.True(IsHighContrastDictionary(resources.MergedDictionaries[^1]));

            Assert.True(ThemeResourceManager.ProcessSystemParametersChange(
                resources,
                settings,
                nameof(SystemParameters.HighContrast),
                highContrast: false));
            Assert.Equal(3, resources.MergedDictionaries.Count);
            Assert.DoesNotContain(
                resources.MergedDictionaries,
                dictionary => IsHighContrastDictionary(dictionary));
        });
    }

    [Fact]
    public void LoginSemanticBrushesPreserveTheOriginalNormalModePixels()
    {
        RunSta(() =>
        {
            var uri = new Uri(
                "/ClaudeUsage.Windows;component/Resources/Colors.xaml",
                UriKind.Relative);
            var colors = (ResourceDictionary)System.Windows.Application.LoadComponent(uri);
            var expected = new Dictionary<string, Color>
            {
                ["AccentForegroundBrush"] = Colors.White,
                ["InverseTextBrush"] = Colors.White,
                ["SwitchThumbBrush"] = Colors.White,
                ["LoginWindowBackgroundBrush"] = Color.FromRgb(0xF7, 0xF2, 0xED),
                ["LoginChromeBackgroundBrush"] = Color.FromRgb(0xFC, 0xFA, 0xF7),
                ["LoginBorderBrush"] = Color.FromRgb(0xE8, 0xDE, 0xD4),
                ["LoginPrimaryTextBrush"] = Color.FromRgb(0x2D, 0x29, 0x26),
                ["LoginSecondaryTextBrush"] = Color.FromRgb(0x6D, 0x62, 0x5A),
                ["LoginNoticeBackgroundBrush"] = Color.FromRgb(0xFF, 0xF3, 0xDA),
                ["LoginNoticeBorderBrush"] = Color.FromRgb(0xF0, 0xC4, 0x6B),
                ["LoginNoticeTextBrush"] = Color.FromRgb(0x76, 0x51, 0x16),
                ["LoginWebSurfaceBrush"] = Colors.White,
                ["LoginWebBorderBrush"] = Color.FromRgb(0xD8, 0xCE, 0xC4),
            };

            foreach (var (key, color) in expected)
            {
                Assert.Equal(color, Assert.IsType<SolidColorBrush>(colors[key]).Color);
            }
        });

        var loginXaml = File.ReadAllText(FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Views",
            "ClaudeLoginWindow.xaml"));
        Assert.DoesNotMatch("#[0-9A-Fa-f]{6,8}", loginXaml);
        Assert.DoesNotContain("=\"White\"", loginXaml, StringComparison.Ordinal);
    }

    [Fact]
    public void CustomInteractiveTemplatesExposeKeyboardFocusTriggers()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        var files = new[]
        {
            FindRepositoryFile("windows", "src", "ClaudeUsage.Windows", "Resources", "Controls.xaml"),
            FindRepositoryFile("windows", "src", "ClaudeUsage.Windows", "Views", "SettingsWindow.xaml"),
            FindRepositoryFile("windows", "src", "ClaudeUsage.Windows", "Views", "UsageHistoryDashboardWindow.xaml"),
            FindRepositoryFile("windows", "src", "ClaudeUsage.Windows", "Views", "WidgetView.xaml"),
        };

        var missing = new List<string>();
        foreach (var file in files)
        {
            var document = XDocument.Load(file, LoadOptions.SetLineInfo);
            foreach (var template in document.Descendants(presentation + "ControlTemplate"))
            {
                var targetType = (string?)template.Attribute("TargetType") ?? string.Empty;
                if (targetType is not ("Button" or "CheckBox" or "ListBoxItem"))
                {
                    continue;
                }

                var hasFocusTrigger = template
                    .Descendants(presentation + "Trigger")
                    .Select(trigger => (string?)trigger.Attribute("Property"))
                    .Any(property => property is "IsKeyboardFocused" or "IsKeyboardFocusWithin");
                if (!hasFocusTrigger)
                {
                    var line = ((IXmlLineInfo)template).LineNumber;
                    missing.Add($"{Path.GetFileName(file)}:{line} ({targetType})");
                }
            }
        }

        Assert.True(
            missing.Count == 0,
            $"Custom interactive templates without keyboard focus feedback: {string.Join(", ", missing)}");
    }

    [Fact]
    public void EveryDeclaredLiveRegionOptsIntoTheAutomationEventBehavior()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace accessibility = "clr-namespace:ClaudeUsage.Windows.Accessibility";
        var files = Directory.GetFiles(
            FindRepositoryFile("windows", "src", "ClaudeUsage.Windows"),
            "*.xaml",
            SearchOption.AllDirectories);

        var liveRegions = files
            .SelectMany(file => XDocument.Load(file).Descendants(presentation + "TextBlock"))
            .Where(element => element.Attributes().Any(attribute =>
                attribute.Name.LocalName.EndsWith(".LiveSetting", StringComparison.Ordinal)
                && !string.Equals(attribute.Value, "Off", StringComparison.OrdinalIgnoreCase)))
            .ToArray();

        Assert.NotEmpty(liveRegions);
        Assert.All(liveRegions, element => Assert.Equal(
            "True",
            (string?)element.Attribute(accessibility + "LiveRegionBehavior.AnnounceOnTextChanged")));
    }

    [Fact]
    public void LiveRegionBehaviorRaisesTheUiaLiveRegionChangedEvent()
    {
        RunSta(() =>
        {
            var textBlock = new TextBlock { Text = "Updated" };
            AutomationEvents? raisedEvent = null;
            var peer = new TestTextBlockAutomationPeer(textBlock);

            var raised = LiveRegionBehavior.RaiseLiveRegionChanged(
                textBlock,
                listenerExists: automationEvent => automationEvent == AutomationEvents.LiveRegionChanged,
                peerFactory: _ => peer,
                eventRaiser: (_, automationEvent) => raisedEvent = automationEvent);

            Assert.True(raised);
            Assert.Equal(AutomationEvents.LiveRegionChanged, raisedEvent);
        });
    }

    [Fact]
    public void UsageHistoryChartExposesAConciseDataSummaryToAutomation()
    {
        RunSta(() =>
        {
            var now = DateTimeOffset.Now;
            var chart = new UsageHistoryChart();
            chart.Resources["History.ChartTitle"] = "Limit usage";
            chart.Resources["History.ChartAccessibilityEmpty"] = "No usage samples.";
            chart.Resources["History.ChartAccessibilitySummary"] = "{0} series. {1}";
            chart.Resources["History.ChartAccessibilitySeries"] =
                "{0}: {1} samples, latest {2:0.#}%, range {3:0.#}–{4:0.#}%.";
            chart.Series =
            [
                new UsageHistoryChartSeries(
                    "claude-five-hour",
                    "Claude · 5 hours",
                    UsageProvider.Claude,
                    Brushes.Orange,
                    [
                        new UsageHistoryChartPoint(now.AddMinutes(-5), 15),
                        new UsageHistoryChartPoint(now, 42),
                    ]),
            ];

            var peer = Assert.IsAssignableFrom<AutomationPeer>(
                UIElementAutomationPeer.CreatePeerForElement(chart));

            Assert.Equal(AutomationControlType.Custom, peer.GetAutomationControlType());
            Assert.Equal("Limit usage", peer.GetName());
            Assert.Contains("1 series", peer.GetHelpText(), StringComparison.Ordinal);
            Assert.Contains("Claude · 5 hours", peer.GetHelpText(), StringComparison.Ordinal);
            Assert.Contains("latest 42%", peer.GetHelpText(), StringComparison.Ordinal);
            Assert.Contains("range 15–42%", peer.GetHelpText(), StringComparison.Ordinal);
        });
    }

    private static bool IsHighContrastDictionary(ResourceDictionary dictionary) =>
        ThemeResourceManager.GetResourcePath(dictionary)?.EndsWith(
            ThemeResourceManager.HighContrastDictionaryPath,
            StringComparison.OrdinalIgnoreCase) == true;

    private static string FindRepositoryFile(params string[] segments)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine([directory.FullName, .. segments]);
            if (File.Exists(candidate) || Directory.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException($"Repository path not found: {Path.Combine(segments)}");
    }

    private static void RunSta(Action action)
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
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null)
        {
            throw failure;
        }
    }

    private sealed class TestTextBlockAutomationPeer(TextBlock owner)
        : FrameworkElementAutomationPeer(owner)
    {
        protected override string GetClassNameCore() => nameof(TextBlock);

        protected override AutomationControlType GetAutomationControlTypeCore() =>
            AutomationControlType.Text;
    }
}
