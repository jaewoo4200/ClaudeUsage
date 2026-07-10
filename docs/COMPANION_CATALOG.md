# Companion catalog

ClaudeUsage 1.5.0 includes nine original SwiftUI companions. The selected companion is stored in local `UserDefaults` under `companionKind`; changing it does not alter usage history or provider data.

## Shared signals

Every companion receives the same inputs:

- the highest visible Claude or Codex quota percentage
- the recent percentage-point pace when optional local history is enabled
- the resolved state: Waiting, Calm, Focused, Sleepy, Tired, or Refreshed
- the selected sensitivity and animation mode

The companion does not change the calculation. It changes only how the result is expressed.

## Characters

| Companion | Identity | Character-specific behavior |
|---|---|---|
| Mimo | Laptop robot | Moves eyes, arms, and legs; opens a correctly oriented laptop while Focused |
| Lumi | Desk-light robot | Tilts its lamp head, casts a work beam, and flickers when Tired |
| Kumo | Weather cloud | Shows lightning, drops, rain, sun, and clearing sparkles |
| Dot | Pixel creature | Moves detached pixels and changes the code bars on its terminal body |
| Navi | Exploration drone | Orbits Claude and Codex markers and fires its thruster while working hard |
| Bori | Fox researcher | Moves its tail, wears focus glasses, and opens a small laptop |
| Muru | Mushroom friend | Tilts its cap, opens a book, and grows fresh leaves after a reset |
| Tori | Digital bird | Changes wing speed and rests in a nest when Sleepy or Tired |
| Pico | Robot cat | Moves its ears and tail while a chest battery shows remaining quota |

## State language

| State | Common meaning | Typical visual treatment |
|---|---|---|
| Waiting | No usage source is available yet | Neutral eyes and minimal motion |
| Calm | Quota pressure and pace are low | Relaxed eyes and slow idle motion |
| Focused | Pressure or pace crossed the selected focus threshold | Work props, faster limbs, light, thrust, or wings |
| Sleepy | Usage is high | Half-closed eyes and a sleep marker |
| Tired | Usage is close to the selected limit | Warning color, exhausted face, rain, flicker, or low battery |
| Refreshed | A drop of at least 15 percentage points was detected below 60% | Check eyes, sparkles, sun, leaves, or energetic motion |

## Rendering and performance

- The outer quota ring stays fixed; only character parts, expressions, and props change pose.
- Auto mode updates target poses every 0.45 to 1.8 seconds depending on state.
- Smooth transitions last only 0.16 to 0.25 seconds.
- Lively mode uses 0.25-second target updates; Still has no continuous timeline.
- The floating-widget timeline pauses whenever the widget is hidden.
- The nine previews in Settings are rendered at a fixed time and do not create nine animation timelines.
- macOS Reduce Motion is always respected.

The catalog is implemented in `Sources/ClaudeUsage/Views/CompanionCharacters.swift`. Shared state resolution remains in `Models/UsageHistory.swift`, and selection persistence remains in `Services/AppSettings.swift`.
