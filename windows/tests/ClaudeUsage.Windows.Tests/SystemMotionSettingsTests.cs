using System.Windows;
using System.Windows.Automation;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Threading;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Controls;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.Views;

namespace ClaudeUsage.Windows.Tests;

public sealed class SystemMotionSettingsTests
{
    [Fact]
    public void RelevantSystemParameterChangesPublishBothLiveMotionProperties()
    {
        RunSta(() =>
        {
            var sourceValue = true;
            var settings = new SystemMotionSettings(
                () => sourceValue,
                Dispatcher.CurrentDispatcher);
            var changes = new List<string?>();
            settings.PropertyChanged += (_, e) => changes.Add(e.PropertyName);

            sourceValue = false;
            settings.ProcessSystemParametersChange(nameof(SystemParameters.MenuAnimation));
            Assert.True(settings.AnimationsEnabled);
            Assert.Empty(changes);

            settings.ProcessSystemParametersChange(nameof(SystemParameters.ClientAreaAnimation));
            Assert.False(settings.AnimationsEnabled);
            Assert.True(settings.ReduceMotion);
            Assert.Equal(
                [nameof(SystemMotionSettings.AnimationsEnabled), nameof(SystemMotionSettings.ReduceMotion)],
                changes);

            sourceValue = true;
            settings.ProcessSystemParametersChange(propertyName: null);
            Assert.True(settings.AnimationsEnabled);
            Assert.False(settings.ReduceMotion);
        });
    }

    [Fact]
    public void SpinnerTriggersBindToTheSharedLiveMotionState()
    {
        RunSta(() =>
        {
            var flyoutSection = new FlyoutProviderSection();
            flyoutSection.Measure(new Size(320, 400));
            flyoutSection.Arrange(new Rect(0, 0, 320, 400));
            AssertLiveMotionBinding(FindElement(flyoutSection, "Motion.FlyoutProviderSpinner"));

            var widgetCard = new WidgetProviderCard();
            widgetCard.Measure(new Size(320, 400));
            widgetCard.Arrange(new Rect(0, 0, 320, 400));
            AssertLiveMotionBinding(FindElement(widgetCard, "Motion.WidgetProviderSpinner"));
        });
    }

    [Fact]
    public void CompanionSwitchesToItsStaticPoseWhenWindowsReducesMotionLive()
    {
        RunSta(() =>
        {
            var animationsEnabled = true;
            var settings = new SystemMotionSettings(
                () => animationsEnabled,
                Dispatcher.CurrentDispatcher);
            var companion = new CompanionControl(settings)
            {
                Width = 78,
                Height = 78,
                AvatarSize = 78,
                AnimationMode = MimoAnimationMode.Lively,
                ReducedMotion = false,
                Companion = CompanionKind.Mimo,
                Mood = PetMood.Refreshed,
            };
            companion.Measure(new Size(78, 78));
            companion.Arrange(new Rect(0, 0, 78, 78));
            companion.RaiseEvent(new RoutedEventArgs(FrameworkElement.LoadedEvent));

            Assert.False(companion.EffectiveReducedMotionForDiagnostics);
            animationsEnabled = false;
            settings.ProcessSystemParametersChange(nameof(SystemParameters.ClientAreaAnimation));

            Assert.True(companion.EffectiveReducedMotionForDiagnostics);
            var rightArm = FindElement(companion, "Companion.Mimo.ArmGroup.Right");
            Assert.Equal(-132, Assert.IsType<RotateTransform>(rightArm.RenderTransform).Angle, 3);

            animationsEnabled = true;
            settings.ProcessSystemParametersChange(nameof(SystemParameters.ClientAreaAnimation));
            Assert.False(companion.EffectiveReducedMotionForDiagnostics);

            companion.ReducedMotion = true;
            Assert.True(companion.EffectiveReducedMotionForDiagnostics);
            companion.RaiseEvent(new RoutedEventArgs(FrameworkElement.UnloadedEvent));
        });
    }

    [Fact]
    public void LiveReduceMotionImmediatelyFinishesAnActivePagedWidgetTransition()
    {
        RunSta(() =>
        {
            var animationsEnabled = true;
            var settings = new SystemMotionSettings(
                () => animationsEnabled,
                Dispatcher.CurrentDispatcher);
            var widget = new WidgetView(settings);
            widget.Measure(new Size(320, 420));
            widget.Arrange(new Rect(0, 0, 320, 420));
            widget.RaiseEvent(new RoutedEventArgs(FrameworkElement.LoadedEvent));

            var pagedCard = FindElement(widget, "Motion.PagedCard");
            pagedCard.RenderTransform = new TranslateTransform(8, 0);
            pagedCard.Opacity = 0.45;

            animationsEnabled = false;
            settings.ProcessSystemParametersChange(nameof(SystemParameters.ClientAreaAnimation));

            Assert.Equal(0, Assert.IsType<TranslateTransform>(pagedCard.RenderTransform).X);
            Assert.Equal(1, pagedCard.Opacity);
            widget.RaiseEvent(new RoutedEventArgs(FrameworkElement.UnloadedEvent));
        });
    }

    private static void AssertLiveMotionBinding(FrameworkElement element)
    {
        var trigger = element.Style.Triggers
            .OfType<MultiDataTrigger>()
            .Single();
        var binding = trigger.Conditions
            .Cast<System.Windows.Condition>()
            .Select(condition => condition.Binding)
            .OfType<Binding>()
            .Single(candidate => candidate.Path?.Path == nameof(SystemMotionSettings.AnimationsEnabled));

        Assert.Same(SystemMotionSettings.Current, binding.Source);
    }

    private static FrameworkElement FindElement(DependencyObject root, string automationId) =>
        Assert.IsAssignableFrom<FrameworkElement>(Descendants(root).FirstOrDefault(
            element => AutomationProperties.GetAutomationId(element) == automationId));

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        yield return root;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            foreach (var descendant in Descendants(VisualTreeHelper.GetChild(root, index)))
            {
                yield return descendant;
            }
        }
    }

    private static void RunSta(Action action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                action();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null)
        {
            throw failure;
        }
    }
}
