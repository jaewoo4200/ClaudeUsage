# macOS 1.7.0 screenshots

The release screenshots were refreshed on 2026-10-20 using the final 1.7.0
SwiftUI views in `ReleaseScreenshotTests`. NSHostingView renders with demo
data at 2x, without opening an account session or a live desktop window.
Off-screen rendering can differ from live compositing for glow effects.

All account and usage values are synthetic (Claude 38% / 18% / 24%, Codex
42% / 28%, weekly breakdown 72 / 20 / 6 / 2). No live account fetch,
credentials, conversation content, or project names are included. Reset
countdowns reflect the capture time.

- `theme-*-ko.png`: classic and new theme samples; `themes-ko.png` compares
  Donut, Halo Bar, and Aura. Filenames now match the final separate theme IDs.
- `dropdown-*`, `widget-*`: menu bar dropdown and widget layouts
- `breakdown-ko.png`: the weekly breakdown component
- `settings-services-ko.png`: independent Claude and Codex visibility controls
- `settings-layout-ko.png`: widget layout and breakdown-pin settings
- `settings-notifications-*.png`: permission/test controls with a fake
  notification client; no OS permission prompt is triggered by the renderer
- `history-dashboard-ko.png`: retained demo history image from PR #2

Widget samples have breakdown pinning enabled and use the built-in Mimo,
never a personal or third-party Codex pet. Notification controls illustrate
opt-in features, not default enabled preferences.

Existing screenshots of unchanged screens (companion lineup, menu bar label,
provider icons) remain in their original asset directories.
