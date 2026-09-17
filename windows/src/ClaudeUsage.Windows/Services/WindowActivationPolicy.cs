using System.Windows;

namespace ClaudeUsage.Windows.Services;

internal static class WindowActivationPolicy
{
    internal static WindowState ResolveRestoredState(WindowState currentState) =>
        currentState == WindowState.Minimized
            ? WindowState.Normal
            : currentState;

    internal static void RestoreAndActivate(Window window)
    {
        ArgumentNullException.ThrowIfNull(window);
        window.WindowState = ResolveRestoredState(window.WindowState);
        window.Activate();
    }
}
