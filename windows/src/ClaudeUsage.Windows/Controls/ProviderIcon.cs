using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using MediaBrushes = System.Windows.Media.Brushes;
using MediaColor = System.Windows.Media.Color;
using MediaColors = System.Windows.Media.Colors;
using MediaLinearGradientBrush = System.Windows.Media.LinearGradientBrush;
using MediaPen = System.Windows.Media.Pen;
using MediaPenLineCap = System.Windows.Media.PenLineCap;
using MediaPenLineJoin = System.Windows.Media.PenLineJoin;
using MediaSolidColorBrush = System.Windows.Media.SolidColorBrush;
using WpfPoint = System.Windows.Point;
using WpfRect = System.Windows.Rect;
using WpfSize = System.Windows.Size;

namespace ClaudeUsage.Windows.Controls;

public enum ProviderBrand
{
    Claude,
    Codex,
}

/// <summary>
/// Displays the installed desktop application's icon when Windows can resolve it.
/// A vector Claude/Codex mark is always available, so missing or protected package
/// paths never leave a letter tile or a broken image behind.
/// </summary>
public sealed class ProviderIcon : FrameworkElement
{
    public static readonly DependencyProperty ProviderProperty = DependencyProperty.Register(
        nameof(Provider),
        typeof(ProviderBrand),
        typeof(ProviderIcon),
        new FrameworkPropertyMetadata(ProviderBrand.Claude, OnProviderChanged));

    private ImageSource? _installedIcon;

    public ProviderIcon()
    {
        Focusable = false;
        IsHitTestVisible = false;
        SnapsToDevicePixels = true;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        Loaded += OnLoaded;
    }

    public ProviderBrand Provider
    {
        get => (ProviderBrand)GetValue(ProviderProperty);
        set => SetValue(ProviderProperty, value);
    }

    protected override WpfSize MeasureOverride(WpfSize availableSize)
    {
        var width = double.IsNaN(Width) ? 36 : Width;
        var height = double.IsNaN(Height) ? 36 : Height;
        return new WpfSize(width, height);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        var size = Math.Min(ActualWidth, ActualHeight);
        if (size <= 0)
        {
            return;
        }

        var bounds = new WpfRect(
            (ActualWidth - size) / 2,
            (ActualHeight - size) / 2,
            size,
            size);
        if (_installedIcon is not null)
        {
            drawingContext.DrawImage(_installedIcon, bounds);
            return;
        }

        if (Provider == ProviderBrand.Claude)
        {
            DrawClaudeFallback(drawingContext, bounds);
        }
        else
        {
            DrawCodexFallback(drawingContext, bounds);
        }
    }

    private async void OnLoaded(object sender, RoutedEventArgs e) => await LoadInstalledIconAsync();

    private async Task LoadInstalledIconAsync()
    {
        var requestedProvider = Provider;
        try
        {
            var icon = await ProviderBrandIconLoader.LoadAsync(requestedProvider).ConfigureAwait(true);
            if (Provider == requestedProvider)
            {
                _installedIcon = icon;
                InvalidateVisual();
            }
        }
        catch (Exception)
        {
            // Icon discovery is cosmetic. The vector fallback is the stable path.
            _installedIcon = null;
            InvalidateVisual();
        }
    }

    private static void OnProviderChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e)
    {
        var control = (ProviderIcon)sender;
        control._installedIcon = null;
        control.InvalidateVisual();
        if (control.IsLoaded)
        {
            _ = control.LoadInstalledIconAsync();
        }
    }

    private static void DrawClaudeFallback(DrawingContext context, WpfRect bounds)
    {
        var radius = bounds.Width * 0.25;
        context.DrawRoundedRectangle(ClaudeGradient, ClaudeBorderPen, bounds, radius, radius);

        var center = new WpfPoint(bounds.Left + (bounds.Width * 0.5), bounds.Top + (bounds.Height * 0.5));
        var pen = new MediaPen(MediaBrushes.White, Math.Max(1.6, bounds.Width * 0.075))
        {
            StartLineCap = MediaPenLineCap.Round,
            EndLineCap = MediaPenLineCap.Round,
        };
        pen.Freeze();
        for (var index = 0; index < 12; index++)
        {
            var angle = ((index * 30) - 90) * Math.PI / 180;
            var inner = bounds.Width * (index % 2 == 0 ? 0.055 : 0.07);
            var outer = bounds.Width * (index % 3 == 0 ? 0.35 : 0.29);
            context.DrawLine(
                pen,
                new WpfPoint(center.X + (Math.Cos(angle) * inner), center.Y + (Math.Sin(angle) * inner)),
                new WpfPoint(center.X + (Math.Cos(angle) * outer), center.Y + (Math.Sin(angle) * outer)));
        }
    }

    private static void DrawCodexFallback(DrawingContext context, WpfRect bounds)
    {
        var radius = bounds.Width * 0.25;
        context.DrawRoundedRectangle(CodexTileBrush, CodexTileBorderPen, bounds, radius, radius);

        var cloudLeft = bounds.Left + (bounds.Width * 0.14);
        var cloudTop = bounds.Top + (bounds.Height * 0.20);
        var cloudWidth = bounds.Width * 0.72;
        var cloudHeight = bounds.Height * 0.60;
        context.DrawEllipse(CodexCloudGradient, null,
            new WpfPoint(cloudLeft + (cloudWidth * 0.28), cloudTop + (cloudHeight * 0.50)),
            cloudWidth * 0.28,
            cloudHeight * 0.38);
        context.DrawEllipse(CodexCloudGradient, null,
            new WpfPoint(cloudLeft + (cloudWidth * 0.51), cloudTop + (cloudHeight * 0.34)),
            cloudWidth * 0.33,
            cloudHeight * 0.34);
        context.DrawEllipse(CodexCloudGradient, null,
            new WpfPoint(cloudLeft + (cloudWidth * 0.74), cloudTop + (cloudHeight * 0.52)),
            cloudWidth * 0.29,
            cloudHeight * 0.36);
        context.DrawRoundedRectangle(
            CodexCloudGradient,
            null,
            new WpfRect(cloudLeft + (cloudWidth * 0.15), cloudTop + (cloudHeight * 0.43), cloudWidth * 0.70, cloudHeight * 0.42),
            cloudHeight * 0.20,
            cloudHeight * 0.20);

        var terminalPen = new MediaPen(MediaBrushes.White, Math.Max(1.3, bounds.Width * 0.06))
        {
            StartLineCap = MediaPenLineCap.Round,
            EndLineCap = MediaPenLineCap.Round,
            LineJoin = MediaPenLineJoin.Round,
        };
        terminalPen.Freeze();
        var x = bounds.Left + (bounds.Width * 0.39);
        var y = bounds.Top + (bounds.Height * 0.49);
        var step = bounds.Width * 0.09;
        context.DrawLine(terminalPen, new WpfPoint(x - step, y - step), new WpfPoint(x, y));
        context.DrawLine(terminalPen, new WpfPoint(x, y), new WpfPoint(x - step, y + step));
        context.DrawLine(
            terminalPen,
            new WpfPoint(bounds.Left + (bounds.Width * 0.56), bounds.Top + (bounds.Height * 0.61)),
            new WpfPoint(bounds.Left + (bounds.Width * 0.70), bounds.Top + (bounds.Height * 0.61)));
    }

    private static readonly MediaLinearGradientBrush ClaudeGradient = Freeze(new MediaLinearGradientBrush(
        MediaColor.FromRgb(244, 113, 75),
        MediaColor.FromRgb(219, 83, 57),
        new WpfPoint(0, 0),
        new WpfPoint(1, 1)));

    private static readonly MediaPen ClaudeBorderPen = Freeze(new MediaPen(
        new MediaSolidColorBrush(MediaColor.FromArgb(28, 96, 43, 31)),
        0.7));

    private static readonly MediaSolidColorBrush CodexTileBrush = Freeze(new MediaSolidColorBrush(MediaColors.White));

    private static readonly MediaPen CodexTileBorderPen = Freeze(new MediaPen(
        new MediaSolidColorBrush(MediaColor.FromArgb(24, 27, 31, 36)),
        0.7));

    private static readonly MediaLinearGradientBrush CodexCloudGradient = Freeze(new MediaLinearGradientBrush(
        MediaColor.FromRgb(178, 153, 255),
        MediaColor.FromRgb(53, 75, 244),
        new WpfPoint(0.15, 0),
        new WpfPoint(0.85, 1)));

    private static T Freeze<T>(T freezable) where T : Freezable
    {
        freezable.Freeze();
        return freezable;
    }
}

internal static class ProviderBrandIconLoader
{
    private static readonly ConcurrentDictionary<ProviderBrand, Lazy<Task<ImageSource?>>> Cache = new();

    public static Task<ImageSource?> LoadAsync(ProviderBrand provider) =>
        Cache.GetOrAdd(
            provider,
            static brand => new Lazy<Task<ImageSource?>>(
                () => Task.Run(() => Load(brand)),
                LazyThreadSafetyMode.ExecutionAndPublication)).Value;

    private static ImageSource? Load(ProviderBrand provider)
    {
        foreach (var path in CandidatePaths(provider).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!File.Exists(path))
            {
                continue;
            }

            var icon = ExtractShellIcon(path);
            if (icon is not null
                && (provider != ProviderBrand.Codex || HasCodexBrandPalette(icon)))
            {
                return icon;
            }
        }

        return null;
    }

    private static bool HasCodexBrandPalette(ImageSource icon)
    {
        if (icon is not BitmapSource bitmap || bitmap.PixelWidth <= 0 || bitmap.PixelHeight <= 0)
        {
            return false;
        }

        BitmapSource source = bitmap;
        if (source.Format != PixelFormats.Bgra32)
        {
            source = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
            source.Freeze();
        }

        var stride = checked(source.PixelWidth * 4);
        var pixels = new byte[checked(stride * source.PixelHeight)];
        source.CopyPixels(pixels, stride, 0);
        return HasCodexBrandPalette(pixels);
    }

    internal static bool HasCodexBrandPalette(ReadOnlySpan<byte> bgraPixels)
    {
        var opaquePixels = 0;
        var codexBluePixels = 0;
        for (var index = 0; index + 3 < bgraPixels.Length; index += 4)
        {
            var blue = bgraPixels[index];
            var green = bgraPixels[index + 1];
            var red = bgraPixels[index + 2];
            var alpha = bgraPixels[index + 3];
            if (alpha < 32)
            {
                continue;
            }

            opaquePixels++;
            var maximum = Math.Max(red, Math.Max(green, blue));
            var minimum = Math.Min(red, Math.Min(green, blue));
            if (blue >= 130
                && blue >= green + 18
                && maximum - minimum >= 45)
            {
                codexBluePixels++;
            }
        }

        return opaquePixels > 0 && codexBluePixels * 50 >= opaquePixels;
    }

    private static IEnumerable<string> CandidatePaths(ProviderBrand provider)
    {
        var paths = new List<string>();
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var executableNames = provider == ProviderBrand.Claude
            ? new[] { "Claude.exe" }
            // The Windows Codex desktop app is hosted by ChatGPT.exe. A
            // codex.exe process is the CLI and does not carry the brand icon.
            : new[] { "ChatGPT.exe" };

        if (provider == ProviderBrand.Claude)
        {
            Add(paths, Path.Combine(local, "Programs", "Claude", "Claude.exe"));
            Add(paths, Path.Combine(local, "AnthropicClaude", "Claude.exe"));
            Add(paths, Path.Combine(local, "Claude", "Claude.exe"));
            Add(paths, Path.Combine(roaming, "Claude", "Claude.exe"));
        }
        else
        {
            Add(paths, Path.Combine(local, "Programs", "Codex", "Codex.exe"));
            Add(paths, Path.Combine(local, "OpenAI", "Codex", "Codex.exe"));
            Add(paths, Path.Combine(local, "Programs", "ChatGPT", "ChatGPT.exe"));
            Add(paths, Path.Combine(local, "OpenAI", "ChatGPT", "ChatGPT.exe"));
        }

        // Prefer a real running binary or a Start-menu shortcut. Microsoft Store
        // execution aliases can exist as tiny proxy files whose shell icon is a
        // generic application tile rather than the provider brand.
        AddRunningApplicationPaths(paths, provider);
        AddStartMenuShortcuts(paths, provider);
        foreach (var executableName in executableNames)
        {
            AddAppPath(paths, executableName);
            Add(paths, Path.Combine(local, "Microsoft", "WindowsApps", executableName));
        }

        return paths;
    }

    private static void AddAppPath(ICollection<string> paths, string executableName)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                $@"Software\Microsoft\Windows\CurrentVersion\App Paths\{executableName}");
            if (key?.GetValue(null) is string path)
            {
                Add(paths, path.Trim('"'));
            }
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or System.Security.SecurityException)
        {
            // A protected registry view is equivalent to an app not being discoverable.
        }
    }

    private static void AddStartMenuShortcuts(ICollection<string> paths, ProviderBrand provider)
    {
        var names = provider == ProviderBrand.Claude
            ? new[] { "claude" }
            : new[] { "codex", "chatgpt" };
        var roots = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),
        };

        foreach (var root in roots.Where(Directory.Exists))
        {
            try
            {
                foreach (var shortcut in Directory.EnumerateFiles(root, "*.lnk", SearchOption.AllDirectories))
                {
                    var fileName = Path.GetFileNameWithoutExtension(shortcut);
                    if (names.Any(name => fileName.Contains(name, StringComparison.OrdinalIgnoreCase)))
                    {
                        Add(paths, shortcut);
                    }
                }
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                // Start-menu discovery is best effort.
            }
        }
    }

    private static void AddRunningApplicationPaths(ICollection<string> paths, ProviderBrand provider)
    {
        var processNames = provider == ProviderBrand.Claude
            ? new[] { "Claude" }
            : new[] { "ChatGPT" };
        foreach (var processName in processNames)
        {
            foreach (var process in Process.GetProcessesByName(processName))
            {
                using (process)
                {
                    try
                    {
                        Add(paths, process.MainModule?.FileName);
                    }
                    catch (Exception exception) when (
                        exception is InvalidOperationException
                            or System.ComponentModel.Win32Exception
                            or NotSupportedException)
                    {
                        // Cross-integrity process paths can be unavailable.
                    }
                }
            }
        }
    }

    private static ImageSource? ExtractShellIcon(string path)
    {
        var info = new ShellFileInfo();
        var result = SHGetFileInfo(
            path,
            0,
            ref info,
            (uint)Marshal.SizeOf<ShellFileInfo>(),
            ShellIcon | LargeIcon);
        if (result == IntPtr.Zero || info.IconHandle == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            var source = Imaging.CreateBitmapSourceFromHIcon(
                info.IconHandle,
                Int32Rect.Empty,
                BitmapSizeOptions.FromWidthAndHeight(64, 64));
            source.Freeze();
            return source;
        }
        finally
        {
            _ = DestroyIcon(info.IconHandle);
        }
    }

    private static void Add(ICollection<string> paths, string? path)
    {
        if (!string.IsNullOrWhiteSpace(path))
        {
            paths.Add(path);
        }
    }

    private const uint ShellIcon = 0x000000100;
    private const uint LargeIcon = 0x000000000;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ShellFileInfo
    {
        public IntPtr IconHandle;
        public int IconIndex;
        public uint Attributes;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string? DisplayName;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string? TypeName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SHGetFileInfo(
        string path,
        uint fileAttributes,
        ref ShellFileInfo fileInfo,
        uint fileInfoSize,
        uint flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr iconHandle);
}
