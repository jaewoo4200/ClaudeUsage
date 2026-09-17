# Windows design and release acceptance

This document is the acceptance contract for the Windows port. A green build or
feature-equivalent screen is not enough: the app must preserve the macOS product's
visual hierarchy, density, interaction, and motion within the explicit Windows
exceptions below.

## Sources of truth

Implementation details come from the current SwiftUI sources, in particular:

- `Sources/ClaudeUsage/Views/DesignSystem.swift`
- `Sources/ClaudeUsage/Views/Components.swift`
- `Sources/ClaudeUsage/Views/UsageCards.swift`
- `Sources/ClaudeUsage/Views/MenuBarContentView.swift`
- `Sources/ClaudeUsage/Views/WidgetView.swift`
- `Sources/ClaudeUsage/Views/UsagePetView.swift`
- `Sources/ClaudeUsage/Views/CompanionCharacters.swift`
- `Sources/ClaudeUsage/Views/SettingsView.swift`
- `Sources/ClaudeUsage/Views/UsageHistoryDashboardView.swift`

The current 2x visual references are:

- `docs/assets/menu-dropdown.png` (360 logical pixels wide)
- `docs/assets/widget-horizontal.png` (480 logical pixels wide)
- `docs/assets/widget-paged.png` (240 logical pixels wide)
- `docs/assets/settings-layout.png` and `settings-mimo.png` (420 logical pixels wide)
- `docs/assets/history-dashboard.png` (760 x 560 logical pixels)
- `docs/assets/companion-lineup.png`
- `docs/assets/provider-icons.png`

The older `docs/screenshots/dropdown-*.png` and `widget-*.png` files predate the
combined Claude/Codex UI and are not complete acceptance references.

## Allowed Windows differences

Only platform-owned surfaces may differ:

- Windows notification-area icons cannot reproduce the variable-width macOS menu
  bar label. The tray icon and tooltip are the Windows equivalent.
- Segoe UI Variable is used in place of Apple's system font. Font sizes, weights,
  line heights, and control widths must be optically adjusted to preserve the same
  hierarchy and density.
- Native window chrome, shadows, focus indication, and accessibility affordances
  may follow Windows conventions where the macOS surface is platform-owned.

WPF itself is not an exception for changing the app's component tree, card grammar,
spacing, colors, provider icons, companion proportions, or information hierarchy.

## Visual acceptance

### Notification flyout

- 360 logical pixels wide, including the equivalent of the macOS outer padding.
- Content order: optional compact companion summary, Claude provider section,
  divider, Codex provider section, divider, compact footer.
- No additional product header, pin/close header, provider container cards, or text
  action strip that is absent from `MenuBarContentView.swift`.
- Provider icons are 36 logical pixels and use installed Claude/Codex/ChatGPT icons
  when available, with a polished bundled fallback.
- Footer uses compact icon actions for history, settings, refresh, logout, and quit.
- Daangn, Toss, and Hybrid render different usage-card grammars, not just different
  accent colors.

### Floating widgets

- Stacked, paged, and separate-provider widgets are 240 logical pixels wide;
  horizontal is 480 logical pixels wide.
- Height fits content. No fixed 400-pixel page and no whole-widget scroll viewer.
- Daangn uses ring metrics, Toss uses large values and 5-pixel bars, and Hybrid
  uses the compact title/countdown/value hierarchy with 7-pixel gradient bars on
  the gradient outer surface from `WidgetView.swift`. SHORT/LONG labels, comments,
  and individual outlined cards belong to the flyout, not the widget.
- The complete background is draggable. Positions persist independently and clamp
  to the active monitor after move, restart, display removal, or DPI change.
- Topmost, paged navigation, separate-provider visibility, keyboard access, and
  reduced-motion behavior work at runtime.

### Companions

- Menu summary uses a 58-pixel ring avatar; compact widgets use 66 pixels; the
  horizontal widget uses 78 pixels.
- The avatar is paired with name, state badge, message, detail, and optional mini
  sparkline as in `UsagePetView.swift`; it is not a 180 x 210 speech-bubble panel.
- All nine companions retain their character-specific geometry, palette, state
  details, and idle/focused/tired/reset presentation.
- Animation changes fixed subparts without changing quota-card geometry. Automatic,
  lively, still, system reduced-motion, and hidden-window suspension are verified.

### Settings

- The content surface is 420 x 600 logical pixels and keeps the compact SwiftUI
  information architecture.
- Theme selection uses three visual preview tiles and an explicit selected state.
- Layout, appearance, language, sensitivity, and animation use custom segmented
  controls. Boolean settings use switch-style controls rather than default WPF
  check boxes.
- Companion selection is a three-column grid with recognizable live/static 30-pixel
  previews for all nine characters.
- Account rows use provider icons, plan/status, and compact actions.
- All settings update the flyout and visible widgets live without resizing unrelated
  content.

### Usage history

- A separate 760 x 560 window (minimum 640 x 480) is available from the flyout and
  settings.
- It supports 1 hour, 24 hours, 7 days, and 14 days plus All, Claude, and Codex
  filters; four summary values; a 0-100 percent time-series chart; legend; empty
  state; and clear-history action.

### Themes and localization

- Exact semantic colors and corner radii come from `DesignSystem.swift` for light
  and dark Daangn, Toss, and Hybrid.
- Korean and English longest strings fit without clipping or changing the fixed
  widget widths.
- 0%, 9%, 99%, and 100%; long model names; and day/hour/minute reset strings have
  visual baselines.

## Interaction and motion acceptance

- Every floating window can be moved with pointer drag from its background.
- Windows remain recoverable after monitor topology and DPI changes.
- Flyout placement works with top, bottom, left, right, and auto-hidden taskbars.
- Animation stops when its widget is hidden and honors Windows reduced-motion.
- Refresh, login/logout, theme/language change, page navigation, history opening,
  and app quit are keyboard and screen-reader operable.

## Release acceptance

The product is distributable only after all of the following evidence exists:

- Core, Windows, and UI/state tests pass with zero build warnings.
- Visual baselines pass for light/dark x three themes x Korean/English at 100%,
  125%, 150%, and 200% scaling for the required screens.
- A clean Windows 11 x64 machine can install, launch, log in, restart, update,
  uninstall, and remove/retain user data according to the documented choice.
- Startup registration, WebView2 bootstrap/failure guidance, offline recovery,
  sleep/wake, multiple monitors, and SmartScreen behavior are verified.
- Release artifacts are reproducible, contain no secrets or debug symbols, include
  checksums and licenses, and are signed with the release certificate. Public
  publication remains a separately authorized action.
