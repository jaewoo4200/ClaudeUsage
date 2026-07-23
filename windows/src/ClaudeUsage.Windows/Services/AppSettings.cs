using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;
using ClaudeUsage.Core.Models;

namespace ClaudeUsage.Windows.Services;

public enum AppearanceMode
{
    System,
    Light,
    Dark,
}

public enum WidgetLayoutMode
{
    Stacked,
    Horizontal,
    Paged,
    Separate,
}

public enum ThemeKind
{
    Daangn,
    Toss,
    Hybrid,
}

public enum AppLanguage
{
    Korean,
    English,
}

public static class WidgetPositionKeys
{
    public const string Combined = "combined";
    public const string Claude = "claude";
    public const string Codex = "codex";
}

/// <summary>
/// A widget position in Win32 physical screen pixels. Physical coordinates avoid
/// ambiguity when monitors use different DPI scales. The window clamps the value
/// to the saved monitor's current work area before using it.
/// </summary>
public sealed class WidgetWindowPosition
{
    public int Left { get; set; }

    public int Top { get; set; }

    public string? MonitorDeviceName { get; set; }
}

public sealed class AppSettings : INotifyPropertyChanged
{
    public const int CurrentSchemaVersion = 3;

    private int _schemaVersion = CurrentSchemaVersion;
    private string? _codexExecutablePath;
    private bool _showCodexSpark;
    private bool _keepFlyoutOpen;
    private bool _widgetAlwaysOnTop = true;
    private bool _companionEnabled = true;
    private CompanionKind _selectedCompanion = CompanionKind.Mimo;
    private MimoSensitivity _companionSensitivity = MimoSensitivity.Balanced;
    private MimoAnimationMode _companionAnimationMode = MimoAnimationMode.Automatic;
    private bool _reducedMotion;
    private bool _usageHistoryEnabled;
    private bool _claudeCloudEnabled = true;
    private WidgetLayoutMode _widgetLayout = WidgetLayoutMode.Stacked;
    private bool _separateClaudeWidgetEnabled = true;
    private bool _separateCodexWidgetEnabled = true;
    private ThemeKind _theme = ThemeKind.Daangn;
    private AppearanceMode _appearance = AppearanceMode.System;
    private AppLanguage _language = DefaultLanguage();
    private bool _floatingWidgetVisible;
    private bool _startWithWindows;
    private Dictionary<string, WidgetWindowPosition> _widgetPositions =
        new(StringComparer.OrdinalIgnoreCase);

    public event PropertyChangedEventHandler? PropertyChanged;

    public int SchemaVersion
    {
        get => _schemaVersion;
        set => SetField(ref _schemaVersion, value);
    }

    public string? CodexExecutablePath
    {
        get => _codexExecutablePath;
        set => SetField(ref _codexExecutablePath, value);
    }

    public bool ShowCodexSpark
    {
        get => _showCodexSpark;
        set => SetField(ref _showCodexSpark, value);
    }

    public bool KeepFlyoutOpen
    {
        get => _keepFlyoutOpen;
        set => SetField(ref _keepFlyoutOpen, value);
    }

    public bool WidgetAlwaysOnTop
    {
        get => _widgetAlwaysOnTop;
        set => SetField(ref _widgetAlwaysOnTop, value);
    }

    public bool CompanionEnabled
    {
        get => _companionEnabled;
        set => SetField(ref _companionEnabled, value);
    }

    public CompanionKind SelectedCompanion
    {
        get => _selectedCompanion;
        set => SetField(ref _selectedCompanion, value);
    }

    public MimoSensitivity CompanionSensitivity
    {
        get => _companionSensitivity;
        set => SetField(ref _companionSensitivity, value);
    }

    public MimoAnimationMode CompanionAnimationMode
    {
        get => _companionAnimationMode;
        set => SetField(ref _companionAnimationMode, value);
    }

    public bool ReducedMotion
    {
        get => _reducedMotion;
        set => SetField(ref _reducedMotion, value);
    }

    public bool UsageHistoryEnabled
    {
        get => _usageHistoryEnabled;
        set => SetField(ref _usageHistoryEnabled, value);
    }

    public bool ClaudeCloudEnabled
    {
        get => _claudeCloudEnabled;
        set => SetField(ref _claudeCloudEnabled, value);
    }

    public WidgetLayoutMode WidgetLayout
    {
        get => _widgetLayout;
        set => SetField(ref _widgetLayout, value);
    }

    public bool SeparateClaudeWidgetEnabled
    {
        get => _separateClaudeWidgetEnabled;
        set => SetField(ref _separateClaudeWidgetEnabled, value);
    }

    public bool SeparateCodexWidgetEnabled
    {
        get => _separateCodexWidgetEnabled;
        set => SetField(ref _separateCodexWidgetEnabled, value);
    }

    public ThemeKind Theme
    {
        get => _theme;
        set => SetField(ref _theme, value);
    }

    public AppearanceMode Appearance
    {
        get => _appearance;
        set => SetField(ref _appearance, value);
    }

    public AppLanguage Language
    {
        get => _language;
        set => SetField(ref _language, value);
    }

    public bool FloatingWidgetVisible
    {
        get => _floatingWidgetVisible;
        set => SetField(ref _floatingWidgetVisible, value);
    }

    public bool StartWithWindows
    {
        get => _startWithWindows;
        set => SetField(ref _startWithWindows, value);
    }

    public Dictionary<string, WidgetWindowPosition> WidgetPositions
    {
        get => _widgetPositions;
        set => SetField(
            ref _widgetPositions,
            value is null
                ? new Dictionary<string, WidgetWindowPosition>(StringComparer.OrdinalIgnoreCase)
                : new Dictionary<string, WidgetWindowPosition>(value, StringComparer.OrdinalIgnoreCase));
    }

    [JsonIgnore]
    public bool UsesSeparateWindows => WidgetLayout == WidgetLayoutMode.Separate;

    internal void Normalize()
    {
        SchemaVersion = CurrentSchemaVersion;
        CodexExecutablePath = string.IsNullOrWhiteSpace(CodexExecutablePath)
            ? null
            : CodexExecutablePath.Trim();

        if (!Enum.IsDefined(Appearance))
        {
            Appearance = AppearanceMode.System;
        }

        if (!Enum.IsDefined(WidgetLayout))
        {
            WidgetLayout = WidgetLayoutMode.Stacked;
        }

        if (!Enum.IsDefined(Theme))
        {
            Theme = ThemeKind.Daangn;
        }

        if (!Enum.IsDefined(Language))
        {
            Language = DefaultLanguage();
        }

        if (!Enum.IsDefined(SelectedCompanion))
        {
            SelectedCompanion = CompanionKind.Mimo;
        }

        if (!Enum.IsDefined(CompanionSensitivity))
        {
            CompanionSensitivity = MimoSensitivity.Balanced;
        }

        if (!Enum.IsDefined(CompanionAnimationMode))
        {
            CompanionAnimationMode = MimoAnimationMode.Automatic;
        }

        // Separate mode must never result in zero visible provider windows.
        if (!SeparateClaudeWidgetEnabled && !SeparateCodexWidgetEnabled)
        {
            SeparateClaudeWidgetEnabled = true;
        }

        WidgetPositions = WidgetPositions;
    }

    private static AppLanguage DefaultLanguage() =>
        CultureInfo.CurrentUICulture.Name.StartsWith("ko", StringComparison.OrdinalIgnoreCase)
            ? AppLanguage.Korean
            : AppLanguage.English;

    private bool SetField<T>(
        ref T field,
        T value,
        [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        if (propertyName == nameof(WidgetLayout))
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(UsesSeparateWindows)));
        }

        return true;
    }
}
