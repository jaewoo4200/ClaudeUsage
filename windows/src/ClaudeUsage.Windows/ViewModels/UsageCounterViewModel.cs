using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media;

namespace ClaudeUsage.Windows.ViewModels;

public sealed class UsageCounterViewModel : INotifyPropertyChanged
{
    private string _resetText;

    public UsageCounterViewModel(
        string id,
        string title,
        string windowLabel,
        double usedPercent,
        DateTimeOffset? resetsAt,
        bool isWeekly,
        DateTimeOffset now,
        string resettingText)
    {
        Id = id;
        Title = title;
        WindowLabel = windowLabel;
        UsedPercent = usedPercent;
        ResetsAt = resetsAt;
        IsWeekly = isWeekly;
        _resetText = UsageCountdownFormatter.Format(resetsAt, now, isWeekly, resettingText);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Id { get; }

    public string Title { get; }

    public string WindowLabel { get; }

    public double UsedPercent { get; }

    public DateTimeOffset? ResetsAt { get; }

    public bool IsWeekly { get; }

    public string ResetText
    {
        get => _resetText;
        private set
        {
            if (_resetText == value)
            {
                return;
            }

            _resetText = value;
            OnPropertyChanged();
        }
    }

    public string PercentageText => $"{Math.Clamp(UsedPercent, 0, 100):0}%";

    public double ClampedPercent => Math.Clamp(UsedPercent, 0, 100);

    public System.Windows.Media.Brush ProgressBrush => UsedPercent switch
    {
        >= 90 => new SolidColorBrush(System.Windows.Media.Color.FromRgb(230, 84, 84)),
        >= 70 => new SolidColorBrush(System.Windows.Media.Color.FromRgb(242, 169, 59)),
        _ => new SolidColorBrush(System.Windows.Media.Color.FromRgb(255, 111, 61))
    };

    internal bool UpdateCountdown(DateTimeOffset now, string resettingText)
    {
        var text = UsageCountdownFormatter.Format(ResetsAt, now, IsWeekly, resettingText);
        if (text == ResetText)
        {
            return false;
        }

        ResetText = text;
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
