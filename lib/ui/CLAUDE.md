# lib/ui

Flutter UI layer for the Shards of Infinity card game.

## Structure

```
ui/
├── screens/
│   ├── game_setup_screen.dart      # Player count picker → starts game
│   ├── game_screen.dart            # Main game board (active, local + AI)
│   ├── network_game_screen.dart    # Networked board (server-authoritative)
│   ├── network_lobby_screen.dart   # Create/join multiplayer game
│   ├── online_lobby_screen.dart    # Multi-game lobby (auto-enter recent, back-to-lobby)
│   ├── network_auto_screen.dart    # Auto-connect/reconnect entry
│   ├── about_screen.dart           # Fan-made / non-commercial credits page
│   └── home_screen.dart            # Legacy demo screen
├── widgets/
│   ├── game_card_widget.dart       # Styled card with faction colors, art, badges, conditional glow
│   ├── card_detail_modal.dart      # Zoom modal w/ context action (Recruit/Play/Activate/Exhaust)
│   ├── choice_modal.dart           # Shared modal for ChooseOne / Destiny / Relic picks
│   ├── destiny_tray.dart           # Tray of claimed Destinies with Use actions (showDestinyTray)
│   ├── card_fan.dart               # Fan-of-cards hand display
│   ├── card_art.dart               # Procedural canvas art (faction patterns) fallback
│   ├── scrollable_board.dart       # Landscape scrollable board container
│   ├── resource_bar.dart           # Health/mastery/gems/power bar
│   ├── resource_icons.dart         # Custom-painted gem/power/mastery/health/shield icons
│   ├── beveled_button.dart         # Beveled action button (official-client styling)
│   └── playing_card_widget.dart    # Legacy card widget
└── theme/
    ├── game_theme.dart             # Dark board theme, colors
    ├── faction_colors.dart         # Faction color palettes (primary/light/dark)
    ├── board_chrome.dart           # Board frame / chrome styling (official-client look)
    ├── animation_timing.dart       # 3-speed animation system (see below)
    └── responsive.dart             # Screen-class breakpoints & sizing helpers
```

The board UI was reworked to match the official client; reference screenshots
live in [`ai-docs/design_reference/`](../../ai-docs/design_reference/).
`resource_icons.dart` (custom `CustomPainter` resource glyphs), `beveled_button.dart`,
and `board_chrome.dart` were added as part of that pass.

## Game screen layout (top to bottom)

1. **Turn indicator** — turn number and current player name
2. **Opponent area** — resource bar + champions (clickable to attack when you have power)
3. **Center row** — 6 market cards (tap affordable ones to buy)
4. **Play area** — your champions (persistent, gold border) + cards played this turn
5. **Action message** — feedback text (gold italic)
6. **Resource bar** — your health, mastery, gems, power, deck/discard counts
7. **Action buttons** — PLAY ALL | ATTACK | END TURN
8. **Card fan** — hand cards in a rotated fan (tap to select, tap again to play)

## Key interactions

The gesture model is **tap-to-act, long-press-to-zoom**: a tap performs the
card's primary action directly, a long-press opens the zoom modal
(`card_detail_modal.dart`) where the same context action is also available
alongside full text.

- **Tap card in hand** → selects (raises it up, shows "TAP TO PLAY" label). **Tap again** → plays it.
- **Long-press any card** → opens the **zoom modal** with full effect text and a
  context action button (Recruit / Play / Activate / Exhaust — depends on where
  the card lives). Swipe/page between cards in the same zone.
- **PLAY ALL** → plays all hand cards left to right (does NOT auto-attack)
- **ATTACK** → spends all power attacking opponent (shows target picker in
  multiplayer); the button shows the damage it will deal
- **Tap opponent champion** → attacks that champion (costs shield value in power)
- **Tap your champion** → activates it (free, once per turn, shows green checkmark
  when done); a champion with an Exhaust ability also exposes an "Exhaust" action
  in its zoom modal
- **UNDO** → reverts the last in-turn action; the undo stack snapshots engine
  state via `GameStateCodec` and is cleared on END TURN (no cross-turn undo)
- **END TURN** → ends turn (unspent power is lost per rules)
- **Tap center row card** → recruits if affordable (highlighted with gold glow)
- **Banish/Scrap effects** → after playing a card with these effects, a selection dialog appears

Opponent plays are visible on the networked board. The board is wrapped in a
landscape `ScrollableBoard` (`widgets/scrollable_board.dart`) so wide layouts
scroll rather than overflow.

### Networked board extras (`network_game_screen.dart`)

- **Log** button → a scrollable, newest-first sheet of the game's public action
  log (the `actionLog` tail shipped by the server's `redactFor`).
- **Draw-pile viewer** — tapping your own draw pile lists its contents **A→Z**
  (the server ships your own `drawPileContents` SORTED — contents visible, ORDER
  hidden, so the anti-scry rule holds; opponents' piles still show a count only).
- **Destinies** button (by Focus) → opens the **Destiny tray**
  (`destiny_tray.dart`, `showDestinyTray`): your claimed Destinies, each with a
  **Use** action gated by `GameService.canUseDestinyAbility` (the server ships
  `exhaustedDestinies` so used ones are disabled).

## Card widget features

- Faction-colored header bar with card name and cost badge
- Asset image art with faction-tinted overlay (see card-art pipeline below)
- **Minimal on-card text** — when a card has real art, the widget suppresses its
  printed effect text (full text lives in the zoom modal) for a cleaner board;
  cards without art still show effect descriptions in the info area
- Badges: shield value, GUARD, MERC, faction abbreviation
- Gold glow highlight when selected or affordable
- **Conditional glow** — an amber glow on hand/market cards whose
  `ConditionalEffect` predicate currently holds (the `conditionsMet` flag). The
  caller computes it from the engine's `GameService.conditionsSatisfied(card)`
  locally, or — on the networked board — from
  [`redacted_condition_evaluator.dart`](../services/redacted_condition_evaluator.dart),
  a client-side mirror that evaluates conditions over the redacted state.
- Long-press opens the full zoom modal (`card_detail_modal.dart`)
- AnimatedScale on just-played cards in play area

### Card-art pipeline

Art is resolved in priority order:

1. **`CardModel.art`** (the DB `art` filename) → loads `assets/cards/<art>`.
2. **`card_art_map.dart`** — a card-name → asset-path fallback map.
3. **`card_art.dart`** — procedural canvas art (faction patterns) as the last
   resort.

Starter cards (Crystal / Blaster / Shard Reactor / Infinity Shard) deliberately
use procedural glyphs (the old stock-photo placeholders were replaced).

## Additional screens/overlays

- **Card zoom modal** (`card_detail_modal.dart`) — full-size card with full effect
  text and a context action (Recruit / Play / Activate / Exhaust); pages between
  cards in the same zone. Replaces the old read-only long-press popup.
- **Game over screen** — winner name, win condition (elimination vs mastery), final standings table (HP + mastery per player), Rematch and New Game buttons
- **ChooseOneEffect dialog** — buttons for each choice option (e.g., "2 gems" vs "2 power")
- **Banish dialog** — list of hand/discard cards to permanently remove
- **Scrap dialog** — list of center row cards to remove
- **Attack target dialog** — choose opponent in 3-4 player games
- **AI thinking overlay** — "AI is thinking..." indicator during AI turns
- **About page** (`screens/about_screen.dart`) — fan-made / non-commercial /
  own-the-physical-game notice, crediting Stone Blade Entertainment and Ultra PRO,
  with a "Made with care by slowfadegold.com" footer. Reached via the **ABOUT**
  button on the setup screen (`ValueKey('aboutButton')`) or the `?about=1` URL.
- **Destiny tray** (`widgets/destiny_tray.dart`, `showDestinyTray`) — the claimed
  Destinies sheet with per-Destiny **Use** actions (see networked-board extras).

## Resource bar

- Health (red/green), Gems (cyan), Power (orange)
- **Mastery progress indicator** — bar filling toward 30, turns gold when maxed
- Deck/discard pile counts

## Theme

Dark board (navy/dark blue) with:
- Faction colors: Homodeus=Gold, Wraethe=Purple, Order=Blue, Undergrowth=Green
- Resource colors: Health=Red/Green, Gems=Cyan, Power=Orange, Mastery=Purple
- Gold accents for current player, selected cards, affordable items

## Animation system (`theme/animation_timing.dart`)

A small, centralised timing system so widgets never hardcode millisecond values.
Design notes: [`ai-docs/animation_system_design.md`](../../ai-docs/animation_system_design.md).

- **`AnimationSpeed`** — `slow` (deliberate/accessible), `fast` (snappy default),
  `instant` (everything snaps to `Duration.zero`). Speed scales *durations and
  delays only*, never game logic.
- **`AnimationRole`** — logical roles widgets look up a duration by: `cardMove`,
  `counterTick`, `hoverScale`, `phaseDelay`.
- **`AnimationTiming`** — resolves a role → `Duration` for the active speed (the
  single source of truth for timing). Get one from the tree with
  `AnimationTiming.of(context)` (honours OS/browser reduced-motion via
  `MediaQuery.disableAnimations`, forcing `instant`), or `AnimationTiming.forSpeed(speed)`.
  Convenience getters: `.cardMove`, `.counterTick`, `.hoverScale`, `.phaseDelay`,
  `.isInstant`.
- **`AnimationSettings`** — `InheritedWidget` holding the global speed. Wrapped
  around `MaterialApp` in [`lib/main.dart`](../main.dart) with
  `initialSpeed: AnimationSpeed.fast`. `AnimationSettings.of(context)` returns an
  `AnimationSettingsController` whose `setSpeed()` changes the speed at runtime.

**Instant-in-tests:** when no `AnimationSettings` is above the widget,
`AnimationTiming.of` falls back to `AnimationSettings.fallbackSpeed`, which is
`AnimationSpeed.instant`. Widget/golden tests therefore stay deterministic (no
pending timers, no `pumpAndSettle` flakiness) without any setup.

Call sites in `game_screen.dart` use `AnimationTiming.of(context).cardMove` /
`.phaseDelay` for card moves and phase pacing.

## Responsive helper (`theme/responsive.dart`)

`Responsive` classifies the layout by *available width* (so it works in a
resizable desktop browser, not just by device). Design notes:
[`ai-docs/responsive_ui_design.md`](../../ai-docs/responsive_ui_design.md).

- **`ScreenClass`** — `mobile` / `tablet` / `desktop`.
- **Breakpoints:** `mobileMaxWidth = 600`, `tabletMaxWidth = 1000`,
  `maxContentWidth = 1400` (board cap on ultra-wide), `minTouchTarget = 48`.
- **Lookup:** `Responsive.classify(width)`, `Responsive.of(context)` (uses
  ambient `MediaQuery`), `Responsive.isMobile(width)`, `Responsive.isDesktop(width)`.
- **Pick-by-class:** `Responsive.value(width, mobile:, tablet:, desktop:)`
  (tablet falls back to mobile, desktop to tablet).
- **Card sizing:** `handCardWidth(width)` and `compactCardWidth(width)` scale hand
  / center-row and champion / played cards per class.

`game_screen.dart` uses these to size cards, cap content width, and toggle
`compact` card layouts on mobile. The web build ships PWA metadata
(`web/manifest.json`, `web/index.html`) so the browser client can be installed /
launched standalone.

## Legacy widgets

`home_screen.dart` and `playing_card_widget.dart` are kept for existing widget tests. They use `DeckService` and `ValueKey` strings. Don't modify their keys without updating `test/widget_test.dart`.
