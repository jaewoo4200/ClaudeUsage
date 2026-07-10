# Mimo behavior and reset-credit advisor

Status: proposed

This document turns Mimo from a moving badge into a fixed-position character whose eyes, arms, legs, expression, props, and speech react to current quota pressure and opt-in local trends.

## Product principles

- The outer quota ring, character center, and widget footprint never move.
- Only eyes, eyelids, mouth, arms, legs, and small in-frame effects animate.
- Reset credits are recommendation-only. Mimo never consumes one automatically.
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

## Behavior catalogue

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

- Use 8-12 animation frames per second only while visible.
- Run active gestures in 3-5 second bursts, followed by a still interval.
- With Reduce Motion enabled, switch poses without continuous limb movement.
- Bubble text must be exposed as one accessibility announcement and must not repeat on every refresh.
- Keep behavior deterministic within a time bucket so widget recreation does not cause random jumps.

## Suggested implementation order

1. Parse and test reset-credit count, status, and expiry from the app-server response.
2. Add the read-only advisor and fixed-size speech bubble.
3. Add provider-specific pace calculations from existing history snapshots.
4. Add the action state machine and the behavior catalogue in small groups.
5. Add settings for speech frequency, Reduce Motion behavior, and recommendation threshold.
