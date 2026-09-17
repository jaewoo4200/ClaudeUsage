using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Controls;

namespace ClaudeUsage.Windows.Tests;

public sealed class CompanionCharacterParityTests
{
    [Fact]
    public void AllNineCharactersExposeTheirMacDefiningDetails()
    {
        RunSta(() =>
        {
            var cases = new[]
            {
                new CharacterCase(CompanionKind.Mimo, PetMood.Calm, ["Companion.Mimo.Body"]),
                new CharacterCase(CompanionKind.Lumi, PetMood.Calm, ["Companion.Lumi.Base"]),
                new CharacterCase(CompanionKind.Kumo, PetMood.Refreshed,
                    ["Companion.Kumo.Sun", "Companion.Kumo.WeatherSparkle"]),
                new CharacterCase(CompanionKind.Dot, PetMood.Calm,
                    ["Companion.Dot.Pixel.TopLeft", "Companion.Dot.Pixel.Right", "Companion.Dot.Pixel.BottomLeft"]),
                new CharacterCase(CompanionKind.Navi, PetMood.Calm,
                    ["Companion.Navi.Provider.C", "Companion.Navi.Provider.G",
                     "Companion.Navi.SolarPanel.Left.Line.0", "Companion.Navi.SolarPanel.Left.Line.1",
                     "Companion.Navi.SolarPanel.Left.Line.2", "Companion.Navi.SolarPanel.Right.Line.0",
                     "Companion.Navi.SolarPanel.Right.Line.1", "Companion.Navi.SolarPanel.Right.Line.2"]),
                new CharacterCase(CompanionKind.Bori, PetMood.Focused,
                    ["Companion.Bori.TailTip", "Companion.Bori.EarInner.Left",
                     "Companion.Bori.EarInner.Right", "Companion.Bori.LaptopStatus"]),
                new CharacterCase(CompanionKind.Muru, PetMood.Calm, ["Companion.Muru.CapSpot.Center"]),
                new CharacterCase(CompanionKind.Tori, PetMood.Sleepy,
                    ["Companion.Tori.Perch.0", "Companion.Tori.Perch.1", "Companion.Tori.Perch.2"]),
                new CharacterCase(CompanionKind.Pico, PetMood.Calm,
                    ["Companion.Pico.EarInner.Left", "Companion.Pico.EarInner.Right"]),
            };

            foreach (var item in cases)
            {
                var control = CreateCharacter(item.Kind, item.Mood);
                var ids = Descendants(control)
                    .Select(AutomationProperties.GetAutomationId)
                    .Where(id => !string.IsNullOrWhiteSpace(id))
                    .ToHashSet(StringComparer.Ordinal);
                foreach (var expected in item.ExpectedIds)
                {
                    Assert.Contains(expected, ids);
                }
            }
        });
    }

    [Fact]
    public void KumoDotAndNaviUseTheSourceGeometryForMissingDetails()
    {
        RunSta(() =>
        {
            var kumo = CreateCharacter(CompanionKind.Kumo, PetMood.Refreshed);
            var sun = Assert.IsType<Ellipse>(FindByAutomationId(kumo, "Companion.Kumo.Sun"));
            var sparkle = Assert.IsType<TextBlock>(FindByAutomationId(kumo, "Companion.Kumo.WeatherSparkle"));
            Assert.Equal(20, sun.Width);
            Assert.Equal(20, sun.Height);
            Assert.Equal("✦", sparkle.Text);

            var dot = CreateCharacter(CompanionKind.Dot, PetMood.Calm);
            var thirdPixel = Assert.IsType<Rectangle>(FindByAutomationId(dot, "Companion.Dot.Pixel.BottomLeft"));
            Assert.Equal(7.5, thirdPixel.Width);
            Assert.Equal(7.5, thirdPixel.Height);

            var navi = CreateCharacter(CompanionKind.Navi, PetMood.Calm);
            var providerC = Assert.IsType<TextBlock>(FindByAutomationId(navi, "Companion.Navi.Provider.C"));
            var providerG = Assert.IsType<TextBlock>(FindByAutomationId(navi, "Companion.Navi.Provider.G"));
            Assert.Equal("C", providerC.Text);
            Assert.Equal("G", providerG.Text);
            for (var index = 0; index < 3; index++)
            {
                Assert.IsType<Line>(FindByAutomationId(navi, $"Companion.Navi.SolarPanel.Left.Line.{index}"));
                Assert.IsType<Line>(FindByAutomationId(navi, $"Companion.Navi.SolarPanel.Right.Line.{index}"));
            }

            var tiredPico = CreateCharacter(CompanionKind.Pico, PetMood.Tired);
            Assert.IsType<System.Windows.Shapes.Path>(
                FindByAutomationId(tiredPico, "Companion.StatusGlyph.Drop"));
        });
    }

    [Fact]
    public void StillAndReducedMotionUseTheMacTimeZeroAnglesAndAnchors()
    {
        RunSta(() =>
        {
            var mimo = CreateCharacter(CompanionKind.Mimo, PetMood.Refreshed);
            AssertRotation(FindElement(mimo, "Companion.Mimo.ArmGroup.Left"), 16, 0.23, 0.385);
            AssertRotation(FindElement(mimo, "Companion.Mimo.ArmGroup.Right"), -132, 0.77, 0.385);
            AssertRotation(FindElement(mimo, "Companion.Mimo.LegGroup.Left"), -4, 0.38, 0.665);
            AssertRotation(FindElement(mimo, "Companion.Mimo.LegGroup.Right"), 4, 0.62, 0.665);

            var lumi = CreateCharacter(CompanionKind.Lumi, PetMood.Tired);
            var shade = FindElement(lumi, "Companion.Lumi.ShadeGroup");
            AssertRotation(shade, 18, 0.5, 0.53);
            Assert.Equal(0.52, shade.Opacity, 3);

            var bori = CreateCharacter(CompanionKind.Bori, PetMood.Tired);
            AssertRotation(FindElement(bori, "Companion.Bori.HeadGroup"), 9, 0.5, 0.42);
            AssertRotation(FindElement(bori, "Companion.Bori.Tail"), -18, 0.5, 1);

            var muru = CreateCharacter(CompanionKind.Muru, PetMood.Sleepy);
            AssertRotation(FindElement(muru, "Companion.Muru.CapGroup"), 8, 0.5, 0.49);

            var tori = CreateCharacter(CompanionKind.Tori, PetMood.Sleepy);
            AssertRotation(FindElement(tori, "Companion.Tori.Wing.Left"), -8, 0.355, 0.54);
            AssertRotation(FindElement(tori, "Companion.Tori.Wing.Right"), 8, 0.645, 0.54);

            var pico = CreateCharacter(CompanionKind.Pico, PetMood.Tired);
            AssertRotation(FindElement(pico, "Companion.Pico.Ear.Left"), -18, 0.5, 0.5);
            AssertRotation(FindElement(pico, "Companion.Pico.Ear.Right"), 18, 0.5, 0.5);
            AssertRotation(FindElement(pico, "Companion.Pico.Tail"), 42, 0.5, 1);
        });
    }

    [Fact]
    public void CompositePartsStayInsideTheSameRotatingSourceGroup()
    {
        RunSta(() =>
        {
            var mimo = CreateCharacter(CompanionKind.Mimo, PetMood.Calm);
            AssertVisualDescendant(
                FindElement(mimo, "Companion.Mimo.ArmGroup.Left"),
                FindElement(mimo, "Companion.Mimo.Hand.Left"));
            AssertVisualDescendant(
                FindElement(mimo, "Companion.Mimo.LegGroup.Left"),
                FindElement(mimo, "Companion.Mimo.Foot.Left"));

            var lumi = CreateCharacter(CompanionKind.Lumi, PetMood.Sleepy);
            AssertVisualDescendant(
                FindElement(lumi, "Companion.Lumi.ShadeGroup"),
                FindElement(lumi, "Companion.Lumi.Screen"));

            var bori = CreateCharacter(CompanionKind.Bori, PetMood.Tired);
            AssertVisualDescendant(
                FindElement(bori, "Companion.Bori.HeadGroup"),
                FindElement(bori, "Companion.Bori.EarInner.Left"));
            AssertVisualDescendant(
                FindElement(bori, "Companion.Bori.HeadGroup"),
                FindElement(bori, "Companion.Bori.Head"));

            var muru = CreateCharacter(CompanionKind.Muru, PetMood.Tired);
            AssertVisualDescendant(
                FindElement(muru, "Companion.Muru.CapGroup"),
                FindElement(muru, "Companion.Muru.CapSpot.Center"));
        });
    }

    [Fact]
    public void CharacterGeometryMatchesTheSwiftUiHundredPointCanvas()
    {
        RunSta(() =>
        {
            var mimo = CreateCharacter(CompanionKind.Mimo, PetMood.Focused);
            var viewbox = Assert.Single(Descendants(mimo).OfType<Viewbox>());
            Assert.Equal(new Thickness(), viewbox.Margin);
            AssertGeometry(FindElement(mimo, "Companion.Mimo.Screen"), 28.5, 30.5, 43, 25);
            Assert.Equal(
                10,
                Descendants(mimo).Count(element =>
                    AutomationProperties.GetAutomationId(element).StartsWith("Companion.Mimo.Keyboard.Key.", StringComparison.Ordinal)));

            var lumi = CreateCharacter(CompanionKind.Lumi, PetMood.Focused);
            var beam = Assert.IsType<Polygon>(FindByAutomationId(lumi, "Companion.Lumi.Beam"));
            Assert.Equal(new Point(21, 31), beam.Points[0]);
            Assert.Equal(new Point(79, 31), beam.Points[1]);
            Assert.Equal(new Point(50, 89), beam.Points[2]);

            var kumo = CreateCharacter(CompanionKind.Kumo, PetMood.Calm);
            var cloud = FindElement(kumo, "Companion.Kumo.CloudGroup");
            var shadow = Assert.IsType<DropShadowEffect>(cloud.Effect);
            Assert.Equal(0.18, shadow.Opacity, 3);

            var bori = CreateCharacter(CompanionKind.Bori, PetMood.Calm);
            AssertGeometry(FindElement(bori, "Companion.Bori.Tail"), 68, 32, 18, 52);

            var tori = CreateCharacter(CompanionKind.Tori, PetMood.Calm);
            var beak = Assert.IsType<Polygon>(FindByAutomationId(tori, "Companion.Tori.Beak"));
            Assert.Equal(new Point(44.5, 52), beak.Points[0]);
            Assert.Equal(new Point(55.5, 52), beak.Points[1]);
            Assert.Equal(new Point(50, 62), beak.Points[2]);

            var pico = CreateCharacter(CompanionKind.Pico, PetMood.Calm);
            AssertGeometry(FindElement(pico, "Companion.Pico.Tail"), 74.5, 44, 9, 38);
            AssertGeometry(FindElement(pico, "Companion.Pico.Ear.Left"), 21, 10.5, 20, 25);
            AssertGeometry(FindElement(pico, "Companion.Pico.Ear.Right"), 59, 10.5, 20, 25);
            AssertGeometry(FindElement(pico, "Companion.Pico.BatteryTrack"), 39, 65.75, 22, 8.5);
        });
    }

    private static CompanionControl CreateCharacter(CompanionKind kind, PetMood mood)
    {
        var control = new CompanionControl
        {
            Width = 78,
            Height = 78,
            AvatarSize = 78,
            AnimationMode = MimoAnimationMode.Still,
            ReducedMotion = true,
            Companion = kind,
            Mood = mood,
        };
        control.Measure(new Size(78, 78));
        control.Arrange(new Rect(0, 0, 78, 78));
        return control;
    }

    private static DependencyObject? FindByAutomationId(DependencyObject root, string automationId) =>
        Descendants(root).FirstOrDefault(
            element => AutomationProperties.GetAutomationId(element) == automationId);

    private static FrameworkElement FindElement(DependencyObject root, string automationId) =>
        Assert.IsAssignableFrom<FrameworkElement>(FindByAutomationId(root, automationId));

    private static void AssertRotation(
        FrameworkElement element,
        double angle,
        double originX,
        double originY)
    {
        var transform = Assert.IsType<RotateTransform>(element.RenderTransform);
        Assert.Equal(angle, transform.Angle, 3);
        Assert.Equal(originX, element.RenderTransformOrigin.X, 3);
        Assert.Equal(originY, element.RenderTransformOrigin.Y, 3);
    }

    private static void AssertGeometry(
        FrameworkElement element,
        double left,
        double top,
        double width,
        double height)
    {
        Assert.Equal(left, Canvas.GetLeft(element), 3);
        Assert.Equal(top, Canvas.GetTop(element), 3);
        Assert.Equal(width, element.Width, 3);
        Assert.Equal(height, element.Height, 3);
    }

    private static void AssertVisualDescendant(DependencyObject ancestor, DependencyObject expected) =>
        Assert.Contains(expected, Descendants(ancestor));

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

    private sealed record CharacterCase(
        CompanionKind Kind,
        PetMood Mood,
        IReadOnlyList<string> ExpectedIds);
}
