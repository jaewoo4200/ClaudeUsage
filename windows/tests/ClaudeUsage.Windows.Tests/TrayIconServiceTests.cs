using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class TrayIconServiceTests
{
    [Fact]
    public void ControllerCreationPublishesInitialStateBeforeShowingTrayIcon()
    {
        var backend = new RecordingTrayIconBackend();
        var presentation = CreatePresentation(startWithWindowsChecked: true);

        using var controller = new TrayIconController(
            backend,
            CreateCallbacks(),
            "ClaudeUsage ready",
            presentation);

        Assert.Equal("ClaudeUsage ready", backend.TooltipValue);
        Assert.Equal(1, backend.ShowCount);
        Assert.Equal(
            [
                TrayMenuCommand.OpenUsage,
                TrayMenuCommand.ToggleWidget,
                TrayMenuCommand.Refresh,
                TrayMenuCommand.ClaudeLogin,
                TrayMenuCommand.ChooseCodexExecutable,
                TrayMenuCommand.ToggleStartWithWindows,
                TrayMenuCommand.Settings,
                TrayMenuCommand.Quit,
            ],
            backend.MenuItems.Keys);
        Assert.Equal((presentation.OpenUsage, false), backend.MenuItems[TrayMenuCommand.OpenUsage]);
        Assert.Equal((presentation.ToggleWidget, false), backend.MenuItems[TrayMenuCommand.ToggleWidget]);
        Assert.Equal((presentation.Refresh, false), backend.MenuItems[TrayMenuCommand.Refresh]);
        Assert.Equal((presentation.ClaudeLogin, false), backend.MenuItems[TrayMenuCommand.ClaudeLogin]);
        Assert.Equal(
            (presentation.ChooseCodexExecutable, false),
            backend.MenuItems[TrayMenuCommand.ChooseCodexExecutable]);
        Assert.Equal(
            (presentation.ToggleStartWithWindows, true),
            backend.MenuItems[TrayMenuCommand.ToggleStartWithWindows]);
        Assert.Equal((presentation.Settings, false), backend.MenuItems[TrayMenuCommand.Settings]);
        Assert.Equal((presentation.Quit, false), backend.MenuItems[TrayMenuCommand.Quit]);
        Assert.All(backend.Operations.Take(9), operation =>
            Assert.NotEqual("show", operation));
        Assert.Equal("show", backend.Operations[9]);
    }

    [Fact]
    public void LeftClickActivationInvokesFlyoutCallbackOnly()
    {
        var backend = new RecordingTrayIconBackend();
        var activations = 0;
        var menuCallbacks = 0;
        using var controller = new TrayIconController(
            backend,
            CreateCallbacks(
                activate: () => activations++,
                defaultMenuAction: () => menuCallbacks++),
            "ready",
            CreatePresentation());

        backend.RaiseLeftClick();

        Assert.Equal(1, activations);
        Assert.Equal(0, menuCallbacks);
    }

    [Fact]
    public void EveryMenuCommandInvokesItsMatchingApplicationCallback()
    {
        var backend = new RecordingTrayIconBackend();
        var invoked = new List<TrayMenuCommand>();
        using var controller = new TrayIconController(
            backend,
            new TrayIconCallbacks(
                () => throw new InvalidOperationException("Activation is not a menu callback."),
                () => invoked.Add(TrayMenuCommand.OpenUsage),
                () => invoked.Add(TrayMenuCommand.ToggleWidget),
                () => invoked.Add(TrayMenuCommand.Refresh),
                () => invoked.Add(TrayMenuCommand.ClaudeLogin),
                () => invoked.Add(TrayMenuCommand.ChooseCodexExecutable),
                () => invoked.Add(TrayMenuCommand.ToggleStartWithWindows),
                () => invoked.Add(TrayMenuCommand.Settings),
                () => invoked.Add(TrayMenuCommand.Quit)),
            "ready",
            CreatePresentation());

        foreach (var command in Enum.GetValues<TrayMenuCommand>())
        {
            backend.RaiseCommand(command);
        }

        Assert.Equal(Enum.GetValues<TrayMenuCommand>(), invoked);
    }

    [Fact]
    public void TooltipUpdatesAreForwardedAndLimitedToNotifyIconCapacity()
    {
        var backend = new RecordingTrayIconBackend();
        using var controller = new TrayIconController(
            backend,
            CreateCallbacks(),
            "initial",
            CreatePresentation());
        var longTooltip = new string('x', 80);

        controller.UpdateTooltip("updated");
        Assert.Equal("updated", backend.TooltipValue);

        controller.UpdateTooltip(longTooltip);
        Assert.Equal(63, backend.TooltipValue.Length);
        Assert.Equal(longTooltip[..63], backend.TooltipValue);
    }

    [Fact]
    public void DisposeHidesBackendAndDetachesAllCallbacksExactlyOnce()
    {
        var backend = new RecordingTrayIconBackend();
        var callbackCount = 0;
        var controller = new TrayIconController(
            backend,
            CreateCallbacks(
                activate: () => callbackCount++,
                defaultMenuAction: () => callbackCount++),
            "initial",
            CreatePresentation());

        controller.Dispose();
        controller.Dispose();
        backend.RaiseLeftClick();
        backend.RaiseCommand(TrayMenuCommand.Quit);
        controller.UpdateTooltip("ignored after disposal");
        controller.UpdatePresentation(CreatePresentation(startWithWindowsChecked: true));

        Assert.Equal(1, backend.DisposeCount);
        Assert.Equal(0, callbackCount);
        Assert.Equal("initial", backend.TooltipValue);
    }

    private static TrayIconCallbacks CreateCallbacks(
        Action? activate = null,
        Action? defaultMenuAction = null)
    {
        var menuAction = defaultMenuAction ?? (() => { });
        return new TrayIconCallbacks(
            activate ?? (() => { }),
            menuAction,
            menuAction,
            menuAction,
            menuAction,
            menuAction,
            menuAction,
            menuAction,
            menuAction);
    }

    private static TrayIconPresentation CreatePresentation(
        bool startWithWindowsChecked = false) => new(
        OpenUsage: "Open usage",
        ToggleWidget: "Show widget",
        Refresh: "Refresh",
        ClaudeLogin: "Sign in to Claude",
        ChooseCodexExecutable: "Choose Codex executable",
        ToggleStartWithWindows: "Start with Windows",
        StartWithWindowsChecked: startWithWindowsChecked,
        Settings: "Settings",
        Quit: "Quit");

    private sealed class RecordingTrayIconBackend : ITrayIconBackend
    {
        public event EventHandler? LeftClickActivated;

        public event EventHandler<TrayMenuCommandEventArgs>? CommandInvoked;

        public string TooltipValue { get; private set; } = string.Empty;

        public string Tooltip
        {
            set
            {
                TooltipValue = value;
                Operations.Add("tooltip");
            }
        }

        public Dictionary<TrayMenuCommand, (string Text, bool Checked)> MenuItems { get; } = [];

        public List<string> Operations { get; } = [];

        public int ShowCount { get; private set; }

        public int DisposeCount { get; private set; }

        public void SetMenuItem(TrayMenuCommand command, string text, bool isChecked = false)
        {
            MenuItems[command] = (text, isChecked);
            Operations.Add($"menu:{command}");
        }

        public void Show()
        {
            ShowCount++;
            Operations.Add("show");
        }

        public void Dispose() => DisposeCount++;

        public void RaiseLeftClick() => LeftClickActivated?.Invoke(this, EventArgs.Empty);

        public void RaiseCommand(TrayMenuCommand command) =>
            CommandInvoked?.Invoke(this, new TrayMenuCommandEventArgs(command));
    }
}
