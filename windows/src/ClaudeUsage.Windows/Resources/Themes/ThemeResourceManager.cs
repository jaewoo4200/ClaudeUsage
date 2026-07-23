using System.ComponentModel;
using System.IO;
using System.Security;
using System.Windows;
using ClaudeUsage.Windows.Services;
using Microsoft.Win32;

namespace ClaudeUsage.Windows.Resources.Themes;

/// <summary>
/// Applies theme, appearance, and language dictionaries to the running WPF app.
/// Call <see cref="Initialize"/> once at startup; subsequent settings changes are
/// observed automatically. DynamicResource consumers update without recreating a window.
/// </summary>
public static class ThemeResourceManager
{
    private const string ThemeDictionaryMarker = "Resources/Themes/";
    private const string StringDictionaryMarker = "Resources/Strings.";
    internal const string HighContrastDictionaryPath = "Resources/Themes/HighContrast.xaml";
    private static readonly object ResourcePathMarker = new();

    private static AppSettings? _settings;
    private static bool _isTrackingSystemPreferences;

    public static event EventHandler? ResourcesChanged;

    public static void Initialize(AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        if (!ReferenceEquals(_settings, settings))
        {
            if (_settings is not null)
            {
                _settings.PropertyChanged -= OnSettingsPropertyChanged;
            }

            _settings = settings;
            _settings.PropertyChanged += OnSettingsPropertyChanged;
        }

        if (!_isTrackingSystemPreferences)
        {
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
            SystemParameters.StaticPropertyChanged += OnSystemParametersStaticPropertyChanged;
            _isTrackingSystemPreferences = true;
        }

        Apply(settings);
    }

    public static void Shutdown()
    {
        if (_settings is not null)
        {
            _settings.PropertyChanged -= OnSettingsPropertyChanged;
            _settings = null;
        }

        if (_isTrackingSystemPreferences)
        {
            SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
            SystemParameters.StaticPropertyChanged -= OnSystemParametersStaticPropertyChanged;
            _isTrackingSystemPreferences = false;
        }
    }

    public static void Apply(AppSettings settings)
    {
        var application = System.Windows.Application.Current;
        if (application is null)
        {
            return;
        }

        if (!application.Dispatcher.CheckAccess())
        {
            _ = application.Dispatcher.BeginInvoke(() => Apply(settings));
            return;
        }

        ApplyResources(application.Resources, settings, SystemParameters.HighContrast);
        ResourcesChanged?.Invoke(null, EventArgs.Empty);
    }

    /// <summary>
    /// Applies the same ordered dictionary stack used by the running app. Kept
    /// internal so the live high-contrast transition can be verified without
    /// changing the machine-wide accessibility setting in a test process.
    /// </summary>
    internal static void ApplyResources(
        ResourceDictionary applicationResources,
        AppSettings settings,
        bool highContrast)
    {
        ArgumentNullException.ThrowIfNull(applicationResources);
        ArgumentNullException.ThrowIfNull(settings);

        var dictionaries = applicationResources.MergedDictionaries;
        for (var index = dictionaries.Count - 1; index >= 0; index--)
        {
            var source = GetResourcePath(dictionaries[index]);
            if (source?.Contains(ThemeDictionaryMarker, StringComparison.OrdinalIgnoreCase) == true
                || source?.Contains(StringDictionaryMarker, StringComparison.OrdinalIgnoreCase) == true)
            {
                dictionaries.RemoveAt(index);
            }
        }

        var appearance = ResolveAppearance(settings.Appearance);
        dictionaries.Add(Load($"Resources/Themes/Base.{appearance}.xaml"));
        dictionaries.Add(Load($"Resources/Themes/{settings.Theme}.xaml"));
        dictionaries.Add(Load(settings.Language == AppLanguage.Korean
            ? "Resources/Strings.ko.xaml"
            : "Resources/Strings.en.xaml"));

        // This dictionary must be last: it changes only semantic brushes while
        // preserving every normal-mode theme template and geometry exactly.
        if (highContrast)
        {
            dictionaries.Add(Load(HighContrastDictionaryPath));
        }
    }

    internal static bool ProcessSystemParametersChange(
        ResourceDictionary applicationResources,
        AppSettings settings,
        string? propertyName,
        bool highContrast)
    {
        if (!IsHighContrastPropertyChange(propertyName))
        {
            return false;
        }

        ApplyResources(applicationResources, settings, highContrast);
        return true;
    }

    public static string GetString(string key, string fallback)
    {
        var value = System.Windows.Application.Current?.TryFindResource(key);
        return value as string ?? fallback;
    }

    internal static string? GetResourcePath(ResourceDictionary dictionary)
    {
        ArgumentNullException.ThrowIfNull(dictionary);
        return dictionary.Contains(ResourcePathMarker)
            ? dictionary[ResourcePathMarker] as string
            : dictionary.Source?.OriginalString;
    }

    private static ResourceDictionary Load(string relativePath)
    {
        var uri = new Uri(
            $"/ClaudeUsage.Windows;component/{relativePath}",
            UriKind.Relative);
        var dictionary = (ResourceDictionary)System.Windows.Application.LoadComponent(uri);
        dictionary[ResourcePathMarker] = relativePath;
        return dictionary;
    }

    private static bool IsHighContrastPropertyChange(string? propertyName) =>
        string.IsNullOrEmpty(propertyName)
        || string.Equals(
            propertyName,
            nameof(SystemParameters.HighContrast),
            StringComparison.Ordinal);

    private static string ResolveAppearance(AppearanceMode appearance) => appearance switch
    {
        AppearanceMode.Light => "Light",
        AppearanceMode.Dark => "Dark",
        _ => SystemUsesDarkAppearance() ? "Dark" : "Light",
    };

    private static bool SystemUsesDarkAppearance()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
        }
        catch (Exception exception) when (
            exception is SecurityException or UnauthorizedAccessException or IOException)
        {
            return false;
        }
    }

    private static void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_settings is null)
        {
            return;
        }

        if (e.PropertyName is nameof(AppSettings.Theme)
            or nameof(AppSettings.Appearance)
            or nameof(AppSettings.Language))
        {
            Apply(_settings);
        }
    }

    private static void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (_settings is null)
        {
            return;
        }

        var appearanceChanged = _settings.Appearance == AppearanceMode.System
                                && e.Category is UserPreferenceCategory.General
                                    or UserPreferenceCategory.VisualStyle
                                    or UserPreferenceCategory.Color;
        var highContrastPaletteChanged = SystemParameters.HighContrast
                                         && e.Category is UserPreferenceCategory.Accessibility
                                             or UserPreferenceCategory.General
                                             or UserPreferenceCategory.VisualStyle
                                             or UserPreferenceCategory.Color;

        if (appearanceChanged || highContrastPaletteChanged)
        {
            Apply(_settings);
        }
    }

    private static void OnSystemParametersStaticPropertyChanged(
        object? sender,
        PropertyChangedEventArgs e)
    {
        if (_settings is not null && IsHighContrastPropertyChange(e.PropertyName))
        {
            // Apply marshals to the application dispatcher when Windows raises
            // the accessibility notification from a non-UI thread.
            Apply(_settings);
        }
    }
}
