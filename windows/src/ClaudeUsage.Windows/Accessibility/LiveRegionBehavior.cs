using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Threading;

namespace ClaudeUsage.Windows.Accessibility;

/// <summary>
/// Turns a WPF <see cref="TextBlock"/> live-region declaration into the UIA
/// event assistive technology actually listens for when the displayed text
/// changes. WPF does not raise LiveRegionChanged from LiveSetting alone.
/// </summary>
public static class LiveRegionBehavior
{
    public static readonly DependencyProperty AnnounceOnTextChangedProperty =
        DependencyProperty.RegisterAttached(
            "AnnounceOnTextChanged",
            typeof(bool),
            typeof(LiveRegionBehavior),
            new PropertyMetadata(false, OnAnnounceOnTextChangedChanged));

    private static readonly DependencyPropertyDescriptor TextDescriptor =
        DependencyPropertyDescriptor.FromProperty(TextBlock.TextProperty, typeof(TextBlock));
    private static readonly DependencyPropertyDescriptor IsVisibleDescriptor =
        DependencyPropertyDescriptor.FromProperty(UIElement.IsVisibleProperty, typeof(UIElement));

    private static readonly ConditionalWeakTable<TextBlock, Subscription> Subscriptions = new();

    public static bool GetAnnounceOnTextChanged(DependencyObject element) =>
        (bool)element.GetValue(AnnounceOnTextChangedProperty);

    public static void SetAnnounceOnTextChanged(DependencyObject element, bool value) =>
        element.SetValue(AnnounceOnTextChangedProperty, value);

    internal static bool RaiseLiveRegionChanged(
        TextBlock element,
        Func<AutomationEvents, bool>? listenerExists = null,
        Func<TextBlock, AutomationPeer?>? peerFactory = null,
        Action<AutomationPeer, AutomationEvents>? eventRaiser = null)
    {
        ArgumentNullException.ThrowIfNull(element);

        listenerExists ??= AutomationPeer.ListenerExists;
        if (!listenerExists(AutomationEvents.LiveRegionChanged))
        {
            return false;
        }

        peerFactory ??= static textBlock =>
            UIElementAutomationPeer.FromElement(textBlock)
            ?? UIElementAutomationPeer.CreatePeerForElement(textBlock);
        var peer = peerFactory(element);
        if (peer is null)
        {
            return false;
        }

        eventRaiser ??= static (automationPeer, automationEvent) =>
            automationPeer.RaiseAutomationEvent(automationEvent);
        eventRaiser(peer, AutomationEvents.LiveRegionChanged);
        return true;
    }

    private static void OnAnnounceOnTextChangedChanged(
        DependencyObject dependencyObject,
        DependencyPropertyChangedEventArgs e)
    {
        if (dependencyObject is not TextBlock textBlock)
        {
            return;
        }

        if ((bool)e.NewValue)
        {
            Subscriptions.GetValue(textBlock, static target => new Subscription(target)).Start();
            return;
        }

        if (Subscriptions.TryGetValue(textBlock, out var subscription))
        {
            subscription.Dispose();
            Subscriptions.Remove(textBlock);
        }
    }

    private sealed class Subscription : IDisposable
    {
        private readonly TextBlock _target;
        private bool _isObservingText;
        private bool _announcementPending;
        private bool _isDisposed;

        public Subscription(TextBlock target) => _target = target;

        public void Start()
        {
            if (_isDisposed)
            {
                return;
            }

            _target.Loaded -= OnLoaded;
            _target.Loaded += OnLoaded;
            _target.Unloaded -= OnUnloaded;
            _target.Unloaded += OnUnloaded;

            if (_target.IsLoaded)
            {
                StartObservingText();
            }
        }

        public void Dispose()
        {
            if (_isDisposed)
            {
                return;
            }

            _isDisposed = true;
            _target.Loaded -= OnLoaded;
            _target.Unloaded -= OnUnloaded;
            StopObservingText();
        }

        private void OnLoaded(object sender, RoutedEventArgs e) => StartObservingText();

        private void OnUnloaded(object sender, RoutedEventArgs e)
        {
            _announcementPending = false;
            StopObservingText();
        }

        private void StartObservingText()
        {
            if (_isObservingText || _isDisposed)
            {
                return;
            }

            TextDescriptor.AddValueChanged(_target, OnTextChanged);
            IsVisibleDescriptor.AddValueChanged(_target, OnTextChanged);
            _isObservingText = true;
        }

        private void StopObservingText()
        {
            if (!_isObservingText)
            {
                return;
            }

            TextDescriptor.RemoveValueChanged(_target, OnTextChanged);
            IsVisibleDescriptor.RemoveValueChanged(_target, OnTextChanged);
            _isObservingText = false;
        }

        private void OnTextChanged(object? sender, EventArgs e)
        {
            if (_announcementPending
                || _isDisposed
                || AutomationProperties.GetLiveSetting(_target) == AutomationLiveSetting.Off)
            {
                return;
            }

            _announcementPending = true;
            _ = _target.Dispatcher.BeginInvoke(
                DispatcherPriority.ContextIdle,
                new Action(AnnounceCurrentValue));
        }

        private void AnnounceCurrentValue()
        {
            _announcementPending = false;
            if (_isDisposed
                || !_target.IsLoaded
                || !_target.IsVisible
                || string.IsNullOrWhiteSpace(_target.Text))
            {
                return;
            }

            _ = RaiseLiveRegionChanged(_target);
        }
    }
}
