using System.Globalization;
using System.Windows;
using System.Windows.Data;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.ViewModels;
using Binding = System.Windows.Data.Binding;

namespace ClaudeUsage.Windows.Controls;

/// <summary>
/// Small presentation-only converters shared by the flyout templates. They use
/// the active string dictionary so a language switch updates after the template
/// is recreated by ThemeResourceManager.
/// </summary>
public sealed class FlyoutUsageCommentConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not WidgetMetricViewModel metric)
        {
            return string.Empty;
        }

        var theme = parameter as string;
        var percent = metric.ClampedPercent;
        if (string.Equals(theme, "Hybrid", StringComparison.OrdinalIgnoreCase))
        {
            return percent switch
            {
                < 30 => Text("충분히 여유", "Plenty left"),
                < 70 => Text("적당한 페이스", "Good pace"),
                < 90 => Text("속도 조절", "Slow down"),
                _ => Text("한도 임박", "Near limit"),
            };
        }

        var weekly = IsWeekly(metric);
        return percent switch
        {
            < 30 => Text("아직 여유로워요 🙂", "Plenty of room 🙂"),
            < 70 => Text("적당히 쓰는 중이에요 😊", "Pacing well 😊"),
            < 90 when weekly => Text("조금만 아껴 써요 😯", "Slow down a bit 😯"),
            < 90 => Text("속도 조절이 필요해요 ⚡", "Take it easy ⚡"),
            _ when weekly => Text("이번 주 거의 다 썼어요 🥲", "Almost out this week 🥲"),
            _ => Text("이번 윈도우 거의 다 썼어요 🚨", "Window nearly out 🚨"),
        };
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        Binding.DoNothing;

    internal static bool IsWeekly(WidgetMetricViewModel metric) =>
        metric.Id.Contains("week", StringComparison.OrdinalIgnoreCase)
        || metric.WindowLabel.Contains("week", StringComparison.OrdinalIgnoreCase)
        || metric.WindowLabel.Contains("주간", StringComparison.OrdinalIgnoreCase)
        || metric.WindowLabel.Contains("7일", StringComparison.OrdinalIgnoreCase);

    private static string Text(string korean, string english) =>
        ThemeResourceManager.GetString("UI.Settings", "Settings") == "설정" ? korean : english;
}

public sealed class FlyoutWindowTagConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is WidgetMetricViewModel metric && FlyoutUsageCommentConverter.IsWeekly(metric)
            ? "LONG"
            : "SHORT";

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        Binding.DoNothing;
}

public sealed class FlyoutMoodTitleConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object? parameter, CultureInfo culture) =>
        values.FirstOrDefault() is PetMood mood
            ? ThemeResourceManager.GetString($"Companion.Mood.{mood}", mood.ToString())
            : string.Empty;

    public object[] ConvertBack(object? value, Type[] targetTypes, object? parameter, CultureInfo culture) =>
        targetTypes.Select(_ => Binding.DoNothing).ToArray();
}

public sealed class FlyoutCompanionDetailConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object? parameter, CultureInfo culture)
    {
        var recentTokens = Value(values, 0);
        var pace = Value(values, 1);
        var pressure = Value(values, 2);
        var korean = ThemeResourceManager.GetString("UI.Settings", "Settings") == "설정";
        if (recentTokens is not null)
        {
            return korean ? $"최근 {recentTokens}" : $"Recent {recentTokens}";
        }

        if (pace is not null)
        {
            return korean ? $"최근 {pace}" : $"Recent {pace}";
        }

        if (pressure is not null)
        {
            return korean ? $"현재 부담 {pressure}" : $"Current pressure {pressure}";
        }

        return korean ? "사용량을 기다리는 중" : "Waiting for usage";
    }

    public object[] ConvertBack(object? value, Type[] targetTypes, object? parameter, CultureInfo culture) =>
        targetTypes.Select(_ => Binding.DoNothing).ToArray();

    private static string? Value(IReadOnlyList<object> values, int index) =>
        index < values.Count
        && values[index] is string text
        && !string.IsNullOrWhiteSpace(text)
        && text != "-"
            ? text
            : null;
}

public sealed class InverseBooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        Binding.DoNothing;
}
