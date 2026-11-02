# Widget Interaction and Resource Notes

Measurements and preview checks: 2026-10-21, based on 1.7.1 source (`3210fe3`).
These changes are included in [1.7.2](releases/v1.7.2.md), dated 2026-11-02.
The measurements below are historical preview results, not new 1.7.2 benchmarks.

## Changes

- Hidden panels now release their SwiftUI hosting trees. Previously `orderOut`
  hid the window but retained countdown timelines and other view work.
  Account polling and usage-history collection remain enabled.
- Every widget layout has a top-right hide button. Separate Claude/Codex windows
  hide independently; hiding a window does not disable its provider. The menu-bar
  widget toggle can hide the remaining windows and show the configured set again.
- Window movement now uses AppKit `performDrag(with:)` with the original mouse-down
  event instead of repeatedly setting the frame from SwiftUI mouse coordinates.
  SwiftUI still distinguishes a drag from a button click.
- Hover changes and content resizing are deferred while the pointer is held.
  Only the latest requested size is applied after release, anchored to the new
  location. Hosting-view minimum/maximum constraints no longer compete with the
  panel's size management. Dragged positions are saved after release.
- Legacy text countdowns stop ticking without a reset date or after expiry.
  Weekly text ticks at minute boundaries, switching to seconds in its last hour.
  Gauge lists keep one shared second tick per list: a per-row experiment increased
  static UI cost and was not retained.

The old combination of manual frame movement, hover-driven layout, and hosting
constraints allowed multiple paths to change the same frame. These are concrete
sources of movement instability, but not a quantified before/after jitter test.

## Short CPU Comparison

One local run per version, Debug/arm64, same Mac, demo account data, horizontal
Daangn widget, Mimo in the focused state. Each phase settles for one second and
measures process CPU time for 12 seconds. Account synchronization and local token
scans are disabled. Percentages use 100% for one CPU core.

| UI state | Before | After |
| --- | ---: | ---: |
| Visible, automatic animation | 16.640% | 14.409% |
| Visible, still animation | 2.918% | 2.882% |
| Hidden | 3.126% | 0.011% |

The strongest finding is elimination of retained hidden-widget work. The small
visible differences are not enough to establish a general performance gain.
These are **not installed Release-app or battery-life measurements**. They do not
include networking, login WebViews, or token parsing, and do not include separate
WindowServer GPU work.

Process peak RSS was 122.9 MiB before and 125.9 MiB after. This cumulative peak is
not current resident memory and does not demonstrate a memory reduction.

## Further Improvements

1. An optional energy mode can reduce animation frequency on battery or in Low
   Power Mode. Keep the existing Still setting as the lowest-cost visible mode.
2. Suspend pet animation for genuinely occluded windows or display sleep. Check
   multiple monitors, Spaces and always-on-top behavior before using occlusion
   alone as a visibility signal.
3. Profile animation interpolation in a Release build before changing sprite or
   vector rendering. The automatic/still gap is larger than countdown overhead.
4. Profile local token scanning with a large real log archive before adding an
   incremental file-offset index. Preserve rotation, truncation and deduplication.

Provider polling remains every 60 seconds; local token scans are throttled to
five minutes. History samples are normally five minutes apart (resets may add a
sample), retained for 14 days. No freshness reduction or new telemetry was added.

## Reproduction and Checks

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  TEST_RUNNER_CLAUDE_USAGE_PROFILE=1 \
  xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage \
  -configuration Debug -derivedDataPath build/WidgetInteractionTests \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  -only-testing:ClaudeUsageTests/WidgetResourceTests \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test
```

The resource probe is skipped by default. Its `[WidgetProfile]` output is in the
test result's exported diagnostics. It temporarily uses demo settings and restores
them afterward. Add `TEST_RUNNER_CLAUDE_USAGE_PREVIEW_SECONDS=120` for an interactive
demo window instead of CPU measurements. Do not interact with a timed CPU sample.

Interaction tests cover the original drag event, deferred resizing/hover, missing
events, countdown boundaries, and hide buttons across all six themes and four
layouts. Render tests cover Korean/English widget views. A preview run confirmed
native frame movement and drag-state cleanup after release; automated synthetic
drags did not reliably supply the global mouse-button state. Human smoothness and
cross-display testing remain useful before publishing.

Preview checks: 125 tests passed, zero failed, and three opt-in tests skipped (live
Codex account, selected local Codex pet, and the separately executed resource
probe). The universal Release build contains both `arm64` and `x86_64`; its local
ad-hoc bundle signature passes strict verification. It is not Developer-ID signed
or notarized. That build was an unreleased 1.7.1-source candidate; see the 1.7.2
release notes for current package verification.

Local candidate: `build/WidgetEfficiencyRelease/Build/Products/Release/ClaudeUsage.app`.

## Preview 2: Hide Control and Small Icons

The circular close control is now a borderless minus symbol with a stable 22-point
hit area. Only hovering shows the subtle background; the tooltip and accessibility
label still say "Hide this widget". It does not minimize or quit the app.

The supplied ICNS contained PNG payloads in `icp4`/`icp5` slots. ImageIO could read
those payloads, but the system icon decoder used by `iconutil` produced noise for
the 16px and 32px standard-resolution icons. This explains a correct large preview
alongside a corrupt small list icon. It was not just an old Finder cache.

The small slots were regenerated from the existing 1024px artwork and the iconset
was repackaged with Apple's `iconutil`. The exported 1024px PNG is byte-identical
before/after; the friend's logo design is unchanged. New tests check all ten size
and scale combinations and compare small images after a system-decoder round trip.
The round-trip regression failed on the previous resource and passes on the fix.
For future icon changes, use `scripts/build-icon.sh` and run `AppIconTests` rather
than hand-packing PNG chunks into an ICNS.

The CPU figures above were measured before this cosmetic follow-up, not remeasured
for preview 2. No additional timers or animations were added for the hide control.

Preview 2 installer: `build/ClaudeUsage-1.7.1-widget-fix-preview2.dmg`.

## Preview 3: Settings Logo and System Icon Cache

The settings header still used a separate theme-drawn C rather than the real app
icon. It now loads the bundled `AppIcon.icns` once and displays that unchanged in
every theme. A regression test compares its artwork with the bundled resource.

The installed preview-2 ICNS matched the fixed resource, but `NSWorkspace` still
returned the old noisy 16px/32px images. The app bundle itself retained a 16:14
modification time while its new icon was from 17:18. Re-registering this app alone
did not refresh the image. Updating only the bundle modification time and
re-registering it made fresh system-icon queries return the correct logo.

DMG staging now updates the app bundle date after signing, so repeated builds of
the same version do not preserve that stale date. Strict signature verification
still passes. No credentials, Keychain items, access-control permissions, global
icon caches, or system processes were changed. A new Keychain prompt was not
forced merely to recheck its artwork.

Preview 3 installer: `build/ClaudeUsage-1.7.1-widget-fix-preview3.dmg`.

References: Apple's [native window dragging](https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:))
and [hosting-view sizing options](https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions).
Icon packaging follows Apple's [high-resolution icon guidance](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html).
