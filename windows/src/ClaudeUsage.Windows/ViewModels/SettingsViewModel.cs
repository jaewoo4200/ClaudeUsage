using System.ComponentModel;
using System.Reflection;
using System.Runtime.CompilerServices;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using WpfApplication = System.Windows.Application;

namespace ClaudeUsage.Windows.ViewModels;

public sealed record SettingOption<T>(
    T Value,
    string Label,
    string Description = "",
    string Icon = "");

public sealed class SettingChangedEventArgs(string propertyName) : EventArgs
{
    public string PropertyName { get; } = propertyName;
}

public sealed class SettingsViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly AppSettings _settings;
    private readonly UsageHistoryService _history;
    private readonly string _appVersion;
    private readonly bool _persistChanges;
    private bool _disposed;
    private bool _hasPersistenceError;

    public SettingsViewModel(
        AppSettings settings,
        UsageViewModel usage,
        UsageHistoryService history,
        CompanionViewModel companion,
        bool persistChanges = true)
    {
        _settings = settings ?? throw new ArgumentNullException(nameof(settings));
        Usage = usage ?? throw new ArgumentNullException(nameof(usage));
        _history = history ?? throw new ArgumentNullException(nameof(history));
        Companion = companion ?? throw new ArgumentNullException(nameof(companion));
        _persistChanges = persistChanges;
        _appVersion = typeof(SettingsViewModel).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion.Split('+')[0]
            ?? typeof(SettingsViewModel).Assembly.GetName().Version?.ToString(3)
            ?? "0.1.0";
        ThemeResourceManager.Initialize(_settings);
        _settings.PropertyChanged += OnSettingsPropertyChanged;
        _history.Store.Changed += OnHistoryStoreChanged;
        RebuildOptions();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>
    /// Raised after an in-memory setting is atomically persisted. The app shell can
    /// use this to reconcile window topology or HKCU Run integration.
    /// </summary>
    public event EventHandler<SettingChangedEventArgs>? SettingsChanged;

    public AppSettings Settings => _settings;

    public UsageViewModel Usage { get; }

    public CompanionViewModel Companion { get; }

    public bool HasHistorySamples => _history.Store.HasSamples;

    public string AppVersionText => string.Format(
        ThemeResourceManager.GetString("Settings.VersionFormat", "v{0} · Settings"),
        _appVersion);

    public bool HasPersistenceError
    {
        get => _hasPersistenceError;
        private set => SetField(ref _hasPersistenceError, value);
    }

    public string PersistenceErrorText => ThemeResourceManager.GetString(
        "Settings.PersistenceError",
        "Settings couldn't be saved. Changes remain active for this session but may revert after restart. History and Claude integration stay off for this session when you disable them.");

    public IReadOnlyList<SettingOption<AppearanceMode>> AppearanceOptions { get; private set; } = [];

    public IReadOnlyList<SettingOption<ThemeKind>> ThemeOptions { get; private set; } = [];

    public IReadOnlyList<SettingOption<WidgetLayoutMode>> LayoutOptions { get; private set; } = [];

    public IReadOnlyList<SettingOption<AppLanguage>> LanguageOptions { get; private set; } = [];

    public IReadOnlyList<SettingOption<CompanionKind>> CompanionOptions { get; private set; } = [];

    public IReadOnlyList<SettingOption<MimoSensitivity>> CompanionSensitivityOptions { get; private set; } = [];

    public IReadOnlyList<SettingOption<MimoAnimationMode>> CompanionAnimationOptions { get; private set; } = [];

    public AppearanceMode Appearance
    {
        get => _settings.Appearance;
        set => Change(nameof(AppSettings.Appearance), value, () => _settings.Appearance, current => _settings.Appearance = current);
    }

    public ThemeKind Theme
    {
        get => _settings.Theme;
        set => Change(nameof(AppSettings.Theme), value, () => _settings.Theme, current => _settings.Theme = current);
    }

    public AppLanguage Language
    {
        get => _settings.Language;
        set
        {
            if (_settings.Language == value)
            {
                return;
            }

            _settings.Language = value;
            RebuildOptions();
            Persist(nameof(AppSettings.Language));
        }
    }

    public bool FloatingWidgetVisible
    {
        get => _settings.FloatingWidgetVisible;
        set => Change(
            nameof(AppSettings.FloatingWidgetVisible),
            value,
            () => _settings.FloatingWidgetVisible,
            current => _settings.FloatingWidgetVisible = current);
    }

    public bool WidgetAlwaysOnTop
    {
        get => _settings.WidgetAlwaysOnTop;
        set
        {
            if (_settings.WidgetAlwaysOnTop == value)
            {
                return;
            }

            _settings.WidgetAlwaysOnTop = value;
            OnPropertyChanged(nameof(WidgetAlwaysOnTopDescription));
            Persist(nameof(AppSettings.WidgetAlwaysOnTop));
        }
    }

    public string WidgetAlwaysOnTopDescription => WidgetAlwaysOnTop
        ? ThemeResourceManager.GetString(
            "Settings.AlwaysOnTopOnDescription",
            "Stays above other windows")
        : ThemeResourceManager.GetString(
            "Settings.AlwaysOnTopOffDescription",
            "Can go behind other windows");

    public WidgetLayoutMode WidgetLayout
    {
        get => _settings.WidgetLayout;
        set
        {
            if (_settings.WidgetLayout == value)
            {
                return;
            }

            _settings.WidgetLayout = value;
            OnPropertyChanged(nameof(IsSeparateLayout));
            OnPropertyChanged(nameof(SelectedLayoutDescription));
            Persist(nameof(AppSettings.WidgetLayout));
        }
    }

    public bool IsSeparateLayout => WidgetLayout == WidgetLayoutMode.Separate;

    public string SelectedLayoutDescription =>
        LayoutOptions.FirstOrDefault(option => option.Value == WidgetLayout)?.Description ?? string.Empty;

    public string SelectedThemeDescription =>
        ThemeOptions.FirstOrDefault(option => option.Value == Theme)?.Description ?? string.Empty;

    public string SelectedCompanionLabel =>
        CompanionOptions.FirstOrDefault(option => option.Value == SelectedCompanion)?.Label
        ?? SelectedCompanion.DisplayName();

    public string SelectedCompanionDescription => ThemeResourceManager.GetString(
        $"Companion.Description.{SelectedCompanion}",
        SelectedCompanion.DisplayName());

    public string CompanionSensitivityDescription
    {
        get
        {
            var thresholds = CompanionSensitivity.Thresholds();
            return string.Format(
                ThemeResourceManager.GetString(
                    "Settings.CompanionSensitivityFormat",
                    "Focus {0:0}% · pace {1:0}%p/h"),
                thresholds.FocusedPressure,
                thresholds.FocusedBurnRate);
        }
    }

    public bool SeparateClaudeWidgetEnabled
    {
        get => _settings.SeparateClaudeWidgetEnabled;
        set
        {
            if (!value && !_settings.SeparateCodexWidgetEnabled)
            {
                OnPropertyChanged();
                return;
            }

            Change(
                nameof(AppSettings.SeparateClaudeWidgetEnabled),
                value,
                () => _settings.SeparateClaudeWidgetEnabled,
                current => _settings.SeparateClaudeWidgetEnabled = current);
        }
    }

    public bool CanDisableSeparateClaudeWidget =>
        !SeparateClaudeWidgetEnabled || SeparateCodexWidgetEnabled;

    public bool SeparateCodexWidgetEnabled
    {
        get => _settings.SeparateCodexWidgetEnabled;
        set
        {
            if (!value && !_settings.SeparateClaudeWidgetEnabled)
            {
                OnPropertyChanged();
                return;
            }

            Change(
                nameof(AppSettings.SeparateCodexWidgetEnabled),
                value,
                () => _settings.SeparateCodexWidgetEnabled,
                current => _settings.SeparateCodexWidgetEnabled = current);
        }
    }

    public bool CanDisableSeparateCodexWidget =>
        !SeparateCodexWidgetEnabled || SeparateClaudeWidgetEnabled;

    public bool ShowCodexSpark
    {
        get => _settings.ShowCodexSpark;
        set => Change(
            nameof(AppSettings.ShowCodexSpark),
            value,
            () => _settings.ShowCodexSpark,
            current => _settings.ShowCodexSpark = current);
    }

    public bool CompanionEnabled
    {
        get => _settings.CompanionEnabled;
        set => Change(
            nameof(AppSettings.CompanionEnabled),
            value,
            () => _settings.CompanionEnabled,
            current => _settings.CompanionEnabled = current);
    }

    public CompanionKind SelectedCompanion
    {
        get => _settings.SelectedCompanion;
        set
        {
            if (_settings.SelectedCompanion == value)
            {
                return;
            }

            _settings.SelectedCompanion = value;
            OnPropertyChanged(nameof(SelectedCompanionLabel));
            OnPropertyChanged(nameof(SelectedCompanionDescription));
            Persist(nameof(AppSettings.SelectedCompanion));
        }
    }

    public MimoSensitivity CompanionSensitivity
    {
        get => _settings.CompanionSensitivity;
        set
        {
            if (_settings.CompanionSensitivity == value)
            {
                return;
            }

            _settings.CompanionSensitivity = value;
            OnPropertyChanged(nameof(CompanionSensitivityDescription));
            Persist(nameof(AppSettings.CompanionSensitivity));
        }
    }

    public MimoAnimationMode CompanionAnimationMode
    {
        get => _settings.CompanionAnimationMode;
        set => Change(
            nameof(AppSettings.CompanionAnimationMode),
            value,
            () => _settings.CompanionAnimationMode,
            current => _settings.CompanionAnimationMode = current);
    }

    public bool ReducedMotion
    {
        get => _settings.ReducedMotion;
        set => Change(
            nameof(AppSettings.ReducedMotion),
            value,
            () => _settings.ReducedMotion,
            current => _settings.ReducedMotion = current);
    }

    public bool UsageHistoryEnabled
    {
        get => _settings.UsageHistoryEnabled;
        set => Change(
            nameof(AppSettings.UsageHistoryEnabled),
            value,
            () => _settings.UsageHistoryEnabled,
            current => _settings.UsageHistoryEnabled = current);
    }

    public bool ClaudeCloudEnabled
    {
        get => _settings.ClaudeCloudEnabled;
        set => Change(
            nameof(AppSettings.ClaudeCloudEnabled),
            value,
            () => _settings.ClaudeCloudEnabled,
            current => _settings.ClaudeCloudEnabled = current);
    }

    public bool StartWithWindows
    {
        get => _settings.StartWithWindows;
        set => Change(
            nameof(AppSettings.StartWithWindows),
            value,
            () => _settings.StartWithWindows,
            current => _settings.StartWithWindows = current);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _settings.PropertyChanged -= OnSettingsPropertyChanged;
        _history.Store.Changed -= OnHistoryStoreChanged;
        GC.SuppressFinalize(this);
    }

    private void RebuildOptions()
    {
        AppearanceOptions =
        [
            Option(AppearanceMode.System, "Appearance.System", "Auto") with { Icon = "◐" },
            Option(AppearanceMode.Light, "Appearance.Light", "Light") with { Icon = "☀" },
            Option(AppearanceMode.Dark, "Appearance.Dark", "Dark") with { Icon = "☾" },
        ];
        ThemeOptions =
        [
            Option(ThemeKind.Daangn, "Theme.Daangn", "Daangn style", "Theme.DaangnDescription", "Warm orange with ring usage"),
            Option(ThemeKind.Toss, "Theme.Toss", "Toss style", "Theme.TossDescription", "Calm blue with bar usage"),
            Option(ThemeKind.Hybrid, "Theme.Hybrid", "Hybrid", "Theme.HybridDescription", "Midnight gradient with highlighted bars"),
        ];
        LayoutOptions =
        [
            Option(WidgetLayoutMode.Stacked, "Layout.Stacked", "Stack", "Layout.StackedDescription", "Show Claude and Codex vertically") with { Icon = "↕" },
            Option(WidgetLayoutMode.Horizontal, "Layout.Horizontal", "Wide", "Layout.HorizontalDescription", "Place both providers side by side") with { Icon = "↔" },
            Option(WidgetLayoutMode.Paged, "Layout.Paged", "Pages", "Layout.PagedDescription", "Switch providers in a compact widget") with { Icon = "▣" },
            Option(WidgetLayoutMode.Separate, "Layout.Separate", "Split", "Layout.SeparateDescription", "Show independent provider windows") with { Icon = "▦" },
        ];
        LanguageOptions =
        [
            Option(AppLanguage.Korean, "Language.Korean", "한국어"),
            Option(AppLanguage.English, "Language.English", "English"),
        ];
        CompanionOptions = Enum.GetValues<CompanionKind>()
            .Select(value => Option(value, $"Companion.{value}", value.ToString()))
            .ToArray();
        CompanionSensitivityOptions =
        [
            Option(MimoSensitivity.Responsive, "CompanionSensitivity.Responsive", "Responsive"),
            Option(MimoSensitivity.Balanced, "CompanionSensitivity.Balanced", "Balanced"),
            Option(MimoSensitivity.Relaxed, "CompanionSensitivity.Relaxed", "Relaxed"),
        ];
        CompanionAnimationOptions =
        [
            Option(MimoAnimationMode.Automatic, "CompanionAnimation.Automatic", "Automatic"),
            Option(MimoAnimationMode.Lively, "CompanionAnimation.Lively", "Lively"),
            Option(MimoAnimationMode.Still, "CompanionAnimation.Still", "Still"),
        ];

        OnPropertyChanged(nameof(AppearanceOptions));
        OnPropertyChanged(nameof(ThemeOptions));
        OnPropertyChanged(nameof(LayoutOptions));
        OnPropertyChanged(nameof(LanguageOptions));
        OnPropertyChanged(nameof(CompanionOptions));
        OnPropertyChanged(nameof(CompanionSensitivityOptions));
        OnPropertyChanged(nameof(CompanionAnimationOptions));
        OnPropertyChanged(nameof(SelectedLayoutDescription));
        OnPropertyChanged(nameof(SelectedThemeDescription));
        OnPropertyChanged(nameof(SelectedCompanionLabel));
        OnPropertyChanged(nameof(SelectedCompanionDescription));
        OnPropertyChanged(nameof(CompanionSensitivityDescription));
        OnPropertyChanged(nameof(WidgetAlwaysOnTopDescription));
        OnPropertyChanged(nameof(AppVersionText));
    }

    private static SettingOption<T> Option<T>(T value, string key, string fallback) =>
        new(value, ThemeResourceManager.GetString(key, fallback));

    private static SettingOption<T> Option<T>(
        T value,
        string key,
        string fallback,
        string descriptionKey,
        string descriptionFallback) =>
        new(
            value,
            ThemeResourceManager.GetString(key, fallback),
            ThemeResourceManager.GetString(descriptionKey, descriptionFallback));

    private void Change<T>(
        string propertyName,
        T value,
        Func<T> getter,
        Action<T> setter)
    {
        if (EqualityComparer<T>.Default.Equals(getter(), value))
        {
            return;
        }

        setter(value);
        if (propertyName == nameof(AppSettings.Theme))
        {
            OnPropertyChanged(nameof(SelectedThemeDescription));
        }

        Persist(propertyName);
    }

    private void Persist(string propertyName)
    {
        if (!_persistChanges)
        {
            HasPersistenceError = false;
            return;
        }

        if (!SettingsStore.Save(_settings))
        {
            HasPersistenceError = true;
            OnPropertyChanged(nameof(PersistenceErrorText));
            return;
        }

        HasPersistenceError = false;
        SettingsChanged?.Invoke(this, new SettingChangedEventArgs(propertyName));
    }

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        OnPropertyChanged(e.PropertyName);
        if (e.PropertyName == nameof(AppSettings.WidgetLayout))
        {
            OnPropertyChanged(nameof(IsSeparateLayout));
            OnPropertyChanged(nameof(SelectedLayoutDescription));
        }
        else if (e.PropertyName == nameof(AppSettings.WidgetAlwaysOnTop))
        {
            OnPropertyChanged(nameof(WidgetAlwaysOnTopDescription));
        }
        else if (e.PropertyName is nameof(AppSettings.SeparateClaudeWidgetEnabled)
                 or nameof(AppSettings.SeparateCodexWidgetEnabled))
        {
            OnPropertyChanged(nameof(CanDisableSeparateClaudeWidget));
            OnPropertyChanged(nameof(CanDisableSeparateCodexWidget));
        }
        else if (e.PropertyName == nameof(AppSettings.Theme))
        {
            OnPropertyChanged(nameof(SelectedThemeDescription));
        }
        else if (e.PropertyName == nameof(AppSettings.SelectedCompanion))
        {
            OnPropertyChanged(nameof(SelectedCompanionLabel));
            OnPropertyChanged(nameof(SelectedCompanionDescription));
        }
        else if (e.PropertyName == nameof(AppSettings.CompanionSensitivity))
        {
            OnPropertyChanged(nameof(CompanionSensitivityDescription));
        }
    }

    private void OnHistoryStoreChanged(object? sender, EventArgs e)
    {
        if (_disposed)
        {
            return;
        }

        var dispatcher = WpfApplication.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            if (!_disposed)
            {
                OnPropertyChanged(nameof(HasHistorySamples));
            }
        }
        else
        {
            _ = dispatcher.BeginInvoke(() =>
            {
                if (!_disposed)
                {
                    OnPropertyChanged(nameof(HasHistorySamples));
                }
            });
        }
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }
}
