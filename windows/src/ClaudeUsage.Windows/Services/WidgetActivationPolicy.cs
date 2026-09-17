using ClaudeUsage.Windows.ViewModels;

namespace ClaudeUsage.Windows.Services;

internal enum WidgetActivationPolicy
{
    PreserveForeground,
    ActivatePrimaryWidget,
}

internal static class WidgetActivationPlanner
{
    public static WidgetPanelKind? ResolveActivationTarget(
        WidgetActivationPolicy policy,
        WidgetLayoutMode layout,
        bool separateClaudeEnabled,
        bool separateCodexEnabled)
    {
        if (policy == WidgetActivationPolicy.PreserveForeground)
        {
            return null;
        }

        if (layout != WidgetLayoutMode.Separate)
        {
            return WidgetPanelKind.Combined;
        }

        if (separateClaudeEnabled)
        {
            return WidgetPanelKind.Claude;
        }

        return separateCodexEnabled ? WidgetPanelKind.Codex : null;
    }
}
