# Mimo behavior and reset-credit advisor

Status: core mood, sensitivity, animation modes, local trends, and reset-credit readout implemented; nine selectable companions added in v1.5.0; advanced reset recommendations remain proposed

This document records the original Mimo behavior model. Starting with v1.5.0, Mimo is one of nine characters sharing the same state engine; see [COMPANION_CATALOG.md](COMPANION_CATALOG.md) for the complete character-specific behavior map.

## Product principles

- The outer quota ring, character center, and widget footprint never move.
- Only eyes, eyelids, mouth, arms, legs, and small in-frame effects animate.
- Reset credits are recommendation-only. The selected companion never consumes one automatically.
- Trend-only behavior runs only when local history is enabled.
- Important advice is deterministic and explainable from visible usage data.
- Animations pause when the widget is hidden and respect Reduce Motion.

## Available data

| Signal | Current source | Use |
|---|---|---|
| Claude and Codex 5-hour/weekly percentages | Provider usage snapshots | Pressure, remaining quota, reset timing |
| Provider-specific historical percentages | Opt-in five-minute history | Claude-vs-Codex pace and spike detection |
| Claude Code daily tokens | Local numeric usage fields | Supporting activity signal |
| Codex daily token buckets | `account/usage/read` | Supporting activity signal; may lag |
| Codex reset credits | `account/rateLimits/read.rateLimitResetCredits` | Count, status, earliest expiry, recommendation |

The rate-limit API uses `usedPercent`. User-facing recommendation rules use remaining percentage:

```text
remainingPercent = 100 - usedPercent
```

## Implemented pressure and sensitivity rules

Immediate pressure is the highest visible percentage across Claude and Codex 5-hour, weekly, and model-specific limits. It is not a sum or average. Hidden optional model counters are excluded.

| Sensitivity | Focused | Sleepy | Tired |
|---|---:|---:|---:|
| Early | 35% or 8%p/hour | 70% or 22%p/hour | 90% or 40%p/hour |
| Balanced | 50% or 14%p/hour | 75% or 28%p/hour | 90% or 45%p/hour |
| Relaxed | 60% or 18%p/hour | 82% or 34%p/hour | 94% or 52%p/hour |

Balanced is the default. A detected drop of at least 15 percentage points followed by pressure below 60% selects Refreshed for up to 30 minutes. Mimo opens its laptop while Focused; every other companion uses the character-specific prop documented in the companion catalog. Sleepy, Tired, and Refreshed use dedicated faces, poses, and action marks.

## Reset-credit data model

Read these fields when present and ignore unknown future fields:

- `availableCount`
- `credits[].id`
- `credits[].resetType`
- `credits[].status`
- `credits[].grantedAt`
- `credits[].expiresAt`
- `credits[].title`
- `credits[].description`

Only credits with `status == available` and a future `expiresAt` count as usable. Sort them by expiry and show the earliest expiry first.

## Default recommendation rules

These defaults are intentionally conservative because a full reset affects both the weekly and five-hour windows.

| Condition | Recommendation |
|---|---|
| No available credit | Do not mention a reset unless explaining that none remain |
| Weekly natural reset is within 6 hours | Wait for the natural reset |
| Weekly remaining is 10% or less and reset is more than 6 hours away | Strongly recommend a reset |
| Weekly remaining is 20% or less and reset is more than 12 hours away | Recommend a reset |
| Five-hour remaining is 5% or less, its reset is more than 2 hours away, and weekly remaining is 40% or less | Recommend a reset |
| Earliest credit expires within 24 hours and weekly remaining is 60% or less | Recommend using it before expiry |
| Earliest credit expires within 72 hours and weekly remaining is 30% or less | Recommend a reset soon |
| Weekly remaining is above 60% | Save the credit, even if expiry is approaching |

Example bubbles:

- `초기화권 3장, 가장 빠른 만료는 7월 18일이에요.`
- `주간 한도가 9% 남았어요. 초기화권을 쓰기 좋은 때예요.`
- `6시간 안에 자연 초기화돼요. 이번에는 기다리는 편이 좋아요.`
- `아직 주간 한도가 97% 남았어요. 초기화권은 아껴둘게요.`

## Speech-bubble behavior

- Reserve a fixed bubble area so appearing text never resizes or shifts the widget.
- Limit compact-widget bubbles to two lines and menu-dropdown bubbles to three lines.
- Routine messages appear for 5 seconds with a 10-minute cooldown.
- Recommendation and expiry messages stay until dismissed or the underlying state changes.
- Clicking Mimo cycles through the current advice, reset time, trend, and idle phrase.
- Priority order: expiry/recommendation, reset event, critical usage, rapid activity, idle phrase.
- Never cover a quota ring, provider name, navigation arrow, or settings control.

## Planned behavior catalogue

Mimo has a base mood plus one action. This prevents unrelated animations from competing.

| # | State or trigger | Fixed-frame action |
|---|---|---|
| 1 | Idle, no recent change | Eyes slowly look left and right |
| 2 | Idle variation | Double blink, then a small smile |
| 3 | Idle variation | One eye closes in a short wink |
| 4 | Idle for 10 minutes | Arms stretch outward while feet stay planted |
| 5 | Idle for 30 minutes | Eyes close, arms relax, small `z` fades in and out |
| 6 | Claude usage rises faster | Look left; orange-side hand types or points |
| 7 | Codex usage rises faster | Look right; blue-side hand types or points |
| 8 | Both providers rise in the same 10 minutes | Both hands alternate in a dual-typing pose |
| 9 | Provider pace reaches 6 percentage points/hour | Focused eyes and quick alternating hand taps |
| 10 | Provider pace reaches 12 percentage points/hour | Run in place: arms and legs cycle while body and ring stay fixed |
| 11 | Pace reaches 25 percentage points/hour for two samples | Flame eyes and faster in-place running for a short burst |
| 12 | Any single sample jumps by 8 points or more | Eyes widen, hands lift, then return to the prior mood |
| 13 | Five-hour remaining is 25% or less | One foot taps while Mimo checks the reset clock |
| 14 | Highest used percentage is 75-89% | Half-closed eyes, lowered arms, occasional yawn |
| 15 | Highest used percentage is 90% or more | Tired/X eyes, sweat drop, very slow arm movement |
| 16 | A quota drops by 15 points or more | Reset celebration: bright eyes, both hands up, short sparkle |
| 17 | Reset credits are available | Occasionally holds a small ticket showing the count |
| 18 | Earliest credit expires within 72 hours | Ticket shakes once; bubble states the expiry date |
| 19 | Reset recommendation rule matches | Points at the ticket and shows the exact remaining percentage |
| 20 | Low usage after a heavy period | Sits calmly, closes eyes once, then returns to a relaxed smile |

## State selection

Use this priority so a spike does not hide an expiry warning and idle behavior does not interrupt important advice:

1. Reset-credit expiry or recommendation
2. Quota reset celebration
3. Critical quota or very high pace
4. Provider-specific active behavior
5. Idle variation

Provider pace should be calculated independently from existing five-minute snapshots. Quota percentage deltas are the primary immediate signal; token totals are supporting evidence because Codex daily buckets can lag.

## Performance and accessibility

- Auto updates target poses every 1.4 seconds while Waiting or Calm, every 0.45 seconds while Focused or Refreshed, and every 1.8 seconds while Sleepy or Tired.
- Lively uses 0.25-second target-pose updates; Still has no continuous timeline.
- Auto transitions last 0.16 seconds while Focused or Refreshed, 0.22 seconds while Waiting or Calm, and 0.25 seconds while Sleepy or Tired. Lively transitions last 0.16 seconds.
- Interpolate briefly between target poses instead of rebuilding the full character at display refresh rate.
- Pause the floating widget timeline when the widget is hidden.
- With Reduce Motion enabled, switch poses without continuous limb movement.
- Bubble text must be exposed as one accessibility announcement and must not repeat on every refresh.

Reference measurement on 2026-07-10: a 12-second horizontal-widget render-path sample on this Mac dropped from roughly 31% average / 46.4% peak CPU in the installed v1.3.2 build to 1.5% average / 3.6% peak in the v1.4.0 Release UI harness. The v1.4.0 harness disabled account synchronization to isolate UI cost, so this is not a promise for every refresh state or Mac.
- Keep behavior deterministic within a time bucket so widget recreation does not cause random jumps.

## Suggested implementation order

1. Parse and test reset-credit count, status, and expiry from the app-server response.
2. Add the read-only advisor and fixed-size speech bubble.
3. Add provider-specific pace calculations from existing history snapshots.
4. Add the action state machine and the behavior catalogue in small groups.
5. Add settings for speech frequency, Reduce Motion behavior, and recommendation threshold.
