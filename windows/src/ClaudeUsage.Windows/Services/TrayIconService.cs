using System.ComponentModel;
using System.Drawing;
using System.IO;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.ViewModels;
using ClaudeUsage.Windows.Views;
using Forms = System.Windows.Forms;

namespace ClaudeUsage.Windows.Services;

public sealed class TrayIconService : IDisposable
{
    private readonly UsageViewModel _viewModel;
    private readonly AppSettings _settings;
    private readonly TrayIconController _controller;
    private bool _disposed;

    public TrayIconService(
        UsageViewModel viewModel,
        FlyoutWindow flyout,
        UsageCoordinator coordinator,
        AppSettings settings,
        Action toggleWidget,
        Action toggleStartWithWindows,
        Action openSettings,
        Action openClaudeLogin,
        Action exitApplication)
    {
        _viewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        _settings = settings ?? throw new ArgumentNullException(nameof(settings));
        ArgumentNullException.ThrowIfNull(flyout);
        ArgumentNullException.ThrowIfNull(coordinator);
        ArgumentNullException.ThrowIfNull(toggleWidget);
        ArgumentNullException.ThrowIfNull(toggleStartWithWindows);
        ArgumentNullException.ThrowIfNull(openSettings);
        ArgumentNullException.ThrowIfNull(openClaudeLogin);
        ArgumentNullException.ThrowIfNull(exitApplication);

        _controller = new TrayIconController(
            new WinFormsTrayIconBackend(LoadApplicationIcon()),
            new TrayIconCallbacks(
                Activate: flyout.ToggleVisibility,
                OpenUsage: flyout.ShowNearNotificationArea,
                ToggleWidget: toggleWidget,
                Refresh: () => _ = coordinator.RefreshAsync(),
                OpenClaudeLogin: openClaudeLogin,
                ChooseCodexExecutable: () =>
                {
                    flyout.ShowNearNotificationArea();
                    flyout.ChooseExecutable();
                },
                ToggleStartWithWindows: toggleStartWithWindows,
                OpenSettings: openSettings,
                ExitApplication: exitApplication),
            _viewModel.TrayTooltip,
            CreatePresentation());

        _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        _settings.PropertyChanged += OnSettingsPropertyChanged;
        ThemeResourceManager.ResourcesChanged += OnResourcesChanged;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
        _settings.PropertyChanged -= OnSettingsPropertyChanged;
        ThemeResourceManager.ResourcesChanged -= OnResourcesChanged;
        _controller.Dispose();
        GC.SuppressFinalize(this);
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(UsageViewModel.TrayTooltip))
        {
            _controller.UpdateTooltip(_viewModel.TrayTooltip);
        }
    }

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppSettings.FloatingWidgetVisible)
            or nameof(AppSettings.StartWithWindows))
        {
            _controller.UpdatePresentation(CreatePresentation());
        }
    }

    private void OnResourcesChanged(object? sender, EventArgs e) =>
        _controller.UpdatePresentation(CreatePresentation());

    private TrayIconPresentation CreatePresentation() => new(
        OpenUsage: Text("UI.OpenUsage", "Open usage"),
        ToggleWidget: _settings.FloatingWidgetVisible
            ? Text("UI.HideWidget", "Hide widget")
            : Text("UI.ShowWidget", "Show widget"),
        Refresh: Text("UI.Refresh", "Refresh"),
        ClaudeLogin: Text("UI.ClaudeLogin", "Sign in to Claude"),
        ChooseCodexExecutable: Text("UI.ChooseCodex", "Choose Codex executable"),
        ToggleStartWithWindows: Text("Settings.StartWithWindows", "Start with Windows"),
        StartWithWindowsChecked: _settings.StartWithWindows,
        Settings: Text("UI.Settings", "Settings"),
        Quit: Text("UI.Quit", "Quit"));

    private static string Text(string key, string fallback) =>
        ThemeResourceManager.GetString(key, fallback);

    private static Icon LoadApplicationIcon()
    {
        var executablePath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(executablePath))
        {
            try
            {
                var icon = Icon.ExtractAssociatedIcon(executablePath);
                if (icon is not null)
                {
                    return icon;
                }
            }
            catch (Exception exception) when (exception is ArgumentException or IOException)
            {
                // Fall through to a system icon if the host does not expose an icon.
            }
        }

        return (Icon)SystemIcons.Application.Clone();
    }
}

internal enum TrayMenuCommand
{
    OpenUsage,
    ToggleWidget,
    Refresh,
    ClaudeLogin,
    ChooseCodexExecutable,
    ToggleStartWithWindows,
    Settings,
    Quit,
}

internal sealed class TrayMenuCommandEventArgs(TrayMenuCommand command) : EventArgs
{
    public TrayMenuCommand Command { get; } = command;
}

internal interface ITrayIconBackend : IDisposable
{
    event EventHandler? LeftClickActivated;

    event EventHandler<TrayMenuCommandEventArgs>? CommandInvoked;

    string Tooltip { set; }

    void SetMenuItem(TrayMenuCommand command, string text, bool isChecked = false);

    void Show();
}

internal sealed record TrayIconCallbacks(
    Action Activate,
    Action OpenUsage,
    Action ToggleWidget,
    Action Refresh,
    Action OpenClaudeLogin,
    Action ChooseCodexExecutable,
    Action ToggleStartWithWindows,
    Action OpenSettings,
    Action ExitApplication);

internal sealed record TrayIconPresentation(
    string OpenUsage,
    string ToggleWidget,
    string Refresh,
    string ClaudeLogin,
    string ChooseCodexExecutable,
    string ToggleStartWithWindows,
    bool StartWithWindowsChecked,
    string Settings,
    string Quit);

/// <summary>
/// Pure tray interaction adapter. It keeps application callbacks and tray state
/// independent from the WinForms shell implementation so lifecycle behavior is
/// testable without creating a notification-area icon.
/// </summary>
internal sealed class TrayIconController : IDisposable
{
    private const int MaximumTooltipLength = 63;

    private readonly ITrayIconBackend _backend;
    private readonly TrayIconCallbacks _callbacks;
    private bool _disposed;

    public TrayIconController(
        ITrayIconBackend backend,
        TrayIconCallbacks callbacks,
        string initialTooltip,
        TrayIconPresentation initialPresentation)
    {
        _backend = backend ?? throw new ArgumentNullException(nameof(backend));
        _callbacks = callbacks ?? throw new ArgumentNullException(nameof(callbacks));
        ArgumentNullException.ThrowIfNull(initialTooltip);
        ArgumentNullException.ThrowIfNull(initialPresentation);

        _backend.LeftClickActivated += OnLeftClickActivated;
        _backend.CommandInvoked += OnCommandInvoked;
        UpdateTooltip(initialTooltip);
        UpdatePresentation(initialPresentation);
        _backend.Show();
    }

    public void UpdateTooltip(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        if (_disposed)
        {
            return;
        }

        _backend.Tooltip = text.Length <= MaximumTooltipLength
            ? text
            : text[..MaximumTooltipLength];
    }

    public void UpdatePresentation(TrayIconPresentation presentation)
    {
        ArgumentNullException.ThrowIfNull(presentation);
        if (_disposed)
        {
            return;
        }

        _backend.SetMenuItem(TrayMenuCommand.OpenUsage, presentation.OpenUsage);
        _backend.SetMenuItem(TrayMenuCommand.ToggleWidget, presentation.ToggleWidget);
        _backend.SetMenuItem(TrayMenuCommand.Refresh, presentation.Refresh);
        _backend.SetMenuItem(TrayMenuCommand.ClaudeLogin, presentation.ClaudeLogin);
        _backend.SetMenuItem(
            TrayMenuCommand.ChooseCodexExecutable,
            presentation.ChooseCodexExecutable);
        _backend.SetMenuItem(
            TrayMenuCommand.ToggleStartWithWindows,
            presentation.ToggleStartWithWindows,
            presentation.StartWithWindowsChecked);
        _backend.SetMenuItem(TrayMenuCommand.Settings, presentation.Settings);
        _backend.SetMenuItem(TrayMenuCommand.Quit, presentation.Quit);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _backend.LeftClickActivated -= OnLeftClickActivated;
        _backend.CommandInvoked -= OnCommandInvoked;
        _backend.Dispose();
    }

    private void OnLeftClickActivated(object? sender, EventArgs e) => _callbacks.Activate();

    private void OnCommandInvoked(object? sender, TrayMenuCommandEventArgs e)
    {
        var callback = e.Command switch
        {
            TrayMenuCommand.OpenUsage => _callbacks.OpenUsage,
            TrayMenuCommand.ToggleWidget => _callbacks.ToggleWidget,
            TrayMenuCommand.Refresh => _callbacks.Refresh,
            TrayMenuCommand.ClaudeLogin => _callbacks.OpenClaudeLogin,
            TrayMenuCommand.ChooseCodexExecutable => _callbacks.ChooseCodexExecutable,
            TrayMenuCommand.ToggleStartWithWindows => _callbacks.ToggleStartWithWindows,
            TrayMenuCommand.Settings => _callbacks.OpenSettings,
            TrayMenuCommand.Quit => _callbacks.ExitApplication,
            _ => throw new ArgumentOutOfRangeException(nameof(e), e.Command, "Unknown tray command."),
        };

        callback();
    }
}

internal sealed class WinFormsTrayIconBackend : ITrayIconBackend
{
    private readonly Forms.NotifyIcon _notifyIcon;
    private readonly Forms.ContextMenuStrip _menu;
    private readonly IReadOnlyDictionary<TrayMenuCommand, Forms.ToolStripMenuItem> _items;
    private readonly Icon _icon;
    private bool _disposed;

    public WinFormsTrayIconBackend(Icon icon)
    {
        _icon = icon ?? throw new ArgumentNullException(nameof(icon));
        _menu = new Forms.ContextMenuStrip();

        var items = Enum.GetValues<TrayMenuCommand>()
            .ToDictionary(command => command, CreateMenuItem);
        _items = items;
        _menu.Items.AddRange(
        [
            items[TrayMenuCommand.OpenUsage],
            items[TrayMenuCommand.ToggleWidget],
            items[TrayMenuCommand.Refresh],
            new Forms.ToolStripSeparator(),
            items[TrayMenuCommand.ClaudeLogin],
            items[TrayMenuCommand.ChooseCodexExecutable],
            items[TrayMenuCommand.ToggleStartWithWindows],
            items[TrayMenuCommand.Settings],
            new Forms.ToolStripSeparator(),
            items[TrayMenuCommand.Quit],
        ]);

        _notifyIcon = new Forms.NotifyIcon
        {
            Icon = _icon,
            ContextMenuStrip = _menu,
        };
        _notifyIcon.MouseUp += OnMouseUp;
    }

    public event EventHandler? LeftClickActivated;

    public event EventHandler<TrayMenuCommandEventArgs>? CommandInvoked;

    public string Tooltip
    {
        set => _notifyIcon.Text = value;
    }

    public void SetMenuItem(TrayMenuCommand command, string text, bool isChecked = false)
    {
        var item = _items[command];
        item.Text = text;
        item.Checked = isChecked;
    }

    public void Show() => _notifyIcon.Visible = true;

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _notifyIcon.MouseUp -= OnMouseUp;
        _notifyIcon.Visible = false;
        _menu.Dispose();
        _notifyIcon.Dispose();
        _icon.Dispose();
    }

    private Forms.ToolStripMenuItem CreateMenuItem(TrayMenuCommand command) =>
        new(string.Empty, null, (_, _) =>
            CommandInvoked?.Invoke(this, new TrayMenuCommandEventArgs(command)));

    private void OnMouseUp(object? sender, Forms.MouseEventArgs e)
    {
        if (e.Button == Forms.MouseButtons.Left)
        {
            LeftClickActivated?.Invoke(this, EventArgs.Empty);
        }
    }
}
