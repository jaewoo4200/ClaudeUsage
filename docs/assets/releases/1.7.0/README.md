# macOS 1.7.0 screenshots

These PNGs were captured from the app's own SwiftUI views, shown in real
windows with synthetic demo data and captured at 2x. Capturing the window
(instead of drawing the view off-screen) keeps the glow of the Halo Bar and
Aura themes.

All account and usage values are synthetic (Claude 38% / 71% / 24%, Codex
42% / 28%, weekly breakdown 72 / 20 / 6 / 2). No live account fetch,
credentials, conversation content, or project names are included. Reset
countdowns reflect the capture time.

- `theme-*-ko.png`, `themes-ko.png`: the Claude section in each gauge theme
  (Donut, Halo Bar, Aura)
- `dropdown-*`, `widget-*`: menu bar dropdown and widget layouts
- `breakdown-ko.png`: the 7-day row with the weekly breakdown expanded
- `settings-services-ko.png`: Settings > Services with Codex turned off
- `settings-layout-ko.png`: widget layout settings. Drawn off-screen so the
  system toggles show their active colors; it has no glow effects.
- `history-dashboard-ko.png`: the usage history window with the same synthetic
  records as `WidgetLayoutTests`, redrawn for the 1.7.0 accent color.

Existing screenshots of unchanged screens (companion lineup, menu bar label,
provider icons) remain in their original asset directories.
