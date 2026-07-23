using System.Globalization;
using System.Windows;
using ClaudeUsage.Windows.ViewModels;
using DataBinding = System.Windows.Data.Binding;
using IValueConverter = System.Windows.Data.IValueConverter;

namespace ClaudeUsage.Windows.Views;

public sealed class WidgetBooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var visible = value is true;
        if (string.Equals(parameter as string, "Invert", StringComparison.OrdinalIgnoreCase))
        {
            visible = !visible;
        }

        return visible ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        DataBinding.DoNothing;
}

public sealed class WidgetPanelKindVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not WidgetPanelKind current
            || parameter is not string requestedText
            || !Enum.TryParse<WidgetPanelKind>(requestedText, ignoreCase: true, out var requested))
        {
            return Visibility.Collapsed;
        }

        return current == requested ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        DataBinding.DoNothing;
}
