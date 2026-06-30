# Animation System Design — 5 Iterations

> Branch target: next feature branch off `rld-mvp-sprint` (e.g. `rld/animations`)
> Status: **Iterations 1–2 implemented** (`lib/ui/theme/animation_timing.dart`, wired in `main.dart`); Iterations 3–5 remain ideation.
> Generated: 2026-06-28

## Goal

A unified animation system for the Fragments of Boundlessness UI with **three global speed
settings**:

- **Slow** — deliberate, readable; good for learning / spectators / accessibility.
- **Fast** — snappy default for experienced players.
- **Instant** — no animation; state snaps immediately (also the test/golden mode).

Today animations are ad-hoc: hardcoded `Duration(milliseconds: 200/300/400)`
sprinkled across `game_screen.dart`, `game_setup_screen.dart`, and
`game_card_widget.dart` (see grep below). There is no single place to tune timing
and no way for a user to pick a speed.

```
game_screen.dart:66   Future.delayed(400ms)   // AI phase pacing
game_screen.dart:713  AnimatedX duration 300ms
game_screen.dart:1160 AnimatedX duration 300ms
game_setup_screen.dart:26  phaseDelay 300ms
game_setup_screen.dart:94  duration 200ms
game_card_widget.dart:46   duration 200ms
```

---

## What in the game actually needs animation (inventory)

Before choosing an architecture, here is the catalog of animatable moments. Each
of the 5 iterations below decides *how much* of this to cover.

| # | Moment | Current state | Why animate |
|---|--------|---------------|-------------|
| A | Card drawn hand→fan | instant add | shows where new cards came from |
| B | Card played hand→played area | AnimatedX 200/300ms | core feedback loop |
| C | Card bought center→discard | instant | confirms purchase, shows cost paid |
| D | Center row refill (slide in) | instant | clarifies market changed |
| E | Resource counters (gem/power/mastery/health) tick up/down | instant | makes gains/losses legible |
| F | Attack: power → opponent (projectile / shake / flash) | none | combat needs weight |
| G | Champion deploy + per-turn activation pulse | none | champions are persistent, need presence |
| H | Banish/scrap (card dissolves / burns away) | none | "removed from game" should feel final |
| I | Turn handoff / "Player N's turn" banner | none | orient multiplayer |
| J | Game over / win flourish | AnimatedX 300ms-ish | payoff |
| K | Mastery threshold crossed (card "unlocks") | none | signals a bonus fired |
| L | Infinity Shard tier-up / 30-mastery win | none | the signature win condition |
| M | Card hover/focus (desktop) & tap-down (mobile) | scale 200ms | affordance |

The **three speeds** must map onto whichever subset an iteration picks. The clean
rule across all iterations: speed scales *durations and delays*, never *logic*.
`instant` = all durations 0 and all `Future.delayed` collapsed to synchronous.

---

## Cross-cutting design decisions (apply to all iterations)

1. **Single source of truth for timing.** An `AnimationSpeed` enum +
   a resolver that returns concrete `Duration`s per "animation role." No widget
   hardcodes a millisecond value again.
2. **Speed is global app state**, surfaced in settings and persisted. Tests and
   golden screenshots force `instant` so they stay deterministic (this also fixes
   the fragility of timing-dependent `pumpAndSettle`).
3. **Logic and animation are decoupled.** `GameService` already returns plain
   results; animations are a pure view concern. An eliminated player, a bought
   card, etc. are *already true in state* — animation only narrates the transition.
4. **Reduced-motion respect.** If the OS/browser requests reduced motion,
   default to `instant` regardless of setting (accessibility).

---

## Iteration 1 — Minimal: centralize what exists, add the 3-speed switch

**Scope:** A/B/E + M only. Don't add new animations; *unify* the ones already there.

- Add `enum AnimationSpeed { slow, fast, instant }`.
- Add `AnimationTiming` that maps a small set of roles
  (`cardMove`, `counterTick`, `hoverScale`, `phaseDelay`) to durations:
  - slow: 600 / 500 / 250 / 600ms
  - fast: 250 / 200 / 120 / 250ms
  - instant: 0 / 0 / 0 / 0ms
- Replace the 6 hardcoded durations with role lookups.
- Wire a 3-way toggle in `game_setup_screen` and/or an in-game settings menu.

**Pros:** Tiny, low-risk, immediately makes the app tunable and fixes test
determinism. Ships in hours.
**Cons:** Combat (F), banish (H), turn handoff (I) stay un-animated — the moments
that most need "weight" are untouched. Feels like plumbing, not polish.

**Effort:** S. **Best as:** the foundation every other iteration builds on.

---

## Iteration 2 — Implicit-first: lean on Flutter's `Animated*` widgets everywhere

**Scope:** A–E, J, M. Breadth via the cheapest mechanism.

- Build on Iteration 1's timing core.
- Convert layout transitions to implicit widgets driven by the resolved durations:
  `AnimatedPositioned`/`AnimatedAlign` for cards moving between zones,
  `AnimatedSwitcher` for center-row refill, `TweenAnimationBuilder<int>` for
  resource counters ticking, `AnimatedOpacity`/`AnimatedScale` for buy/draw.
- No explicit `AnimationController`s — every animation reads `AnimationTiming`,
  so `instant` (Duration.zero) makes them all snap with zero special-casing.

**Pros:** Wide coverage with little custom code; implicit animations are the
idiomatic, low-bug path; `Duration.zero` gives instant mode for free.
**Cons:** Implicit widgets can't easily express *sequences* (play card → counter
ticks → ally ability fires in order) or bespoke effects (projectiles, dissolves).
Combat/banish still feel generic.

**Effort:** M. **Best as:** the pragmatic default if we want broad coverage fast.

---

## Iteration 3 — Choreographed: an animation queue / timeline orchestrator

**Scope:** A–L, with *ordering*. The "juicy" option.

- Introduce an `AnimationQueue` (a sequencer) the UI feeds with discrete steps
  emitted by gameplay: `CardPlayed`, `CounterChanged`, `AllyTriggered`,
  `AttackResolved`, `CardBanished`, `MasteryThresholdCrossed`, …
- Each step has a role-based duration; the queue plays them in order with optional
  overlap, so a single `playCard` reads as a little cutscene: card flies out →
  gem counter ticks → ally ability flashes the second card → done.
- `instant` drains the queue synchronously (every step Duration.zero, no delays).
- Speeds also control *inter-step gap*, not just per-step duration, so "slow"
  genuinely teaches and "fast" stays crisp.

**Pros:** This is what makes a deckbuilder feel good — causality you can see.
Handles the hard cases (sequenced effects, combat beats) the implicit approach
can't. One mental model for all motion.
**Cons:** Real architecture: needs a clean event stream from the view layer and
careful interaction with `GameService` calls (must not block input / desync
state). Most code, most testing.

**Effort:** L. **Best as:** the target end-state if animation quality is a headline feature.

---

## Iteration 4 — Physics / "game feel" layer: spring motion + juice

**Scope:** B, F, G, H, L emphasized — make key moments *feel* tactile.

- Build on Iteration 2 or 3 for movement, then add a feel layer:
  spring/curve presets per speed (slow = gentle ease, fast = overshoot spring),
  card tilt-on-drag, a subtle screen shake + damage flash on attacks, particle
  burst on banish ("removed from game" literally disintegrates), a glow/scale
  pulse when a mastery threshold or Infinity Shard tier fires.
- Speeds scale both timing *and* amplitude (instant = no shake, no particles).

**Pros:** Highest perceived production value; the signature moments (combat,
Infinity Shard win) land. Differentiates from a "spreadsheet with cards."
**Cons:** Easy to overdo (motion sickness, distraction); particles/shake cost
perf on low-end mobile; needs taste + playtesting. Should gate hard behind
reduced-motion and the `instant`/`slow` settings.

**Effort:** L. **Best as:** a polish pass *after* movement/sequencing exists.

---

## Iteration 5 — Platform-adaptive motion (ties into the responsive work)

**Scope:** orthogonal lens over 1–4 — *how* motion differs desktop vs mobile.

- Desktop/browser: hover-driven affordances (card lift on mouse-over, tooltip
  fades), room for larger travel distances and parallax in the center row.
- Mobile/touch: no hover → use tap-down scale + haptic feedback; shorter travel
  (smaller screens), bottom-sheet style transitions for card detail, swipe-to-play
  gesture with drag-follow animation.
- The `AnimationTiming` resolver takes form-factor as an input alongside speed, so
  e.g. card-move distance and curve adapt per platform while honoring the global
  speed.
- Coordinates directly with the responsive-UI branch (`rld/responsive-ui`).

**Pros:** Motion that's *right* for each device, not desktop animations shrunk
down. Reuses the breakpoint system the styling agent is building.
**Cons:** Most surface area to test (speed × platform × moment matrix); depends on
the responsive work landing first. Risk of two systems (responsive + animation)
needing tight coordination.

**Effort:** M–L (mostly integration). **Best as:** the unifying layer once both
responsive UI and an animation core exist.

---

## Recommended path

These aren't mutually exclusive — they **stack**:

```
Iteration 1 (timing core + 3-speed switch)   ← do first, unblocks everything
        │
        ▼
Iteration 2 (implicit animations, broad)     ← fast visible win
        │
        ▼
Iteration 3 (choreographed queue)            ← if animation is a headline feature
        │
        ├── Iteration 4 (game-feel/juice)    ← polish pass
        └── Iteration 5 (platform-adaptive)  ← merge with responsive branch
```

**Minimum viable** = Iteration 1 + 2: a real 3-speed system covering the common
moments, deterministic `instant` mode for tests, shipped quickly. Everything else
is upside.

## Open questions for the user

1. Is animation a *headline* feature (→ aim for Iteration 3+) or a *polish* item
   (→ stop at Iteration 2)?
2. Should `instant` be the forced mode for all automated tests/goldens? (Strong
   recommend: yes.)
3. Default speed for a new player — `slow` (teaches) or `fast` (respects
   experienced players)?
4. Do we want haptics/particles on mobile (Iteration 4/5), or keep motion
   restrained?
