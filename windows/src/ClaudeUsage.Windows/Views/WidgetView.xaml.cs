using System.ComponentModel;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;

namespace ClaudeUsage.Windows.Views;

public partial class WidgetView : System.Windows.Controls.UserControl
{
    public static readonly DependencyProperty PanelKindProperty = DependencyProperty.Register(
        nameof(PanelKind),
        typeof(WidgetPanelKind),
        typeof(WidgetView),
        new PropertyMetadata(WidgetPanelKind.Combined, OnPanelKindChanged));

    private WidgetViewModel? _viewModel;
    private readonly SystemMotionSettings _systemMotionSettings;

    public WidgetView()
        : this(SystemMotionSettings.Current)
    {
    }

    internal WidgetView(SystemMotionSettings systemMotionSettings)
    {
        _systemMotionSettings = systemMotionSettings
            ?? throw new ArgumentNullException(nameof(systemMotionSettings));
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        UpdateSurfaceVisibility();
    }

    public WidgetPanelKind PanelKind
    {
        get => (WidgetPanelKind)GetValue(PanelKindProperty);
        set => SetValue(PanelKindProperty, value);
    }

    private static void OnPanelKindChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e) =>
        ((WidgetView)sender).UpdateSurfaceVisibility();

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
        => AttachViewModel(e.NewValue as WidgetViewModel);

    private void AttachViewModel(WidgetViewModel? viewModel)
    {
        if (_viewModel is not null)
        {
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
        }

        _viewModel = viewModel;
        if (_viewModel is not null)
        {
            _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        }

        UpdateSurfaceVisibility();
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(WidgetViewModel.Layout)
            or nameof(WidgetViewModel.IsStackedLayout)
            or nameof(WidgetViewModel.IsHorizontalLayout)
            or nameof(WidgetViewModel.IsPagedLayout))
        {
            UpdateSurfaceVisibility();
        }
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        PropertyChangedEventManager.RemoveHandler(
            _systemMotionSettings,
            OnSystemMotionSettingsChanged,
            nameof(SystemMotionSettings.AnimationsEnabled));
        PropertyChangedEventManager.AddHandler(
            _systemMotionSettings,
            OnSystemMotionSettingsChanged,
            nameof(SystemMotionSettings.AnimationsEnabled));
        if (!ReferenceEquals(_viewModel, DataContext))
        {
            AttachViewModel(DataContext as WidgetViewModel);
            return;
        }

        if (_viewModel is not null)
        {
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
            _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        }
        UpdateSurfaceVisibility();
    }

    private void UpdateSurfaceVisibility()
    {
        if (CombinedLayoutHost is null)
        {
            return;
        }

        var isCombined = PanelKind == WidgetPanelKind.Combined;
        CombinedLayoutHost.Visibility = isCombined ? Visibility.Visible : Visibility.Collapsed;
        ClaudeSurface.Visibility = PanelKind == WidgetPanelKind.Claude
            ? Visibility.Visible
            : Visibility.Collapsed;
        CodexSurface.Visibility = PanelKind == WidgetPanelKind.Codex
            ? Visibility.Visible
            : Visibility.Collapsed;

        StackedSurface.Visibility = isCombined && (_viewModel?.IsStackedLayout ?? true)
            ? Visibility.Visible
            : Visibility.Collapsed;
        HorizontalSurface.Visibility = isCombined && _viewModel?.IsHorizontalLayout == true
            ? Visibility.Visible
            : Visibility.Collapsed;
        PagedSurface.Visibility = isCombined && _viewModel?.IsPagedLayout == true
            ? Visibility.Visible
            : Visibility.Collapsed;
        InvalidateMeasure();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        PropertyChangedEventManager.RemoveHandler(
            _systemMotionSettings,
            OnSystemMotionSettingsChanged,
            nameof(SystemMotionSettings.AnimationsEnabled));
        if (_viewModel is not null)
        {
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
        }
    }

    private void OnSystemMotionSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_systemMotionSettings.ReduceMotion)
        {
            StopPagedTransition();
        }
    }

    private void StopPagedTransition()
    {
        if (PagedCard.RenderTransform is TranslateTransform translate)
        {
            translate.BeginAnimation(TranslateTransform.XProperty, null);
            translate.X = 0;
        }

        PagedCard.BeginAnimation(OpacityProperty, null);
        PagedCard.Opacity = 1;
    }

    private void OnPagedCardDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (!IsLoaded
            || _systemMotionSettings.ReduceMotion
            || DataContext is WidgetViewModel { Companion.ReducedMotion: true })
        {
            return;
        }

        var direction = e.NewValue is ProviderWidgetViewModel { Provider: WidgetProviderKind.Claude }
            ? -8d
            : 8d;
        var translate = new TranslateTransform(direction, 0);
        PagedCard.RenderTransform = translate;
        PagedCard.Opacity = 0.45;
        translate.BeginAnimation(
            TranslateTransform.XProperty,
            new DoubleAnimation(0, TimeSpan.FromMilliseconds(180))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
            });
        PagedCard.BeginAnimation(
            OpacityProperty,
            new DoubleAnimation(1, TimeSpan.FromMilliseconds(150)));
    }
}
