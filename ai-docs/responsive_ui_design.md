# Responsive UI Design — 5 Iterations (Browser + Mobile)

> Companion to the in-progress `rld/responsive-ui` implementation branch.
> Status: **ideation** — 5 layout approaches for desktop browser vs. mobile.
> Generated: 2026-06-28

## Problem

The game UI is currently built for one size. The golden screenshots render at a
fixed **1280×900** (desktop). On a phone the same layout breaks: the 6-card center
row, the hand fan, and the resource bars assume horizontal room that mobile
doesn't have, and touch targets aren't sized for fingers.

Key surfaces that must adapt (from `lib/ui/`):
- `game_screen.dart` — overall board layout (opponent area, center row, hand,
  resource bars, action buttons).
- `card_fan.dart` — the hand, currently a fixed-geometry fan.
- `game_card_widget.dart` / `card_art.dart` — individual card sizing.
- `resource_bar.dart` — gem / power / mastery / health readouts.
- `game_setup_screen.dart` — player-count selection.

The five iterations below are different *strategies* for the same goal. They share
one foundation: a breakpoint classifier (mobile < ~600, tablet ~600–1000,
desktop > ~1000) via `LayoutBuilder`/`MediaQuery`.

---

## Iteration 1 — Single fluid layout (scale everything to width)

One layout; every dimension is a fraction of available width/height instead of a
fixed pixel value. Cards, fan radius, fonts, paddings all computed from
constraints.

- **Browser:** large board, big cards.
- **Mobile:** same arrangement, just smaller.

**Pros:** Simplest; one code path; no layout branching to maintain.
**Cons:** "Shrink to fit" makes cards unreadably tiny and touch targets too small
on phones; doesn't exploit vertical space on mobile. A board that's great wide is
cramped tall.
**Effort:** S. **Verdict:** acceptable floor, not a real mobile experience.

---

## Iteration 2 — Two discrete layouts behind a breakpoint switch

Author **two** deliberate layouts and pick one at runtime:
- **Wide (desktop/tablet-landscape):** opponents top, center row middle,
  hand + resources bottom — current arrangement, refined.
- **Narrow (mobile/portrait):** vertical stack — compact opponent strip,
  horizontally **scrollable** center row, hand as a bottom sheet / scrollable row,
  resources as a sticky compact bar.

**Pros:** Each form factor gets a layout that actually fits; clear mental model.
Touch targets sized properly on the narrow path.
**Cons:** Two layouts to keep in sync as features change; some widget duplication.
**Effort:** M. **Verdict:** the pragmatic, recommended default.

---

## Iteration 3 — Adaptive components (shared shell, self-sizing parts)

One board shell; each *component* decides its own responsive behavior internally:
- `ResourceBar` → full labels + icons wide; icon-only chips narrow.
- `CardFan` → arc fan wide; flat scrollable strip narrow; tap to expand a card.
- Center row → 6-across grid wide; 2–3 col grid or horizontal scroller narrow.
- Action buttons → inline row wide; collapsing FAB / bottom action bar narrow.

**Pros:** No giant if/else at the screen level; components are reusable and
independently testable; degrades gracefully across the whole range, not just two
points.
**Cons:** More upfront component work; responsive logic spread across many files
(harder to see the whole picture at once).
**Effort:** M–L. **Verdict:** best long-term architecture; more investment.

---

## Iteration 4 — Orientation-aware (portrait vs. landscape, not just width)

Branch on **orientation** in addition to size. Phones are usually portrait;
landscape phone and tablet want different treatment than portrait.
- **Portrait:** vertical priority — opponents collapse to a thin banner, hand gets
  the bottom third, center row scrolls.
- **Landscape (any device):** horizontal priority — closer to the desktop board.
- Optionally nudge the player to rotate for "best experience," or fully support
  both.

**Pros:** Mobile play in portrait (the common grip) feels native; landscape reuses
desktop work. Matches how people actually hold phones.
**Cons:** Doubles the test matrix (size × orientation); rotation handling and state
preservation across rotation add complexity.
**Effort:** M–L. **Verdict:** strong for a serious mobile release; layer on top of 2 or 3.

---

## Iteration 5 — Platform-idiomatic (web affordances vs. native mobile patterns)

Go beyond layout to *interaction idioms* per platform:
- **Browser:** hover states, tooltips, right-click context, keyboard shortcuts
  (end turn, play all), mouse drag-to-play, wider max-width with letterboxing on
  ultra-wide.
- **Mobile:** tap + long-press for card detail, swipe-to-play, bottom-sheet modals
  for choices (`ChooseOneEffect`), haptics, safe-area insets (notch/home bar),
  pull-to-refresh-style gestures avoided where they'd conflict.

**Pros:** Feels *made for* each platform, not ported. Ties directly into the
animation system's platform-adaptive iteration (see `animation_system_design.md`
Iteration 5).
**Cons:** Largest scope; interaction code per platform; most testing. Premature if
core layout (2/3) isn't solid yet.
**Effort:** L. **Verdict:** the finish line, after layout + components land.

---

## Recommended path

```
Breakpoint foundation (LayoutBuilder/MediaQuery classifier)
        │
        ▼
Iteration 2 (two discrete layouts)  ← what the running agent is implementing
        │
        ▼
Iteration 3 (adaptive components)   ← refactor toward reusable self-sizing parts
        │
        ├── Iteration 4 (orientation-aware)
        └── Iteration 5 (platform-idiomatic interactions)
```

The active `rld/responsive-ui` agent is implementing roughly **Iteration 2**
(breakpoint + distinct wide/narrow layouts). Iterations 3–5 are the follow-on
roadmap. Note the strong overlap between **Iteration 5 here** and **Iteration 5 in
the animation design** — platform-adaptive layout and platform-adaptive motion
should be built together to avoid two competing systems.

## Open questions for the user

1. Primary target — is this **mobile-first** (optimize portrait phone, scale up) or
   **desktop-first with mobile support** (current code's direction)?
2. Must it support **portrait phone**, or is landscape-only acceptable for v1?
3. Any **keyboard shortcut** expectations for the browser build?
4. Should card detail on mobile be a **bottom sheet**, a **full-screen overlay**,
   or **tap-to-zoom in place**?
