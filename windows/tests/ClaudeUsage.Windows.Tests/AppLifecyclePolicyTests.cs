using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using ClaudeUsage.Windows.Views;

namespace ClaudeUsage.Windows.Tests;

public sealed class AppLifecyclePolicyTests
{
    [Theory]
    [InlineData(false, false, 0)]
    [InlineData(false, true, 2)]
    [InlineData(true, false, 1)]
    [InlineData(true, true, 1)]
    public void FlyoutClosePolicyOnlyShutsDownVisualDiagnosticRuns(
        bool isExiting,
        bool forceKeepOpenForDiagnostics,
        int expected)
    {
        Assert.Equal(
            (FlyoutCloseAction)expected,
            FlyoutWindow.ResolveCloseAction(isExiting, forceKeepOpenForDiagnostics));
    }

    [Theory]
    [InlineData(WidgetLayoutMode.Stacked)]
    [InlineData(WidgetLayoutMode.Horizontal)]
    [InlineData(WidgetLayoutMode.Paged)]
    [InlineData(WidgetLayoutMode.Separate)]
    public void BackgroundAndSettingsSynchronizationNeverChooseAnActivationTarget(
        WidgetLayoutMode layout)
    {
        var target = WidgetActivationPlanner.ResolveActivationTarget(
            WidgetActivationPolicy.PreserveForeground,
            layout,
            separateClaudeEnabled: true,
            separateCodexEnabled: true);

        Assert.Null(target);
    }

    [Theory]
    [InlineData(WidgetLayoutMode.Stacked)]
    [InlineData(WidgetLayoutMode.Horizontal)]
    [InlineData(WidgetLayoutMode.Paged)]
    [InlineData(WidgetLayoutMode.Separate)]
    public void DefaultWidgetTogglePreservesTheExistingForeground(WidgetLayoutMode layout)
    {
        Assert.Equal(
            WidgetActivationPolicy.PreserveForeground,
            App.DefaultWidgetToggleActivationPolicy);

        var target = WidgetActivationPlanner.ResolveActivationTarget(
            App.DefaultWidgetToggleActivationPolicy,
            layout,
            separateClaudeEnabled: true,
            separateCodexEnabled: true);

        Assert.Null(target);
    }

    [Theory]
    [InlineData(true, true, WidgetPanelKind.Claude)]
    [InlineData(true, false, WidgetPanelKind.Claude)]
    [InlineData(false, true, WidgetPanelKind.Codex)]
    public void ExplicitTrayToggleChoosesOneEnabledSeparateWidget(
        bool claudeEnabled,
        bool codexEnabled,
        WidgetPanelKind expected)
    {
        var target = WidgetActivationPlanner.ResolveActivationTarget(
            WidgetActivationPolicy.ActivatePrimaryWidget,
            WidgetLayoutMode.Separate,
            claudeEnabled,
            codexEnabled);

        Assert.Equal(expected, target);
    }

    [Fact]
    public void ExplicitTrayToggleHasNoTargetWhenBothSeparateWidgetsAreDisabled()
    {
        var target = WidgetActivationPlanner.ResolveActivationTarget(
            WidgetActivationPolicy.ActivatePrimaryWidget,
            WidgetLayoutMode.Separate,
            separateClaudeEnabled: false,
            separateCodexEnabled: false);

        Assert.Null(target);
    }

    [Fact]
    public void IpcNamesAreStableAndScopedByIdentityAndSession()
    {
        var first = SingleInstanceNames.ForIdentity("S-1-5-21-test-user", 3);
        var same = SingleInstanceNames.ForIdentity("S-1-5-21-test-user", 3);
        var otherUser = SingleInstanceNames.ForIdentity("S-1-5-21-other-user", 3);
        var otherSession = SingleInstanceNames.ForIdentity("S-1-5-21-test-user", 4);

        Assert.Equal(first, same);
        Assert.NotEqual(first, otherUser);
        Assert.NotEqual(first, otherSession);
        Assert.StartsWith(@"Local\ClaudeUsage.Windows.", first.MutexName);
        Assert.StartsWith("ClaudeUsage.Windows.", first.PipeName);
        Assert.DoesNotContain("test-user", first.PipeName, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void SecondaryInstanceForwardsActivationToThePrimaryInstance()
    {
        var suffix = Guid.NewGuid().ToString("N");
        var names = new SingleInstanceNames(
            $@"Local\ClaudeUsage.Windows.Tests.{suffix}",
            $"ClaudeUsage.Windows.Tests.{suffix}");
        var activationCount = 0;
        var primaryStart = SingleInstanceCoordinator.Start(
            names,
            () =>
            {
                Interlocked.Increment(ref activationCount);
                return true;
            },
            TimeSpan.FromSeconds(2));
        Assert.True(primaryStart.IsPrimary);
        Assert.NotNull(primaryStart.Coordinator);

        using var primary = primaryStart.Coordinator!;
        SingleInstanceStartResult secondaryStart = default;
        var secondaryThread = new Thread(() =>
        {
            secondaryStart = SingleInstanceCoordinator.Start(
                names,
                () => true,
                TimeSpan.FromSeconds(3));
        });
        secondaryThread.Start();
        Assert.True(secondaryThread.Join(TimeSpan.FromSeconds(4)));

        Assert.False(secondaryStart.IsPrimary);
        Assert.True(secondaryStart.ActivationForwarded);
        Assert.True(Volatile.Read(ref activationCount) > 0);
    }

    [Fact]
    public void ReleasedPrimaryCanBeReplacedWithoutAStalePipeOrMutex()
    {
        var suffix = Guid.NewGuid().ToString("N");
        var names = new SingleInstanceNames(
            $@"Local\ClaudeUsage.Windows.Tests.{suffix}",
            $"ClaudeUsage.Windows.Tests.{suffix}");
        var firstStart = SingleInstanceCoordinator.Start(
            names,
            () => true,
            TimeSpan.FromSeconds(1));
        Assert.True(firstStart.IsPrimary);
        firstStart.Coordinator!.Dispose();

        var replacementStart = SingleInstanceCoordinator.Start(
            names,
            () => true,
            TimeSpan.FromSeconds(1));
        Assert.True(replacementStart.IsPrimary);
        replacementStart.Coordinator!.Dispose();
    }

    [Fact]
    public void SecondaryDoesNotTreatARejectedShutdownRaceAsDelivered()
    {
        var suffix = Guid.NewGuid().ToString("N");
        var names = new SingleInstanceNames(
            $@"Local\ClaudeUsage.Windows.Tests.{suffix}",
            $"ClaudeUsage.Windows.Tests.{suffix}");
        var requestCount = 0;
        var primaryStart = SingleInstanceCoordinator.Start(
            names,
            () =>
            {
                Interlocked.Increment(ref requestCount);
                return false;
            },
            TimeSpan.FromSeconds(1));
        Assert.True(primaryStart.IsPrimary);

        using var primary = primaryStart.Coordinator!;
        SingleInstanceStartResult secondaryStart = default;
        var secondaryThread = new Thread(() =>
        {
            secondaryStart = SingleInstanceCoordinator.Start(
                names,
                () => true,
                TimeSpan.FromMilliseconds(350));
        });
        secondaryThread.Start();
        Assert.True(secondaryThread.Join(TimeSpan.FromSeconds(2)));

        Assert.True(Volatile.Read(ref requestCount) > 0);
        Assert.False(secondaryStart.IsPrimary);
        Assert.False(secondaryStart.ActivationForwarded);
    }
}
