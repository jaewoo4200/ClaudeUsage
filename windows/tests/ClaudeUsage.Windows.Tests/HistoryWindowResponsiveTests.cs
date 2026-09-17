using System.IO;
using System.Windows;
using System.Windows.Controls;
using ClaudeUsage.Core.History;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using ClaudeUsage.Windows.Views;
using Line = System.Windows.Shapes.Line;

namespace ClaudeUsage.Windows.Tests;

public sealed class HistoryWindowResponsiveTests
{
    [Fact]
    public void HistoryWindowDeclaresMacPreferredClientSizeAndScrollableBody()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            var historyPath = Path.Combine(
                Path.GetTempPath(),
                $"claudeusage-history-window-{Guid.NewGuid():N}.json");
            try
            {
                var settings = new AppSettings
                {
                    Appearance = AppearanceMode.Light,
                    Language = AppLanguage.English,
                };
                var history = new UsageHistoryService(new UsageHistoryStore(historyPath));
                using var viewModel = new UsageHistoryDashboardViewModel(history, settings);
                var window = new UsageHistoryDashboardWindow(viewModel);
                var surface = Assert.IsType<System.Windows.Controls.Grid>(window.FindName("HistorySurface"));
                var bodyScroll = Assert.IsType<ScrollViewer>(window.FindName("HistoryBodyScroll"));
                var controls = Assert.IsType<Grid>(window.FindName("HistoryControlsGrid"));
                var rangePicker = Assert.IsType<ListBox>(window.FindName("HistoryRangePicker"));
                var scopePicker = Assert.IsType<ListBox>(window.FindName("HistoryScopePicker"));
                var historyXAxis = Assert.IsType<Line>(window.FindName("HistoryXAxis"));

                Assert.Equal(760, surface.Width);
                Assert.Equal(560, surface.Height);
                Assert.Equal(760, WindowWorkAreaSizingBehavior.GetPreferredClientWidth(window));
                Assert.Equal(560, WindowWorkAreaSizingBehavior.GetPreferredClientHeight(window));
                Assert.Equal(640, WindowWorkAreaSizingBehavior.GetMinimumClientWidth(window));
                Assert.Equal(480, WindowWorkAreaSizingBehavior.GetMinimumClientHeight(window));
                Assert.True(WindowWorkAreaSizingBehavior.GetIsEnabled(window));
                Assert.Equal(ResizeMode.CanResize, window.ResizeMode);
                Assert.Equal(ScrollBarVisibility.Auto, bodyScroll.VerticalScrollBarVisibility);
                Assert.Equal(ScrollBarVisibility.Auto, bodyScroll.HorizontalScrollBarVisibility);

                Assert.Equal(3, controls.ColumnDefinitions.Count);
                Assert.True(controls.ColumnDefinitions[0].Width.IsStar);
                Assert.Equal(3, controls.ColumnDefinitions[0].Width.Value);
                Assert.Equal(326, controls.ColumnDefinitions[0].MinWidth);
                Assert.Equal(360, controls.ColumnDefinitions[0].MaxWidth);
                Assert.True(controls.ColumnDefinitions[1].Width.IsStar);
                Assert.Equal(1, controls.ColumnDefinitions[1].Width.Value);
                Assert.Equal(40, controls.ColumnDefinitions[1].MinWidth);
                Assert.True(controls.ColumnDefinitions[2].Width.IsAbsolute);
                Assert.Equal(230, controls.ColumnDefinitions[2].Width.Value);

                Assert.Equal(326, rangePicker.MinWidth);
                Assert.Equal(360, rangePicker.MaxWidth);
                Assert.Equal(HorizontalAlignment.Stretch, rangePicker.HorizontalAlignment);
                Assert.Equal(230, scopePicker.MinWidth);
                Assert.Equal(230, scopePicker.MaxWidth);
                Assert.Equal(HorizontalAlignment.Stretch, scopePicker.HorizontalAlignment);

                controls.Measure(new Size(596, 24));
                controls.Arrange(new Rect(0, 0, 596, 24));
                Assert.Equal(326, controls.ColumnDefinitions[0].ActualWidth, precision: 3);
                Assert.Equal(40, controls.ColumnDefinitions[1].ActualWidth, precision: 3);
                Assert.Equal(230, controls.ColumnDefinitions[2].ActualWidth, precision: 3);

                controls.Measure(new Size(716, 24));
                controls.Arrange(new Rect(0, 0, 716, 24));
                Assert.Equal(360, controls.ColumnDefinitions[0].ActualWidth, precision: 3);
                Assert.Equal(126, controls.ColumnDefinitions[1].ActualWidth, precision: 3);
                Assert.Equal(230, controls.ColumnDefinitions[2].ActualWidth, precision: 3);

                Assert.Equal(1, historyXAxis.X1);
                Assert.Equal(19, historyXAxis.Y1);
                Assert.Equal(19, historyXAxis.X2);
                Assert.Equal(19, historyXAxis.Y2);
                Assert.Equal(1.5, historyXAxis.StrokeThickness);
                window.Close();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
            finally
            {
                if (File.Exists(historyPath))
                {
                    File.Delete(historyPath);
                }
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
