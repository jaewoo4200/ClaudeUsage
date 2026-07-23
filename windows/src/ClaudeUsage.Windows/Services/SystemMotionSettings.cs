using System.ComponentModel;
using System.Windows;
using System.Windows.Threading;

namespace ClaudeUsage.Windows.Services;

/// <summary>
/// Live, bindable view of the Windows client-area animation preference.
/// SystemParameters properties are static snapshots, so XAML must bind to this notifier instead
/// of binding directly to SystemParameters.ClientAreaAnimation.
/// </summary>
public sealed class SystemMotionSettings : INotifyPropertyChanged
{
    private readonly Func<bool> _animationsEnabledProvider;
    private readonly Dispatcher _dispatcher;
    private bool _animationsEnabled;

    private SystemMotionSettings()
        : this(
            static () => SystemParameters.ClientAreaAnimation,
            ResolveApplicationDispatcher(),
            subscribeToSystemParameters: true)
    {
    }

    internal SystemMotionSettings(
        Func<bool> animationsEnabledProvider,
        Dispatcher dispatcher,
        bool subscribeToSystemParameters = false)
    {
        _animationsEnabledProvider = animationsEnabledProvider
            ?? throw new ArgumentNullException(nameof(animationsEnabledProvider));
        _dispatcher = dispatcher ?? throw new ArgumentNullException(nameof(dispatcher));
        _animationsEnabled = _animationsEnabledProvider();

        if (subscribeToSystemParameters)
        {
            SystemParameters.StaticPropertyChanged += OnSystemParametersStaticPropertyChanged;
        }
    }

    public static SystemMotionSettings Current { get; } = new();

    public event PropertyChangedEventHandler? PropertyChanged;

    public bool AnimationsEnabled => _animationsEnabled;

    public bool ReduceMotion => !_animationsEnabled;

    private static Dispatcher ResolveApplicationDispatcher() =>
        System.Windows.Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;

    private void OnSystemParametersStaticPropertyChanged(object? sender, PropertyChangedEventArgs e) =>
        ProcessSystemParametersChange(e.PropertyName);

    internal void ProcessSystemParametersChange(string? propertyName)
    {
        if (!string.IsNullOrEmpty(propertyName)
            && propertyName != nameof(SystemParameters.ClientAreaAnimation))
        {
            return;
        }

        if (_dispatcher.CheckAccess())
        {
            Refresh();
            return;
        }

        if (!_dispatcher.HasShutdownStarted && !_dispatcher.HasShutdownFinished)
        {
            _dispatcher.BeginInvoke(DispatcherPriority.DataBind, new Action(Refresh));
        }
    }

    private void Refresh()
    {
        var animationsEnabled = _animationsEnabledProvider();
        if (_animationsEnabled == animationsEnabled)
        {
            return;
        }

        _animationsEnabled = animationsEnabled;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(AnimationsEnabled)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ReduceMotion)));
    }
}
