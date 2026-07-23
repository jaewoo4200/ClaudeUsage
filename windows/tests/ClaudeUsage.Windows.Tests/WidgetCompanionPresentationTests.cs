using ClaudeUsage.Core.History;
using ClaudeUsage.Core.Models;
using System.IO;
using System.Xml.Linq;
using ClaudeUsage.Windows.Controls;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using ClaudeUsage.Windows.Views;

namespace ClaudeUsage.Windows.Tests;

public sealed class WidgetCompanionPresentationTests
{
    [Fact]
    public void CompanionPresentationExposesRingAndSparklineInputs()
    {
        var viewModel = new CompanionViewModel(
            language: ClaudeUsage.Windows.Services.AppLanguage.English);
        var trend = new UsageTrend([12, 18, 24], 12, 3.5, null, false);

        viewModel.ApplyUsage(new UsageHistorySnapshot(claudeFiveHour: 32), trend);

        Assert.Equal(32, viewModel.Pressure);
        Assert.Equal("68%", viewModel.RemainingText);
        Assert.Equal([12d, 18d, 24d], viewModel.TrendPoints);
        Assert.Contains("hour", viewModel.DetailText);
        Assert.False(string.IsNullOrWhiteSpace(viewModel.MoodTitle));
    }

    [Fact]
    public void ProviderStatusOnlyOccupiesSpaceWithoutMetrics()
    {
        var provider = new ProviderWidgetViewModel(WidgetProviderKind.Claude)
        {
            StatusText = "Sign in",
        };

        Assert.True(provider.HasStatus);
        provider.ReplaceMetrics([new WidgetMetricViewModel("five-hour", "5 hour", "Short", 20, "2h")]);
        Assert.False(provider.HasStatus);
        provider.ReplaceMetrics([]);
        Assert.True(provider.HasStatus);

        provider.LoadState = ProviderLoadState.Loading;
        Assert.True(provider.IsLoading);
        Assert.False(provider.HasStatus);

        provider.LoadState = ProviderLoadState.Error;
        Assert.True(provider.HasError);
        Assert.True(provider.HasStatus);
    }

    [Fact]
    public void WidgetMapsCodexTransientStatesToMacEmptyStateGrammar()
    {
        var settings = new AppSettings { Language = AppLanguage.English };
        var usage = new UsageViewModel(settings);
        var companion = new CompanionViewModel(language: AppLanguage.English);
        using var widget = new WidgetViewModel(usage, settings, companion);

        Assert.True(widget.Codex.IsLoading);
        Assert.Equal("Loading…", widget.Codex.HeaderStatusText);
        Assert.False(widget.Codex.HasStatus);

        usage.SetError("Detailed failure", "Details", needsSetup: false);
        Assert.True(widget.Codex.HasError);
        Assert.Equal("Load failed", widget.Codex.HeaderStatusText);
        Assert.Equal("Failed to load usage.", widget.Codex.StatusText);

        usage.SetError("Missing Codex", "Details", needsSetup: true);
        Assert.True(widget.Codex.IsUnavailable);
        Assert.Equal("Sign in to the ChatGPT or Codex app", widget.Codex.HeaderStatusText);
        Assert.Equal("Codex isn't connected.", widget.Codex.StatusText);
    }

    [Fact]
    public void ProviderSuccessStatusMatchesMacHeaderCopy()
    {
        var now = new DateTimeOffset(2026, 7, 13, 12, 0, 0, TimeSpan.Zero);
        var settings = new AppSettings { Language = AppLanguage.English };
        var usage = new UsageViewModel(settings);
        usage.ApplySnapshot(
            new OpenAIUsageData(
                "pro",
                new OpenAIRateLimit(
                    new OpenAIUsageWindow(10, now.AddHours(1), null, 18_000),
                    null),
                null,
                []),
            now,
            now);
        usage.ApplyClaudeSnapshot(
            new ClaudeAccountSnapshot(
                new ClaudeOrganization("test", "Test", ["claude_max"], "max_20x"),
                new ClaudeUsageData(new ClaudeUsageWindow(20, now.AddHours(1)), null)),
            now,
            now);

        Assert.Equal("Connected automatically", usage.StatusText);
        Assert.Equal("Signed in", usage.ClaudeStatusText);

        var companion = new CompanionViewModel(language: AppLanguage.English);
        using var widget = new WidgetViewModel(usage, settings, companion);
        Assert.Equal("Connected automatically", widget.Codex.HeaderStatusText);
        Assert.Equal("Signed in", widget.Claude.HeaderStatusText);

        settings.Language = AppLanguage.Korean;
        usage.Relocalize();
        Assert.Equal("자동 연결됨", usage.StatusText);
        Assert.Equal("로그인됨", usage.ClaudeStatusText);
        Assert.Equal("자동 연결됨", widget.Codex.HeaderStatusText);
        Assert.Equal("로그인됨", widget.Claude.HeaderStatusText);
    }

    [Fact]
    public void ClaudeRefreshKeepsLoadedCardsAndGeometryStable()
    {
        var now = new DateTimeOffset(2026, 7, 13, 12, 0, 0, TimeSpan.Zero);
        var settings = new AppSettings { Language = AppLanguage.English };
        var usage = new UsageViewModel(settings);
        usage.ApplyClaudeSnapshot(
            new ClaudeAccountSnapshot(
                new ClaudeOrganization("test", "Test", ["claude_max"], "max_20x"),
                new ClaudeUsageData(new ClaudeUsageWindow(20, now.AddHours(1)), null)),
            now,
            now);

        var companion = new CompanionViewModel(language: AppLanguage.English);
        using var widget = new WidgetViewModel(usage, settings, companion);
        var metricCount = usage.ClaudeCounters.Count;
        usage.SetClaudeRefreshing();

        Assert.True(usage.ClaudeIsRefreshing);
        Assert.Equal(ProviderLoadState.Loaded, usage.ClaudeState);
        Assert.Equal(metricCount, usage.ClaudeCounters.Count);
        Assert.Equal("Signed in", usage.ClaudeStatusText);
        Assert.True(widget.Claude.IsLoaded);
        Assert.False(widget.Claude.IsLoading);
        Assert.Equal(metricCount, widget.Claude.Metrics.Count);

        usage.SetClaudeError("Temporary failure", "Network unavailable", needsLogin: false);

        Assert.False(usage.ClaudeIsRefreshing);
        Assert.Equal(ProviderLoadState.Loaded, usage.ClaudeState);
        Assert.Equal(metricCount, usage.ClaudeCounters.Count);
        Assert.Equal("Signed in", usage.ClaudeStatusText);
        Assert.True(widget.Claude.IsLoaded);
        Assert.False(widget.Claude.HasError);
        Assert.Equal(metricCount, widget.Claude.Metrics.Count);
    }

    [Theory]
    [InlineData(0, WidgetUsageLevel.Normal)]
    [InlineData(69.9, WidgetUsageLevel.Normal)]
    [InlineData(70, WidgetUsageLevel.Warning)]
    [InlineData(89.9, WidgetUsageLevel.Warning)]
    [InlineData(90, WidgetUsageLevel.Danger)]
    public void HorizontalHeadroomIconUsesPressureLevel(double pressure, WidgetUsageLevel expected)
    {
        var settings = new AppSettings { Language = AppLanguage.English };
        var usage = new UsageViewModel(settings);
        var companion = new CompanionViewModel(language: AppLanguage.English);
        using var widget = new WidgetViewModel(usage, settings, companion);

        companion.ApplyUsage(new UsageHistorySnapshot(claudeFiveHour: pressure), UsageTrend.Empty);

        Assert.Equal(expected, widget.HeadroomLevel);
    }

    [Theory]
    [InlineData("en-US", "1:05 PM", "Jul 13")]
    [InlineData("ko-KR", "오후 1:05", "7월 13일")]
    public void HistoryAxisLabelsUseLocaleTimeAndMonthDayPatterns(
        string cultureName,
        string expectedTime,
        string expectedDate)
    {
        var culture = System.Globalization.CultureInfo.GetCultureInfo(cultureName);
        var timestamp = new DateTime(2026, 7, 13, 13, 5, 0);

        Assert.Equal(
            expectedTime,
            UsageHistoryChart.FormatXAxisLabel(timestamp, TimeSpan.FromHours(1), culture));
        Assert.Equal(
            expectedDate,
            UsageHistoryChart.FormatXAxisLabel(timestamp, TimeSpan.FromDays(7), culture));
    }

    [Fact]
    public void CompanionControlSupportsMenuSettingsAndWidgetAvatarSizes()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                var control = new CompanionControl();
                foreach (var size in new[] { 30d, 58d, 66d, 78d })
                {
                    control.AvatarSize = size;
                    Assert.Equal(size, control.AvatarSize);
                }

                control.AvatarSize = 10;
                Assert.Equal(30, control.AvatarSize);
                control.ShowDetails = false;
                Assert.False(control.ShowDetails);
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

    [Fact]
    public void SettingsCompanionPreviewForwardsLiveStateWithoutChangingItsFrame()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                var preview = new SettingsCompanionPreview
                {
                    Width = 40,
                    Height = 40,
                    AvatarSize = 40,
                    FrameSize = 40,
                    Companion = CompanionKind.Pico,
                    Mood = PetMood.Tired,
                    Pressure = 91,
                    AnimationMode = MimoAnimationMode.Lively,
                    ReducedMotion = false,
                };
                preview.Measure(new System.Windows.Size(40, 40));
                preview.Arrange(new System.Windows.Rect(0, 0, 40, 40));
                preview.Dispatcher.Invoke(
                    () => { },
                    System.Windows.Threading.DispatcherPriority.DataBind);

                var control = FindVisualChild<CompanionControl>(preview);
                Assert.NotNull(control);
                Assert.Equal(40, preview.DesiredSize.Width);
                Assert.Equal(40, preview.DesiredSize.Height);
                Assert.Equal(40, control.AvatarSize);
                Assert.Equal(CompanionKind.Pico, control.Companion);
                Assert.Equal(PetMood.Tired, control.Mood);
                Assert.Equal(91, control.Pressure);
                Assert.Equal(MimoAnimationMode.Lively, control.AnimationMode);
                Assert.False(control.ReducedMotion);

                preview.Pressure = 47;
                preview.Mood = PetMood.Focused;
                preview.Dispatcher.Invoke(
                    () => { },
                    System.Windows.Threading.DispatcherPriority.DataBind);
                Assert.Equal(47, control.Pressure);
                Assert.Equal(PetMood.Focused, control.Mood);
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

    [Fact]
    public void SettingsWindowKeepsMacPreferredGeometryAndPlainHistoryActions()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            var historyPath = Path.Combine(
                Path.GetTempPath(),
                $"claudeusage-settings-parity-{Guid.NewGuid():N}.json");
            try
            {
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
                window.ApplyTemplate();

                var surface = Assert.IsType<System.Windows.Controls.Grid>(window.FindName("SettingsSurface"));
                Assert.Equal(420, surface.Width);
                Assert.Equal(600, surface.Height);
                surface.Measure(new System.Windows.Size(420, 600));
                surface.Arrange(new System.Windows.Rect(0, 0, 420, 600));
                surface.UpdateLayout();
                Assert.Equal(420, WindowWorkAreaSizingBehavior.GetPreferredClientWidth(window));
                Assert.Equal(600, WindowWorkAreaSizingBehavior.GetPreferredClientHeight(window));
                Assert.True(WindowWorkAreaSizingBehavior.GetIsEnabled(window));
                Assert.Equal(System.Windows.ResizeMode.CanMinimize, window.ResizeMode);
                var settingsScroll = surface.Children
                    .OfType<System.Windows.Controls.ScrollViewer>()
                    .Single();
                Assert.Equal(
                    System.Windows.Controls.ScrollBarVisibility.Auto,
                    settingsScroll.VerticalScrollBarVisibility);
                Assert.Equal(
                    System.Windows.Controls.ScrollBarVisibility.Disabled,
                    settingsScroll.HorizontalScrollBarVisibility);
                Assert.Equal(
                    System.Windows.Controls.PanningMode.VerticalOnly,
                    settingsScroll.PanningMode);

                var switchStyle = Assert.IsType<System.Windows.Style>(window.Resources["SwitchToggle"]);
                Assert.Equal(44d, SetterValue(switchStyle, System.Windows.FrameworkElement.WidthProperty));
                Assert.Equal(20d, SetterValue(switchStyle, System.Windows.FrameworkElement.HeightProperty));

                var segmentedStyle = Assert.IsType<System.Windows.Style>(window.Resources["SegmentedList"]);
                Assert.Equal(24d, SetterValue(segmentedStyle, System.Windows.FrameworkElement.HeightProperty));

                var layoutPicker = Assert.IsType<System.Windows.Controls.ListBox>(window.FindName("WidgetLayoutPicker"));
                var layoutCard = Assert.IsType<System.Windows.Controls.Border>(window.FindName("WidgetLayoutCard"));
                Assert.True(double.IsNaN(layoutPicker.Width));
                Assert.Equal(System.Windows.HorizontalAlignment.Stretch, layoutPicker.HorizontalAlignment);
                Assert.True(layoutCard.ActualWidth > 20);
                Assert.Equal(layoutCard.ActualWidth - 20, layoutPicker.ActualWidth, precision: 3);
                var layoutTemplate = Assert.IsType<System.Windows.DataTemplate>(layoutPicker.ItemTemplate);
                var layoutContent = Assert.IsType<System.Windows.Controls.StackPanel>(layoutTemplate.LoadContent());
                Assert.Equal(System.Windows.Controls.Orientation.Horizontal, layoutContent.Orientation);
                Assert.Equal(
                    "Description",
                    System.Windows.Data.BindingOperations.GetBinding(
                        layoutContent,
                        System.Windows.Controls.ToolTipService.ToolTipProperty)?.Path.Path);
                Assert.Equal(
                    "Description",
                    System.Windows.Data.BindingOperations.GetBinding(
                        layoutContent,
                        System.Windows.Automation.AutomationProperties.HelpTextProperty)?.Path.Path);
                var layoutText = layoutContent.Children
                    .OfType<System.Windows.Controls.TextBlock>()
                    .ToArray();
                Assert.Equal(2, layoutText.Length);
                Assert.Equal(
                    "Icon",
                    System.Windows.Data.BindingOperations.GetBinding(
                        layoutText[0],
                        System.Windows.Controls.TextBlock.TextProperty)?.Path.Path);
                Assert.Equal(
                    "Label",
                    System.Windows.Data.BindingOperations.GetBinding(
                        layoutText[1],
                        System.Windows.Controls.TextBlock.TextProperty)?.Path.Path);
                Assert.All(viewModel.LayoutOptions, option =>
                {
                    Assert.False(string.IsNullOrWhiteSpace(option.Icon));
                    Assert.False(string.IsNullOrWhiteSpace(option.Description));
                });
                Assert.Equal(
                    viewModel.LayoutOptions.Count,
                    viewModel.LayoutOptions.Select(option => option.Icon).Distinct().Count());

                var plainStyle = Assert.IsType<System.Windows.Style>(window.Resources["SettingsPlainIconButton"]);
                var openHistory = Assert.IsType<System.Windows.Controls.Button>(window.FindName("OpenHistoryButton"));
                var clearHistory = Assert.IsType<System.Windows.Controls.Button>(window.FindName("ClearHistoryButton"));
                Assert.Same(plainStyle, openHistory.Style);
                Assert.Same(plainStyle, clearHistory.Style);

                foreach (var name in new[] { "ClaudeAccountPlanBadge", "CodexAccountPlanBadge" })
                {
                    var badge = Assert.IsType<System.Windows.Controls.Border>(window.FindName(name));
                    var scale = Assert.IsType<System.Windows.Media.ScaleTransform>(badge.RenderTransform);
                    Assert.Equal(0.85, scale.ScaleX);
                    Assert.Equal(0.85, scale.ScaleY);
                }

                window.Close();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
            finally
            {
                if (File.Exists(historyPath))
                {
                    File.Delete(historyPath);
                }
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

    [Fact]
    public void SettingsTitleAndFlyoutChromeUseLanguageNeutralNativeResources()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

        foreach (var stringsFile in new[] { "Strings.en.xaml", "Strings.ko.xaml" })
        {
            var strings = XDocument.Load(FindRepositoryFile(
                "windows",
                "src",
                "ClaudeUsage.Windows",
                "Resources",
                stringsFile));
            var settingsTitle = strings.Descendants()
                .Single(element =>
                    element.Name.LocalName == "String"
                    && (string?)element.Attribute(xaml + "Key") == "UI.SettingsTitle");
            Assert.Equal("Claude + Codex Usage", settingsTitle.Value);
        }

        var flyoutPath = FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Views",
            "FlyoutWindow.xaml");
        var flyoutText = File.ReadAllText(flyoutPath);
        var flyout = XDocument.Parse(flyoutText);
        var scroll = flyout.Descendants(presentation + "ScrollViewer")
            .Single(element => (string?)element.Attribute(xaml + "Name") == "FlyoutScroll");
        Assert.Equal("Auto", (string?)scroll.Attribute("VerticalScrollBarVisibility"));
        Assert.Equal("Disabled", (string?)scroll.Attribute("HorizontalScrollBarVisibility"));
        Assert.Equal(
            "{StaticResource FlyoutOverlayScrollViewer}",
            (string?)scroll.Attribute("Style"));
        var flyoutBody = scroll.Elements(presentation + "StackPanel").Single();
        Assert.Null(flyoutBody.Attribute("Margin"));

        var flyoutChrome = flyout.Descendants(presentation + "Border")
            .Single(element => (string?)element.Attribute(xaml + "Name") == "FlyoutChrome");
        Assert.Equal(
            "{DynamicResource FlyoutOuterCornerRadius}",
            (string?)flyoutChrome.Attribute("CornerRadius"));
        Assert.DoesNotContain("WidgetOuterCornerRadius", flyoutText, StringComparison.Ordinal);

        var controls = XDocument.Load(FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Resources",
            "Controls.xaml"));
        var outerRadius = controls.Descendants(presentation + "CornerRadius")
            .Single(element =>
                (string?)element.Attribute(xaml + "Key") == "FlyoutOuterCornerRadius");
        Assert.Equal("8", outerRadius.Value.Trim());

        var thinScrollBar = controls.Descendants(presentation + "Style")
            .Single(element =>
                (string?)element.Attribute(xaml + "Key") == "FlyoutThinScrollBar");
        Assert.Equal("{x:Type ScrollBar}", (string?)thinScrollBar.Attribute("TargetType"));
        Assert.Equal(
            "5",
            (string?)thinScrollBar.Elements(presentation + "Setter")
                .Single(setter => (string?)setter.Attribute("Property") == "Width")
                .Attribute("Value"));
        Assert.NotEmpty(thinScrollBar.Descendants(presentation + "Thumb"));
        Assert.Contains(
            thinScrollBar.Descendants(presentation + "Border"),
            border =>
                (string?)border.Attribute(xaml + "Name") == "ThumbChrome"
                && (string?)border.Attribute("Width") == "3"
                && (string?)border.Attribute("Opacity") == "0.48");

        var highContrastTrigger = thinScrollBar.Descendants(presentation + "DataTrigger")
            .Single(trigger =>
                ((string?)trigger.Attribute("Binding"))?.Contains(
                    "SystemParameters.HighContrast",
                    StringComparison.Ordinal) == true);
        Assert.Contains(
            highContrastTrigger.Elements(presentation + "Setter"),
            setter =>
                (string?)setter.Attribute("Property") == "Width"
                && (string?)setter.Attribute("Value") == "5");
        Assert.Contains(
            highContrastTrigger.Elements(presentation + "Setter"),
            setter =>
                (string?)setter.Attribute("Property") == "Opacity"
                && (string?)setter.Attribute("Value") == "1");
        Assert.Contains(
            highContrastTrigger.Elements(presentation + "Setter"),
            setter =>
                (string?)setter.Attribute("Property") == "Margin"
                && (string?)setter.Attribute("Value") == "0,2");

        var overlayScrollViewer = controls.Descendants(presentation + "Style")
            .Single(element =>
                (string?)element.Attribute(xaml + "Key") == "FlyoutOverlayScrollViewer");
        Assert.Equal(
            "{x:Type ScrollViewer}",
            (string?)overlayScrollViewer.Attribute("TargetType"));
        var overlayTemplate = overlayScrollViewer
            .Descendants(presentation + "ControlTemplate")
            .Single();
        var overlayGrid = overlayTemplate.Elements(presentation + "Grid").Single();
        Assert.Empty(overlayGrid.Elements(presentation + "Grid.ColumnDefinitions"));
        var contentPresenter = overlayGrid.Elements(presentation + "ScrollContentPresenter")
            .Single(element =>
                (string?)element.Attribute(xaml + "Name") == "PART_ScrollContentPresenter");
        var verticalScrollBar = overlayGrid.Elements(presentation + "ScrollBar")
            .Single(element =>
                (string?)element.Attribute(xaml + "Name") == "PART_VerticalScrollBar");
        Assert.Same(contentPresenter.Parent, verticalScrollBar.Parent);
        Assert.Equal("5", (string?)verticalScrollBar.Attribute("Width"));
        Assert.Equal("Right", (string?)verticalScrollBar.Attribute("HorizontalAlignment"));
        Assert.Equal(
            "{StaticResource FlyoutThinScrollBar}",
            (string?)verticalScrollBar.Attribute("Style"));
        Assert.Equal(
            "{TemplateBinding ComputedVerticalScrollBarVisibility}",
            (string?)verticalScrollBar.Attribute("Visibility"));
    }

    [Fact]
    public void HybridBadgesAndWindowTagsApproximateMacTrackingWithSupportedFontStretch()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace xaml = "http://schemas.microsoft.com/winfx/2006/xaml";
        var hybrid = XDocument.Load(FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Resources",
            "Themes",
            "Hybrid.xaml"));

        XElement Style(string key) => hybrid.Descendants(presentation + "Style")
            .Single(element => (string?)element.Attribute(xaml + "Key") == key);

        static string? Setter(XNamespace presentationNamespace, XElement style, string property) =>
            (string?)style.Elements(presentationNamespace + "Setter")
                .Single(element => (string?)element.Attribute("Property") == property)
                .Attribute("Value");

        var flyoutBadge = Style("FlyoutPlanBadgeCompactTextStyle");
        Assert.Equal("10", Setter(presentation, flyoutBadge, "FontSize"));
        Assert.Equal("SemiExpanded", Setter(presentation, flyoutBadge, "FontStretch"));

        var widgetBadge = Style("WidgetProviderPlanCompactTextStyle");
        Assert.Equal("9", Setter(presentation, widgetBadge, "FontSize"));
        Assert.Equal("SemiExpanded", Setter(presentation, widgetBadge, "FontStretch"));

        var windowTagBinding = hybrid.Descendants(presentation + "Binding")
            .Single(element =>
                (string?)element.Attribute("Converter") == "{StaticResource FlyoutWindowTagConverter}");
        var windowTag = windowTagBinding.Ancestors(presentation + "TextBlock").Single();
        Assert.Equal("9", (string?)windowTag.Attribute("FontSize"));
        Assert.Equal("SemiExpanded", (string?)windowTag.Attribute("FontStretch"));
    }

    [Fact]
    public void FlyoutOverlayScrollsRealOverflowWithoutMovingItsFooter()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                var controls = new System.Windows.ResourceDictionary
                {
                    Source = new Uri(
                        "/ClaudeUsage.Windows;component/Resources/Controls.xaml",
                        UriKind.Relative),
                };
                var root = new System.Windows.Controls.Grid
                {
                    Width = 320,
                    Height = 320,
                };
                root.Resources.MergedDictionaries.Add(controls);
                root.RowDefinitions.Add(new System.Windows.Controls.RowDefinition
                {
                    Height = new System.Windows.GridLength(260),
                });
                root.RowDefinitions.Add(new System.Windows.Controls.RowDefinition
                {
                    Height = new System.Windows.GridLength(60),
                });

                var content = new System.Windows.Controls.StackPanel();
                for (var index = 0; index < 12; index++)
                {
                    content.Children.Add(new System.Windows.Controls.Border
                    {
                        Height = 42,
                        Margin = new System.Windows.Thickness(0, 0, 0, 8),
                    });
                }

                var scroll = new System.Windows.Controls.ScrollViewer
                {
                    Width = 320,
                    Height = 260,
                    Content = content,
                    Style = Assert.IsType<System.Windows.Style>(
                        controls["FlyoutOverlayScrollViewer"]),
                    VerticalScrollBarVisibility =
                        System.Windows.Controls.ScrollBarVisibility.Auto,
                    HorizontalScrollBarVisibility =
                        System.Windows.Controls.ScrollBarVisibility.Disabled,
                    CanContentScroll = true,
                };
                var footer = new System.Windows.Controls.Border
                {
                    Height = 40,
                    VerticalAlignment = System.Windows.VerticalAlignment.Center,
                };
                System.Windows.Controls.Grid.SetRow(scroll, 0);
                System.Windows.Controls.Grid.SetRow(footer, 1);
                root.Children.Add(scroll);
                root.Children.Add(footer);

                root.Measure(new System.Windows.Size(320, 320));
                root.Arrange(new System.Windows.Rect(0, 0, 320, 320));
                scroll.ApplyTemplate();
                root.UpdateLayout();

                Assert.Equal(320, scroll.ActualWidth, precision: 1);
                Assert.Equal(260, scroll.ActualHeight, precision: 1);
                Assert.True(scroll.ScrollableHeight > 0);
                Assert.True(scroll.ExtentHeight > scroll.ViewportHeight);
                var presenter = Assert.IsType<System.Windows.Controls.ScrollContentPresenter>(
                    scroll.Template.FindName("PART_ScrollContentPresenter", scroll));
                var verticalScrollBar = Assert.IsType<System.Windows.Controls.Primitives.ScrollBar>(
                    scroll.Template.FindName("PART_VerticalScrollBar", scroll));
                Assert.Equal(scroll.ActualWidth, presenter.ActualWidth, precision: 1);
                Assert.Equal(5, verticalScrollBar.ActualWidth, precision: 1);

                var footerBefore = footer.TranslatePoint(
                    new System.Windows.Point(0, 0),
                    root);
                var scrollBottom = scroll.TranslatePoint(
                    new System.Windows.Point(0, scroll.ActualHeight),
                    root).Y;
                Assert.True(footerBefore.Y >= scrollBottom);
                Assert.Equal(0, scroll.VerticalOffset);

                scroll.PageDown();
                root.Dispatcher.Invoke(
                    () => { },
                    System.Windows.Threading.DispatcherPriority.Background);
                root.UpdateLayout();

                Assert.True(scroll.VerticalOffset > 0);
                var footerAfter = footer.TranslatePoint(
                    new System.Windows.Point(0, 0),
                    root);
                Assert.Equal(footerBefore.X, footerAfter.X, precision: 3);
                Assert.Equal(footerBefore.Y, footerAfter.Y, precision: 3);
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

    [Fact]
    public void PagedWidgetUsesMacRingTokensAndHeavyVectorChevrons()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

        var widgetPath = FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Views",
            "WidgetView.xaml");
        var widgetText = File.ReadAllText(widgetPath);
        var widget = XDocument.Parse(widgetText);
        var pagedSurface = widget.Descendants(presentation + "Border")
            .Single(element => (string?)element.Attribute(xaml + "Name") == "PagedSurface");
        var pagedHeader = pagedSurface
            .Elements(presentation + "StackPanel")
            .Single()
            .Elements(presentation + "Grid")
            .First();

        var pageButtons = pagedHeader.Elements(presentation + "Button").ToArray();
        Assert.Equal(2, pageButtons.Length);
        Assert.Equal(
            ["{Binding PreviousProviderCommand}", "{Binding NextProviderCommand}"],
            pageButtons.Select(button => (string?)button.Attribute("Command")));
        Assert.All(pageButtons, button =>
        {
            Assert.Null(button.Attribute("Content"));
            Assert.Null(button.Attribute("FontSize"));
        });

        var chevrons = pageButtons
            .Select(button => button.Elements(presentation + "Path").Single())
            .ToArray();
        Assert.Equal(["M 6,1 L 2,5 L 6,9", "M 2,1 L 6,5 L 2,9"],
            chevrons.Select(path => (string?)path.Attribute("Data")));
        Assert.All(chevrons, path =>
        {
            Assert.Equal("6", (string?)path.Attribute("Width"));
            Assert.Equal("10", (string?)path.Attribute("Height"));
            Assert.Equal("1.75", (string?)path.Attribute("StrokeThickness"));
            Assert.Equal("Round", (string?)path.Attribute("StrokeLineJoin"));
            Assert.Equal(
                "{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}",
                (string?)path.Attribute("Stroke"));
        });
        var pagedHeaderText = pagedHeader.ToString();
        Assert.DoesNotContain("‹", pagedHeaderText, StringComparison.Ordinal);
        Assert.DoesNotContain("›", pagedHeaderText, StringComparison.Ordinal);

        var pageDots = pagedHeader.Descendants(presentation + "Ellipse").ToArray();
        Assert.Equal(2, pageDots.Length);
        Assert.All(pageDots, dot =>
        {
            var fillSetter = dot
                .Descendants(presentation + "Style")
                .Single()
                .Elements(presentation + "Setter")
                .Single(setter => (string?)setter.Attribute("Property") == "Fill");
            Assert.Equal(
                "{DynamicResource AccentMutedBrush}",
                (string?)fillSetter.Attribute("Value"));
            Assert.Contains(
                dot.Descendants(presentation + "Setter"),
                setter =>
                    (string?)setter.Attribute("Property") == "Fill"
                    && (string?)setter.Attribute("Value") == "{DynamicResource AccentBrush}");
        });
    }

    [Fact]
    public void HorizontalInsightIconsUseSemanticDecorativeVectors()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

        var widgetPath = FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Views",
            "WidgetView.xaml");
        var widgetText = File.ReadAllText(widgetPath);
        var widget = XDocument.Parse(widgetText);

        Assert.DoesNotContain("BriefGlyph", widgetText, StringComparison.Ordinal);
        foreach (var forbiddenGlyph in new[] { "◉", "↻", "▣", "⌁", "Σ" })
        {
            Assert.DoesNotContain(forbiddenGlyph, widgetText, StringComparison.Ordinal);
        }

        var iconStyle = widget.Descendants(presentation + "Style").Single(element =>
            (string?)element.Attribute(xaml + "Key") == "BriefVectorIcon");
        Assert.Equal("Path", (string?)iconStyle.Attribute("TargetType"));

        static string? SetterValue(
            XElement style,
            XNamespace presentationNamespace,
            string property) => (string?)style.Elements(presentationNamespace + "Setter")
            .Single(setter => (string?)setter.Attribute("Property") == property)
            .Attribute("Value");

        Assert.Equal("14", SetterValue(iconStyle, presentation, "Width"));
        Assert.Equal("14", SetterValue(iconStyle, presentation, "Height"));
        Assert.Equal("Uniform", SetterValue(iconStyle, presentation, "Stretch"));
        Assert.Equal("1.6", SetterValue(iconStyle, presentation, "StrokeThickness"));
        Assert.Equal("Round", SetterValue(iconStyle, presentation, "StrokeStartLineCap"));
        Assert.Equal("Round", SetterValue(iconStyle, presentation, "StrokeEndLineCap"));
        Assert.Equal("Round", SetterValue(iconStyle, presentation, "StrokeLineJoin"));
        Assert.Equal("False", SetterValue(iconStyle, presentation, "Focusable"));
        Assert.Equal("False", SetterValue(iconStyle, presentation, "IsHitTestVisible"));
        Assert.DoesNotContain(
            iconStyle.Elements(presentation + "Setter"),
            setter => ((string?)setter.Attribute("Property"))?.StartsWith(
                "AutomationProperties.",
                StringComparison.Ordinal) == true);

        var iconSpecs = new[]
        {
            (
                Name: "HeadroomGaugeIcon",
                LabelBinding: "{Binding HeadroomLabel}",
                Margin: (string?)null,
                Stroke: (string?)null,
                MinimumFigures: 3),
            (
                Name: "NextResetClockIcon",
                LabelBinding: "{Binding NextResetLabel}",
                Margin: "0,7,0,0",
                Stroke: "{DynamicResource WarningBrush}",
                MinimumFigures: 3),
            (
                Name: "ResetCreditsTicketIcon",
                LabelBinding: "{Binding ResetCreditsLabel}",
                Margin: "0,7,0,0",
                Stroke: "{DynamicResource AccentSecondaryBrush}",
                MinimumFigures: 4),
            (
                Name: "RecentActivityChartIcon",
                LabelBinding: "{Binding RecentActivityLabel}",
                Margin: "0,7,0,0",
                Stroke: "{DynamicResource SuccessBrush}",
                MinimumFigures: 2),
            (
                Name: "TokensTodaySumIcon",
                LabelBinding: "{Binding TokensTodayLabel}",
                Margin: "0,7,0,0",
                Stroke: "{DynamicResource AccentSecondaryBrush}",
                MinimumFigures: 1),
        };

        foreach (var spec in iconSpecs)
        {
            var icon = widget.Descendants(presentation + "Path").Single(element =>
                (string?)element.Attribute(xaml + "Name") == spec.Name);
            Assert.DoesNotContain(
                icon.Attributes(),
                attribute => attribute.Name.LocalName.StartsWith(
                    "AutomationProperties.",
                    StringComparison.Ordinal));
            var data = Assert.IsType<string>((string?)icon.Attribute("Data"));
            var geometry = System.Windows.Media.Geometry.Parse(data).GetFlattenedPathGeometry();

            Assert.True(
                geometry.Figures.Count >= spec.MinimumFigures,
                $"{spec.Name} should retain its semantic vector detail.");
            Assert.True(
                geometry.Bounds.Width >= 6 && geometry.Bounds.Height >= 6,
                $"{spec.Name} should occupy the 14x14 icon canvas.");

            var row = Assert.IsType<XElement>(icon.Parent);
            Assert.Equal(presentation + "Grid", row.Name);
            Assert.Equal("18", (string?)row.Attribute("Height"));
            Assert.Equal(spec.Margin, (string?)row.Attribute("Margin"));
            Assert.Equal(
                "20",
                (string?)row.Elements(presentation + "Grid.ColumnDefinitions")
                    .Elements(presentation + "ColumnDefinition")
                    .First()
                    .Attribute("Width"));

            var label = row.Elements(presentation + "TextBlock").Single(element =>
                (string?)element.Attribute("Grid.Column") == "1");
            Assert.Equal(spec.LabelBinding, (string?)label.Attribute("Text"));

            if (spec.Stroke is not null)
            {
                Assert.Equal(
                    "{StaticResource BriefVectorIcon}",
                    (string?)icon.Attribute("Style"));
                Assert.Equal(spec.Stroke, (string?)icon.Attribute("Stroke"));
            }
        }

        var headroomIcon = widget.Descendants(presentation + "Path").Single(element =>
            (string?)element.Attribute(xaml + "Name") == "HeadroomGaugeIcon");
        var headroomStyle = headroomIcon
            .Elements(presentation + "Path.Style")
            .Elements(presentation + "Style")
            .Single();
        Assert.Equal(
            "{StaticResource BriefVectorIcon}",
            (string?)headroomStyle.Attribute("BasedOn"));
        Assert.Equal(
            ["Warning", "Danger"],
            headroomStyle.Descendants(presentation + "DataTrigger")
                .Select(trigger => (string?)trigger.Attribute("Value")));
        Assert.All(
            headroomStyle.Descendants(presentation + "DataTrigger"),
            trigger => Assert.Contains(
                trigger.Elements(presentation + "Setter"),
                setter => (string?)setter.Attribute("Property") == "Stroke"));
    }

    [Fact]
    public void WidgetLayoutsMeasureAtMacProductWidthsWithoutAViewport()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                System.Windows.Size MeasureLayout(WidgetLayoutMode layout)
                {
                    var settings = new AppSettings
                    {
                        Appearance = AppearanceMode.Light,
                        WidgetLayout = layout,
                    };
                    var usage = new UsageViewModel(settings);
                    var companion = new CompanionViewModel(language: AppLanguage.English);
                    using var viewModel = new WidgetViewModel(usage, settings, companion);
                    var view = new WidgetView { DataContext = viewModel };
                    var available = new System.Windows.Size(double.PositiveInfinity, double.PositiveInfinity);
                    view.Measure(available);
                    view.Dispatcher.Invoke(
                        () => { },
                        System.Windows.Threading.DispatcherPriority.DataBind);
                    view.InvalidateMeasure();
                    view.Measure(available);
                    return view.DesiredSize;
                }

                var stacked = MeasureLayout(WidgetLayoutMode.Stacked);
                var horizontal = MeasureLayout(WidgetLayoutMode.Horizontal);
                var paged = MeasureLayout(WidgetLayoutMode.Paged);
                Assert.True(
                    stacked.Width is >= 239.5 and <= 240.5,
                    $"Stacked measured {stacked.Width}x{stacked.Height}; horizontal {horizontal.Width}x{horizontal.Height}; paged {paged.Width}x{paged.Height}.");
                Assert.True(
                    horizontal.Width is >= 479.5 and <= 480.5,
                    $"Horizontal measured {horizontal.Width}x{horizontal.Height}.");
                Assert.True(
                    paged.Width is >= 239.5 and <= 240.5,
                    $"Paged measured {paged.Width}x{paged.Height}.");
                Assert.NotInRange(paged.Height, 399.5, 400.5);
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

    [Theory]
    [InlineData(320, 320)]
    [InlineData(400, 400)]
    [InlineData(479, 479)]
    [InlineData(480, 480)]
    [InlineData(600, 480)]
    public void HorizontalWidgetFitsFiniteViewportWithoutChangingItsDesignSurface(
        double viewportWidth,
        double expectedWidth)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                var settings = new AppSettings
                {
                    Appearance = AppearanceMode.Light,
                    WidgetLayout = WidgetLayoutMode.Horizontal,
                };
                var usage = new UsageViewModel(settings);
                var companion = new CompanionViewModel(language: AppLanguage.English);
                using var viewModel = new WidgetViewModel(usage, settings, companion);
                var view = new WidgetView { DataContext = viewModel };
                var available = new System.Windows.Size(viewportWidth, double.PositiveInfinity);
                view.Measure(available);
                view.Dispatcher.Invoke(
                    () => { },
                    System.Windows.Threading.DispatcherPriority.DataBind);
                view.InvalidateMeasure();
                view.Measure(available);

                var designSurface = Assert.IsType<System.Windows.Controls.Border>(
                    view.FindName("HorizontalSurface"));
                var viewport = Assert.IsType<System.Windows.Controls.Viewbox>(
                    view.FindName("HorizontalViewport"));
                Assert.Equal(480, designSurface.Width);
                Assert.Equal(
                    System.Windows.Controls.StretchDirection.DownOnly,
                    viewport.StretchDirection);
                Assert.InRange(view.DesiredSize.Width, expectedWidth - 0.5, expectedWidth + 0.5);
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

    private static T? FindVisualChild<T>(System.Windows.DependencyObject parent)
        where T : System.Windows.DependencyObject
    {
        for (var index = 0; index < System.Windows.Media.VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(parent, index);
            if (child is T match)
            {
                return match;
            }

            if (FindVisualChild<T>(child) is { } descendant)
            {
                return descendant;
            }
        }

        return null;
    }

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

    private static object? SetterValue(
        System.Windows.Style style,
        System.Windows.DependencyProperty property) => style.Setters
        .OfType<System.Windows.Setter>()
        .Single(setter => setter.Property == property)
        .Value;

}
