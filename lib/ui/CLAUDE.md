# lib/ui

Flutter UI layer for the Fragments of Boundlessness card game.

## Structure

```
ui/
├── screens/
│   ├── game_setup_screen.dart      # Player count picker → starts game
│   ├── game_screen.dart            # Main game board (active, local + AI)
│   ├── network_game_screen.dart    # Networked board (server-authoritative)
│   ├── network_lobby_screen.dart   # Create/join multiplayer game (+ server-status chip, saved code)
│   ├── online_lobby_screen.dart    # Multi-game lobby (auto-enter recent, back-to-lobby)
│   ├── network_auto_screen.dart    # Auto-connect/reconnect entry
│   ├── about_screen.dart           # Fan-made / non-commercial credits page
│   ├── card_list_screen.dart       # Full browsable card catalog — responsive GRID (3 cols narrow/portrait, 5 landscape/wide), tap-to-zoom, search + faction/Destiny filter, cost-sorted. Relics ARE shown (bucketed under their faction/group). Linked from the setup lobby; also ?cards=1
│   └── home_screen.dart            # Legacy demo screen
├── widgets/
│   ├── game_card_widget.dart       # Styled card with faction colors, art, badges, conditional glow
│   ├── opponent_bar_strip.dart     # 4-player: condensed per-opponent bars (champions·mastery·health + guard); tap to select whose champions show (OpponentBarData/OpponentBarStrip)
│   ├── card_detail_modal.dart      # Zoom modal w/ context action (Recruit/Play/Activate/Exhaust)
│   ├── choice_modal.dart           # Shared modal for ChooseOne / Destiny / Relic picks
│   ├── played_this_turn_tray.dart  # Scrollable strip of small cards played (and fast-played/warped, red-shaded) this turn, shown above the stats bar (supersedes the old grey WARP tile)
│   ├── game_log_line.dart          # Shared inline log-line renderer (resource-grant icons + seat-id → username resolution); used by the Log sheet and playback ticker
│   ├── destiny_tray.dart           # Tray of claimed Destinies with Use actions (showDestinyTray)
│   ├── card_fan.dart               # Fan-of-cards hand display
│   ├── card_art.dart               # Procedural canvas art (faction patterns) fallback
│   ├── scrollable_board.dart       # Landscape scrollable board container
│   ├── resource_icons.dart         # Custom-painted gem/power/mastery/health/shield icons
│   ├── board_animator.dart         # Overlay-based fly-animation system (BoardAnimator façade)
│   ├── fly_overlay.dart            # FlyingWidget primitive (source→dest rect tween)
│   ├── resource_grant.dart         # Reads simple resource grants off a card's effects (for pips)
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

**Two boards, two gesture models.** They differ — don't assume one applies to
the other:

- **Networked board (`network_game_screen.dart`) — tap-to-ZOOM, drag-to-act:**
  a **tap** (or long-press) on ANY card opens the zoom modal
  (`card_detail_modal.dart`, its context-action buttons sit ~2/3 up the card:
  primary right, secondary left). To actually play/recruit you **drag** the card
  into the play field (hand card → play; market card → recruit; dragging a
  *mercenary* → opens the zoom's Recruit / Fast Play choice instead of silently
  recruiting). This is the primary board and the one players use.
- **Local/solo board (`game_screen.dart`) — tap-to-ACT:** tap a hand card to
  select (raises it, "TAP TO PLAY"), tap again to play; long-press zooms.

Shared affordances (both boards):

- **PLAY ALL** → plays all hand cards left to right (does NOT auto-attack); queues
  any deferred target pickers (banish / recruit / …) for the played cards.
- **ATTACK** → spends all power attacking the opponent (target picker in 3-4p).
  On the networked board the button is labelled **"Attack + End Turn ($power)"** —
  it deals the damage and then ends the turn in one press. If the opponent still
  has a champion your power could destroy, a **warning dialog** ("Your opponent
  still has champions in play!" — Cancel / End Turn) fires first.
- **Champions are a SINGLE action.** The zoom's champion button is labelled
  **"Exhaust"** (when the champion has an Exhaust-gated `activatedAbility`) or
  **"Activate"** (active play-effects only). Firing it does the free once-per-turn
  activation AND the Exhaust ability together — they are not separate presses.
  (The old literal **"Use"** label is gone.) A **passive-only champion** — no
  `activatedAbility` and whose play-effects are all auras (`AddStaticModifier`,
  e.g. zetta_the_encryptor's can't-be-attacked, carmine_eclipse's
  shield-per-card-under) — shows **NO button at all**; its aura applies passively
  the moment it enters play (`playCard` resolves champion play-effects on
  enter-play). Predicate: `isPassiveOnlyChampion` in `card_detail_modal.dart`.
  "Use All" (the champion-side Play All) does this for every champion. A green
  check marks an activated champion; a moon marks an exhausted one.
- **Tap an opponent champion** → zoom modal with an **Attack** action (costs the
  champion's shield in power).
- **UNDO** → reverts the last in-turn action; the undo stack snapshots engine
  state via `GameStateCodec` and is cleared on END TURN (no cross-turn undo).
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
  log (the `actionLog` tail shipped by the server's `redactFor`), each row rendered
  by the shared `GameLogLine` (inline resource-grant icons + seat-id → username
  resolution). The **Forfeit** control now lives inside this popout.
- **Draw-pile viewer** — tapping your own draw pile lists its contents **A→Z**
  (the server ships your own `drawPileContents` SORTED — contents visible, ORDER
  hidden, so the anti-scry rule holds; opponents' piles still show a count only).
- **Destinies** button (by Focus) → opens the **Destiny tray**
  (`destiny_tray.dart`, `showDestinyTray`): your claimed Destinies, each with a
  **Use** action gated by `GameService.canUseDestinyAbility` (the server ships
  `exhaustedDestinies` so used ones are disabled).
- **Faction flame backdrop** (`widgets/faction_flame_backdrop.dart`,
  `FactionFlameBackdrop`) — a flame-shaped, faction-color-coded plume rendered
  BEHIND your draw pile. Its colour is your **dominant faction** across every
  card you own (draw pile + hand + discard + played + champions; neutral
  starters excluded, ties broken by a fixed faction order) — computed by
  `_dominantFaction` on the board state — so you can read your own identity at a
  glance (the same info a card like Chlorophyte Guardian keys off). The colour is
  **locked in once** (cached per player in `_dominantFactionCache` on the first
  non-neutral result) so it does NOT shift as cards move between zones during the
  game — a player is one faction leader, one flame colour. It gently flickers
  when motion is enabled and holds a single static frame (no timers) in instant /
  reduced-motion mode, so tests never hang.
- **Tap-to-zoom everywhere** — every card on the board zooms into the detail
  modal even when you can't act on it. So a spectator or off-turn player can
  always inspect any card, not only their own hand/market.
- **Draw/discard pile sheets are labelled by Character** — tapping your draw or
  discard pile titles the sheet with your Character's display name (e.g. "Ko Syn
  Wu's draw pile"), via `characterDisplayName`.
- **Played-this-turn tray** (`widgets/played_this_turn_tray.dart`,
  `PlayedThisTurnTray`) — a scrollable strip of small cards played this turn,
  shown above the stats bar. Fast-played / warped cards (mercenary/warp cards that
  leave the game at end of turn rather than going to discard) share the SAME strip,
  **red-shaded** (`ValueKey('fastPlayShade_<id>')`) to mark them. This supersedes
  the older greyed `_GreyedPlayTile` "WARP" tile. Fed by the view's `playedThisTurn`
  + `fastPlayedThisTurn`.
- **Spectate ("Watch")** — a non-participant can watch a live game; the board's
  turn badge reads **"SPECTATING"** (instead of "YOUR TURN"/"WAITING"), the
  forfeit control is hidden, and leaving calls `client.stopSpectate()` so the
  server stops pushing views. The server exposes `GameSession.spectatorView()`
  (the same redacted filter an opponent gets, `canUndo` always false).
- **Server-restart banner** — an unexpected socket drop (e.g. the server
  restarting on a redeploy) shows a dismissible "Heads up! Server is restarting…
  try refreshing shortly." banner on both the board and the lobby.
- **Forfeit** lives inside the **game-log popout** (moved out of the top bar); a
  spectator or a finished game shows no forfeit control.
- **Edge-fade scroll** (`_EdgeFadeScroll`) — the horizontally-scrolling
  champion / played rows get a pronounced left/right gradient fade (ShaderMask)
  on whichever edge has cards clipped off-screen, so it's obvious there's more to
  scroll to.
- **Own-play ticker suppressed in portrait** — the `ActionPlaybackOverlay` drop-
  down ticker narrates opponent plays; on a mobile-portrait phone it hides YOUR
  OWN plays (they were distracting/redundant on a small screen).
- **Direct-attack warning** — pressing Attack when the opponent still has a
  killable champion opens a Cancel / End Turn confirm before spending all power
  on the face.
- **Fullscreen toggle** — a web-only top-bar `_FullscreenButton` + a floating
  `_FloatingFullscreenButton` on mobile widths (hidden where the browser
  Fullscreen API doesn't work, e.g. iOS Safari).

### Login / lobby screen (`network_lobby_screen.dart`)

- **Server-status chip** — on entry the lobby probes the game server with a
  short-lived WebSocket (3 s timeout) and shows a **Server: online / offline /
  checking** chip, so a player who can't connect immediately sees *why* (server
  down vs. their own mistake) instead of a silent failure.
- **Access code (token) + saved login** — when the server runs with an access
  token (`SHARDS_ACCESS_TOKEN`), the lobby collects the player's name and code and
  the client presents the code in its `identify` message. The name+token are
  remembered in browser `localStorage` via
  [`token_storage.dart`](../services/token_storage.dart) (a conditional-import
  shim — `token_storage_web.dart` uses `dart:html`, `token_storage_stub.dart` is
  the non-web no-op), with a **"Forget saved code"** control to clear them, and a
  one-tap **paste** button (`ValueKey('pasteAccessCodeButton')`, `_pasteToken` via
  `Clipboard.getData`) since access codes are copied from an invite and the OS
  long-press paste menu is unreliable on web/mobile.
- **Past-games summary** — a **"Past games (N)"** link
  (`ValueKey('pastGamesButton')`) opens a scrollable sheet of finished games with
  who won (Infinity Shard / elimination / draw). Active games stay in the main
  list; completed ones move here. Fed by the lobby summary's `winnerId`/`winType`.
- **About link** — a persistent **ABOUT** button
  (`ValueKey('lobbyAboutButton')`) opens the fan-made / non-commercial credits
  page from both the login and in-lobby states.

## Card widget features

- Faction-colored header bar with card name and cost badge
- Asset image art with faction-tinted overlay (see card-art pipeline below)
- **Minimal on-card text** — when a card has real art, the widget suppresses its
  printed effect text (full text lives in the zoom modal) for a cleaner board;
  cards without art still show effect descriptions in the info area
- Badges: shield value, GUARD, MERC, faction abbreviation
- **Affordable / unused-action glow** — a bright BLUE glow + border on a market
  card you can buy right now (affordable on your turn) OR on an in-play champion
  that still has an **unused action** this turn (`championHasUnusedAction` in
  `game_card_widget.dart` — a free play-effect activation and/or an un-exhausted
  Exhaust ability still available); a distinct action prompt from the gold
  selection accent and the amber conditional glow.
- **Conditional (synergy) glow** — a GOLD glow/border on a card whose
  `ConditionalEffect` predicate currently holds (the `conditionsMet` flag) **and**
  which is actually actionable (the `interactable` flag — for a market card that
  means affordable). GOLD **trumps** the blue affordable glow (they are
  mutually exclusive now, not additive), and both glows are ~15% more pronounced.
  So a synergy prompt never shows on a card you can't act on. The caller computes
  `conditionsMet` from the engine's `GameService.conditionsSatisfied(card)`
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
  own-the-physical-game notice, crediting the original creators and publisher in
  vague euphemisms (deliberately does NOT name the original game or its publisher),
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

## Board fly-animation system (`widgets/board_animator.dart`)

A reusable, overlay-based "fly" system that telegraphs board ACTIONS with motion
(a card flying deck→market on refill, resource pips flying from a played card to
their counters, a recruited card flying market→discard, a Focus gem→mastery pip).

- **`BoardAnimatorScope`** — wraps a board subtree; inserts its OWN `Overlay` so
  transient flights render above the board. Both boards wrap their root `Stack`
  in it (`game_screen.dart`, `network_game_screen.dart`).
- **`BoardAnimator.of(context)`** — the façade. `flyCard(fromKey:, toKey:, …)`
  tweens a faction-tinted mini card between two anchors; `flyResource(fromKey:,
  toKey:, icon:, count:)` fires `count` staggered resource pips. Rect variants
  (`flyCardRects` / `flyResourceRects`) take pre-resolved rects. `rectOf(key)`
  resolves a `GlobalKey`'s global rect.
- **`FlyingWidget`** (`fly_overlay.dart`) — the primitive: an `AnimationController`
  that positions a child from a source global rect to a dest rect (scale / fade /
  optional arc), then removes its `OverlayEntry`.
- **`resourceGrantsOf(effects)`** (`resource_grant.dart`) — best-effort read of a
  card's simple resource gains (`GainGems/Power/Mastery/HealthEffect`) so the
  boards know which pips to fly. Conditional/scaling/choose-one effects are
  skipped (they need live state) — never a WRONG pip, just no pip.
- **Anchors** — `GlobalKey`s tag the resource counters, deck/discard piles, the
  center row and the play area (via `KeyedSubtree`). The boards' bottom zones take
  optional anchor-key params; null = un-anchored (no-op). (The resource bar is
  inlined in each board — there is no standalone `ResourceBar` widget.)
- **Instant mode** — `BoardAnimator.of` resolves `AnimationTiming.of(context)`;
  when instant (tests / reduced-motion / `instant` speed) or no scope is present,
  the animator is a **no-op**: it spawns NOTHING and calls each `onComplete`
  synchronously (mirrors `shard_win_overlay.dart`). Tests pump the boards with no
  `AnimationSettings`, so they stay deterministic (no pending timers). Coverage:
  `test/ui/board_animator_test.dart` + `test/ui/board_animation_smoke_test.dart`.

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

## Web routing & server URL (`lib/main.dart`)

The web client is **multiplayer-first**: the bare domain defaults to the online
lobby; append `?local=1` / `?solo=1` for single-player (and `?about=1` for the
About page). `_defaultServerUrl` derives the WebSocket URL from the page:

- **https** page → `wss://<host>/ws` — the `/ws` PATH lets a single-hostname
  proxy/tunnel split the static app from the WS upgrade (so the bare domain serves
  both); secure scheme is required because browsers block `ws://` from `https://`.
- **http** page → `ws://<host>:8080` (direct LAN/dev); `localhost`/empty host →
  `ws://localhost:8080`.
- `?server=<url>` overrides the derived URL.

See [`ai-docs/deploy_cloudflare.md`](../../ai-docs/deploy_cloudflare.md) for the
Cloudflare-Tunnel + custom-domain + TLS deploy runbook (and the matching server
env vars), and
[`ai-docs/multiplayer_architecture.md`](../../ai-docs/multiplayer_architecture.md)
for transport/security.

## Legacy widgets

`home_screen.dart` and `playing_card_widget.dart` are kept for existing widget tests. They use `DeckService` and `ValueKey` strings. Don't modify their keys without updating `test/widget_test.dart`.
