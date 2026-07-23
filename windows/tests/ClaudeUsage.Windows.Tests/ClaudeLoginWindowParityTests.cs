using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using System.Xml.Linq;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.Views;
using Forms = System.Windows.Forms;

namespace ClaudeUsage.Windows.Tests;

public sealed class ClaudeLoginWindowParityTests
{
    [Fact]
    public void LoginWindowDeclaresMacGeometryCompactToolbarAndFullBleedWebView()
    {
        XNamespace presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        XNamespace x = "http://schemas.microsoft.com/winfx/2006/xaml";
        XNamespace services = "clr-namespace:ClaudeUsage.Windows.Services";
        XNamespace webView =
            "clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf";
        var document = XDocument.Load(FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Views",
            "ClaudeLoginWindow.xaml"));
        var window = Assert.IsType<XElement>(document.Root);

        Assert.Equal("WidthAndHeight", (string?)window.Attribute("SizeToContent"));
        Assert.Equal("CanResize", (string?)window.Attribute("ResizeMode"));
        Assert.Equal(
            "520",
            (string?)window.Attribute(services + "WindowWorkAreaSizingBehavior.PreferredClientWidth"));
        Assert.Equal(
            "760",
            (string?)window.Attribute(services + "WindowWorkAreaSizingBehavior.PreferredClientHeight"));
        Assert.Equal(
            "460",
            (string?)window.Attribute(services + "WindowWorkAreaSizingBehavior.MinimumClientWidth"));
        Assert.Equal(
            "640",
            (string?)window.Attribute(services + "WindowWorkAreaSizingBehavior.MinimumClientHeight"));

        var rootGrid = window.Elements(presentation + "Grid").Single();
        Assert.Equal("LoginSurface", (string?)rootGrid.Attribute(x + "Name"));
        Assert.Equal("520", (string?)rootGrid.Attribute("Width"));
        Assert.Equal("760", (string?)rootGrid.Attribute("Height"));
        var rows = rootGrid
            .Element(presentation + "Grid.RowDefinitions")!
            .Elements(presentation + "RowDefinition")
            .Select(row => (string)row.Attribute("Height")!)
            .ToArray();
        Assert.Equal(["Auto", "*"], rows);

        var toolbar = rootGrid
            .Elements(presentation + "Border")
            .Single(element => (string?)element.Attribute(x + "Name") == "LoginToolbar");
        Assert.Equal("36", (string?)toolbar.Attribute("Height"));
        Assert.Contains(
            toolbar.Descendants(presentation + "TextBlock"),
            element => (string?)element.Attribute(x + "Name") == "StatusText");

        var expectedButtons = new Dictionary<string, string>
        {
            ["ReloadButton"] = "ReloadButton_Click",
            ["OpenInDefaultBrowserButton"] = "OpenInDefaultBrowserButton_Click",
            ["ClearLoginDataButton"] = "ClearLoginDataButton_Click",
        };
        var buttons = toolbar.Descendants(presentation + "Button").ToDictionary(
            element => (string)element.Attribute(x + "Name")!,
            element => (string)element.Attribute("Click")!);
        Assert.Equal(expectedButtons, buttons);

        var browser = rootGrid.Elements(webView + "WebView2").Single();
        Assert.Same(rootGrid, browser.Parent);
        Assert.Equal("LoginWebView", (string?)browser.Attribute(x + "Name"));
        Assert.Equal("1", (string?)browser.Attribute("Grid.Row"));
        Assert.Equal("0", (string?)browser.Attribute("Margin"));
    }

    [Fact]
    public void ExternalBrowserActionUsesOnlyTheFixedHttpsClaudeLoginPage()
    {
        var startInfo = ClaudeLoginWindow.CreateExternalBrowserStartInfo();

        Assert.Equal("https://claude.ai/login", startInfo.FileName);
        Assert.True(startInfo.UseShellExecute);
        Assert.Empty(startInfo.ArgumentList);
    }

    [Fact]
    public void LoginWindowCreatesTheExpectedNativeClientAreaForTheCurrentWorkArea()
    {
        RunSta(() =>
        {
            ThemeResourceManager.Initialize(new AppSettings
            {
                Appearance = AppearanceMode.Light,
                Theme = ThemeKind.Daangn,
                Language = AppLanguage.English,
            });
            var window = new ClaudeLoginWindow();
            try
            {
                var handle = new WindowInteropHelper(window).EnsureHandle();
                Assert.NotEqual(IntPtr.Zero, handle);
                window.Dispatcher.Invoke(
                    static () => { },
                    DispatcherPriority.ApplicationIdle);

                Assert.True(GetClientRect(handle, out var client));
                Assert.True(GetWindowRect(handle, out var outer));
                var dpi = VisualTreeHelper.GetDpi(window);
                var clientWidthPixels = client.Right - client.Left;
                var clientHeightPixels = client.Bottom - client.Top;
                var nonClientWidth = Math.Max(
                    0,
                    (outer.Right - outer.Left - clientWidthPixels) / dpi.DpiScaleX);
                var nonClientHeight = Math.Max(
                    0,
                    (outer.Bottom - outer.Top - clientHeightPixels) / dpi.DpiScaleY);
                var workArea = Forms.Screen.FromHandle(handle).WorkingArea;
                var expected = WindowWorkAreaSizingPolicy.Calculate(new WindowWorkAreaSizingRequest(
                    workArea.Width,
                    workArea.Height,
                    dpi.DpiScaleX,
                    dpi.DpiScaleY,
                    PreferredWidth: 520,
                    PreferredHeight: 760,
                    MinimumWidth: 460,
                    MinimumHeight: 640,
                    NonClientWidth: nonClientWidth,
                    NonClientHeight: nonClientHeight,
                    PreferredSizeIsClient: true,
                    PhysicalMarginPixels: 12));
                var expectedClientWidthPixels =
                    (expected.TargetOuterWidth - nonClientWidth) * dpi.DpiScaleX;
                var expectedClientHeightPixels =
                    (expected.TargetOuterHeight - nonClientHeight) * dpi.DpiScaleY;

                Assert.InRange(
                    clientWidthPixels,
                    (int)Math.Floor(expectedClientWidthPixels) - 1,
                    (int)Math.Ceiling(expectedClientWidthPixels) + 1);
                Assert.InRange(
                    clientHeightPixels,
                    (int)Math.Floor(expectedClientHeightPixels) - 1,
                    (int)Math.Ceiling(expectedClientHeightPixels) + 1);
                Assert.InRange(clientWidthPixels, 1, (int)Math.Ceiling(520 * dpi.DpiScaleX));
                Assert.InRange(clientHeightPixels, 1, (int)Math.Ceiling(760 * dpi.DpiScaleY));
                Assert.InRange(
                    outer.Right - outer.Left,
                    1,
                    Math.Max(1, workArea.Width - 24) + 1);
                Assert.InRange(
                    outer.Bottom - outer.Top,
                    1,
                    Math.Max(1, workArea.Height - 24) + 1);
                Assert.Equal(SizeToContent.Manual, window.SizeToContent);
                Assert.True(window.MinWidth <= window.MaxWidth);
                Assert.True(window.MinHeight <= window.MaxHeight);
            }
            finally
            {
                window.Close();
                ThemeResourceManager.Shutdown();
            }
        });
    }

    [Fact]
    public void LoginChromeProvidesDistinctLightAndDarkSemanticResources()
    {
        RunSta(() =>
        {
            var lightResources = new ResourceDictionary();
            ThemeResourceManager.ApplyResources(
                lightResources,
                new AppSettings
                {
                    Appearance = AppearanceMode.Light,
                    Theme = ThemeKind.Daangn,
                    Language = AppLanguage.English,
                },
                highContrast: false);

            var darkResources = new ResourceDictionary();
            ThemeResourceManager.ApplyResources(
                darkResources,
                new AppSettings
                {
                    Appearance = AppearanceMode.Dark,
                    Theme = ThemeKind.Daangn,
                    Language = AppLanguage.English,
                },
                highContrast: false);

            foreach (var key in new[]
                     {
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
                     })
            {
                var light = Assert.IsType<SolidColorBrush>(lightResources[key]);
                var dark = Assert.IsType<SolidColorBrush>(darkResources[key]);
                Assert.NotEqual(light.Color, dark.Color);
            }

            Assert.Equal(
                Color.FromRgb(0xFC, 0xFA, 0xF7),
                Assert.IsType<SolidColorBrush>(lightResources["LoginChromeBackgroundBrush"]).Color);
            Assert.Equal(
                Color.FromRgb(0x22, 0x22, 0x26),
                Assert.IsType<SolidColorBrush>(darkResources["LoginChromeBackgroundBrush"]).Color);
            Assert.Equal(
                Color.FromRgb(0x11, 0x11, 0x13),
                Assert.IsType<SolidColorBrush>(darkResources["LoginWebSurfaceBrush"]).Color);
        });
    }

    [Fact]
    public void LoginWindowRetainsIsolatedProfileAndHardenedWebViewWiring()
    {
        var source = File.ReadAllText(FindRepositoryFile(
            "windows",
            "src",
            "ClaudeUsage.Windows",
            "Views",
            "ClaudeLoginWindow.xaml.cs"));
        var requiredFragments = new[]
        {
            "userDataFolder: _profilePath",
            "core.Settings.AreDevToolsEnabled = false",
            "core.Settings.IsPasswordAutosaveEnabled = false",
            "core.Settings.IsGeneralAutofillEnabled = false",
            "core.Settings.AreDefaultContextMenusEnabled = false",
            "core.Settings.AreBrowserAcceleratorKeysEnabled = false",
            "core.DownloadStarting += Core_DownloadStarting",
            "core.LaunchingExternalUriScheme += Core_LaunchingExternalUriScheme",
            "core.NewWindowRequested += Core_NewWindowRequested",
            "core.NavigationStarting += Core_NavigationStarting",
            "core.PermissionRequested += Core_PermissionRequested",
            "ClaudeLoginSecurityPolicy.IsAllowedNavigation(e.Uri)",
            "e.State = CoreWebView2PermissionState.Deny",
            "e.SavesInProfile = false",
            "core.CookieManager.DeleteAllCookies()",
            "core.Profile.ClearBrowsingDataAsync()",
            "ClaudeLoginProfileCleanup.DeleteProfileWithRetryAsync(_profilePath)",
        };

        Assert.All(requiredFragments, fragment =>
            Assert.Contains(fragment, source, StringComparison.Ordinal));
        Assert.DoesNotContain("AreDevToolsEnabled = true", source, StringComparison.Ordinal);
        Assert.DoesNotContain("IsPasswordAutosaveEnabled = true", source, StringComparison.Ordinal);
        Assert.DoesNotContain("IsGeneralAutofillEnabled = true", source, StringComparison.Ordinal);
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

        throw new FileNotFoundException($"Repository file not found: {Path.Combine(segments)}");
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

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(IntPtr window, out NativeRect rectangle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr window, out NativeRect rectangle);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
