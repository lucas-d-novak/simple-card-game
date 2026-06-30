# Simple Card Game

## Quick Summary

This repo is a Flutter implementation of the **Shards of Infinity** deck-building
card game, targeting Windows, iOS, Android, and web. See
[`CLAUDE.md`](CLAUDE.md) for the full architecture overview and
[`ROADMAP.md`](ROADMAP.md) for deferred / future enhancements.

The real game engine is `GameService`
([`lib/services/game_service.dart`](lib/services/game_service.dart)) — a pure-Dart
Shards of Infinity orchestrator implementing multiplayer turns, all **31**
`CardEffect` types, champions/guard/ally abilities, mastery, banish/scrap, the
Character Focus action (gem→mastery), the Destiny system, Relics, and the
Infinity Shard win condition. Card identity comes from a JSON card database
([`assets/card_db/cards.json`](assets/card_db/cards.json), **183 cards**; 101 of
the 142 in-scope cards verified so far). The live market (96 in-scope cards) and
the separate Destiny supply (29 cards) are built from that database via
[`lib/data/market_deck.dart`](lib/data/market_deck.dart).

The game also has **networked multiplayer**: an authoritative Dart WebSocket
server in [`server/`](server/) reuses the same engine to run shared LAN games,
with same-turn server-authoritative undo, reconnect/resync, a multi-game lobby
with custom game names, and JSON/SQLite persistence so in-progress games survive
a server restart. Each redacted view ships a shared **action log** (recent tail)
and the recipient's own draw-pile **contents** (sorted, order hidden). Phase 0/1
works end-to-end. See the design doc in
[`ai-docs/multiplayer_architecture.md`](ai-docs/multiplayer_architecture.md).

A legacy single-player **deck-draw demo** also still ships:
`DeckService` ([`lib/services/deck_service.dart`](lib/services/deck_service.dart))
drives [`home_screen.dart`](lib/ui/screens/home_screen.dart), kept intact for
backward compatibility. Its loop is: start with a six-card money deck, draw,
play cards for money/effects, buy from a market row, discard, and reshuffle/reset.

If you only need to get oriented quickly, read this section, then open:

- [`lib/services/game_service.dart`](lib/services/game_service.dart) — the active engine
- [`lib/models/card_effect.dart`](lib/models/card_effect.dart) — the 31 effect types
- [`lib/ui/screens/game_screen.dart`](lib/ui/screens/game_screen.dart) — the game board
- [`test/services/game_service_test.dart`](test/services/game_service_test.dart) — mechanic tests

## Quick Start

### Prerequisites

- Flutter SDK 3.41.5 installed locally
- A browser, emulator, or simulator for the platform you want to run
- Xcode for iOS builds
- Android Studio or Android SDK tooling for Android builds

This repository is already a Flutter app. You do not need to run `flutter create .`.

### Flutter version policy

This repo intentionally keeps Flutter version management simple:

- CI is pinned to Flutter 3.41.5.
- Local development should use Flutter 3.41.5 as well.
- We are not using FVM or another repo-managed Flutter toolchain yet.

Before working in the repo, verify your local SDK:

```bash
flutter --version
```

If your local version does not match 3.41.5, switch to that version before making changes. If we decide to upgrade Flutter later, update the pinned version in [`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) and this README in the same PR.

### Install and run

```bash
flutter pub get
flutter test
flutter run -d chrome
```

Other useful run targets:

```bash
flutter run -d windows
flutter run -d ios
flutter run -d android
flutter analyze
```

The multiplayer server has its own Dart package and test suite:

```bash
cd server
dart pub get
dart test
```

To see which targets are available on your machine:

```bash
flutter devices
```

### Testing and CI golden policy

`flutter test` runs everything locally, including golden screenshot tests.
Golden tests are platform-sensitive (fonts and anti-aliasing differ between
Windows dev machines and the Linux CI runner), so they are tagged `golden` in
[`dart_test.yaml`](dart_test.yaml) and **excluded in CI** via:

```bash
flutter test --exclude-tags golden
```

Regenerate goldens locally after an intentional visual change:

```bash
flutter test test/screenshot_test.dart --update-goldens
```

## What Is Implemented

### Shards of Infinity engine (`GameService`)

- Full multiplayer turn structure (play / buy / attack / end / Focus), 2-4 players
- All **31** `CardEffect` types resolved via exhaustive switch
- 6-card center row / market with auto-refill, built from the card DB (96 cards)
- Character Focus (once-per-turn gem→mastery), Destiny system (claim / use / banish-to-cascade), and Relics
- Champions (persistence, guard, manual + Exhaust-gated activated abilities)
- Ally abilities (same-faction trigger), mastery thresholds, banish/scrap
- Infinity Shard scaling + instant win at mastery 30+
- Combat, elimination, and game-over detection
- Bounded **action log** (`GameService.actionLog` / `GameLogEntry`) recording public
  events (play / recruit / attack / focus / destroy / turn / win)
- JSON card database (183 cards) loaded via `CardDatabase`
- Heuristic AI opponent for solo play

### Networked multiplayer (Phase 0/1)

- Authoritative Dart WebSocket server ([`server/`](server/)) reusing the engine
- Shared LAN games with per-player state redaction (hidden hands / deck order),
  including an id→`CardModel` `cards` dictionary so clients render exact engine cards
- Same-turn server-authoritative **undo**, reconnect/resync, and a multi-game
  lobby with custom game names + per-game rejoin
- JSON/SQLite persistence ([`server/lib/persistence.dart`](server/lib/persistence.dart)) — games survive a restart
- Per-view **action log** (shared event tail) and the recipient's own draw-pile
  **contents** (sorted A→Z; order hidden to preserve the anti-scry rule)
- Opponent plays are visible on the networked board
- Networked board: a **Log** button opens a newest-first event sheet; tapping the
  draw pile lists your own cards A→Z; a **Destinies** tray ([`destiny_tray.dart`](lib/ui/widgets/destiny_tray.dart))
  lets you Use claimed Destinies; cards whose conditional effect currently holds
  get an amber **conditional glow** (via [`redacted_condition_evaluator.dart`](lib/services/redacted_condition_evaluator.dart))

### UI

- Tap-to-zoom card modal ([`card_detail_modal.dart`](lib/ui/widgets/card_detail_modal.dart))
  with context actions (Recruit / Play / Activate / Exhaust); drag-to-play (long-press)
- Local per-turn **undo** (via `GameStateCodec`)
- Minimal on-card text (full text in the zoom modal; suppressed when a card has real art)
- Conditional **glow**: cards whose `ConditionalEffect` currently holds get an amber
  glow in hand + market (`GameService.conditionsSatisfied`; `GameCardWidget.conditionsMet`)
- Landscape `ScrollableBoard` ([`scrollable_board.dart`](lib/ui/widgets/scrollable_board.dart))
  + web PWA meta ([`web/manifest.json`](web/manifest.json))
- Fan-made **About page** ([`about_screen.dart`](lib/ui/screens/about_screen.dart)) —
  non-commercial credits to Stone Blade / Ultra PRO; reachable via an ABOUT button on
  the setup screen and `?about=1`

### Legacy deck-draw demo (`DeckService`)

- A starting deck of six money cards with values 1, 1, 2, 2, 3, and 4
- A market row with five purchasable cards, including four treasure cards and `Scout`
- Draw / play / buy / discard / reshuffle / reset over an in-memory service

## Repo Map

### Core app files

- [`lib/main.dart`](lib/main.dart): app entry point, theme, routes to `GameSetupScreen`
- [`lib/services/game_service.dart`](lib/services/game_service.dart): **the active engine** — all Shards of Infinity mechanics (incl. Focus, Destiny, Relics)
- [`lib/services/ai_service.dart`](lib/services/ai_service.dart): heuristic AI opponent
- [`lib/services/game_client.dart`](lib/services/game_client.dart): networked client (send actions, undo, apply redacted views)
- [`lib/models/card_effect.dart`](lib/models/card_effect.dart): the 31 card effect types
- [`lib/models/card_model.dart`](lib/models/card_model.dart): card data model (incl. `art`)
- [`lib/data/database/`](lib/data/CLAUDE.md): JSON card database loader + codecs
- [`lib/data/market_deck.dart`](lib/data/market_deck.dart): builds the live market (96) + Destiny supply (29) from the DB
- [`lib/ui/screens/game_screen.dart`](lib/ui/screens/game_screen.dart): main game board (local undo, zoom modal)
- [`server/`](server/): authoritative multiplayer WebSocket server
- [`lib/services/deck_service.dart`](lib/services/deck_service.dart): legacy deck-draw demo
- [`lib/ui/screens/home_screen.dart`](lib/ui/screens/home_screen.dart): legacy demo screen

### Tests

The Flutter suite has **563 engine tests** (run with `flutter test --exclude-tags golden`)
plus **8 golden screenshot tests** (run locally with plain `flutter test`). The
server package has **39 server tests** (`cd server && dart test`) covering state
redaction, action authorization, lobby flow, undo, reconnect/resync, and persistence. Highlights:

- [`test/services/game_service_test.dart`](test/services/game_service_test.dart): the engine spec — effects, combat, champions, mastery, win conditions
- [`test/data/`](test/data/): card database, effect codec, and `game_state_codec` serialization tests
- [`server/test/session_test.dart`](server/test/session_test.dart): redaction, authorization, and lobby tests
- [`test/services/deck_service_test.dart`](test/services/deck_service_test.dart): legacy deck-draw rule coverage
- [`test/widget_test.dart`](test/widget_test.dart): legacy demo UI coverage

### Supporting docs

- [`ai-docs/flutter_deck_draw_plan.md`](ai-docs/flutter_deck_draw_plan.md): historical design notes from an earlier stage of the prototype
- [`ai-docs/animation_system_design.md`](ai-docs/animation_system_design.md): design notes for the 3-speed animation system
- [`ai-docs/responsive_ui_design.md`](ai-docs/responsive_ui_design.md): design notes for the responsive breakpoints
- [`ai-docs/engine_gaps.md`](ai-docs/engine_gaps.md): catalogue of unmodeled competitive-multiplayer card mechanics and a phased plan to extend the engine
- [`ai-docs/multiplayer_architecture.md`](ai-docs/multiplayer_architecture.md): design of the authoritative WebSocket server in [`server/`](server/)

The `android/`, `ios/`, and `web/` folders are the main product targets. The desktop folders are standard Flutter scaffolding and are not the stated focus of the project right now.

## Card database

The authoritative source of card data is the JSON database in
[`assets/card_db/`](assets/card_db/README.md):

- [`cards.json`](assets/card_db/cards.json) — the 183-card database (142 in-scope, 101 verified; 41 out-of-scope co-op/boss), one entry per unique card.
- [`schema.json`](assets/card_db/schema.json) — the per-field contract (`set`, `faction`, `group`, `cardType`, `cost`, `playEffects`, `art`, `verified`, and more).
- [`README.md`](assets/card_db/README.md) — the data-entry workflow (phone photos + OCR → structured fields).

It is loaded at runtime by [`lib/data/database/card_database.dart`](lib/data/database/card_database.dart)
(`CardDatabase` + `CardRecord`), with effects decoded by
[`lib/data/database/effect_codec.dart`](lib/data/database/effect_codec.dart)
(JSON ⇄ `CardEffect`). See [`lib/data/CLAUDE.md`](lib/data/CLAUDE.md) for the layer overview.

Validate the database with:

```bash
dart run tool/validate_card_db.dart
```

[`tool/validate_card_db.dart`](tool/validate_card_db.dart) reports missing fields,
effect-decoding errors, verification status, and a per-set completeness summary.
It exits 1 on hard errors (bad JSON, duplicate id, undecodable effect).

## UI systems

### Animation system

The UI uses a centralized 3-speed timing system in
[`lib/ui/theme/animation_timing.dart`](lib/ui/theme/animation_timing.dart):
`AnimationSpeed` is `slow`, `fast`, or `instant`; widgets look up durations by
`AnimationRole` rather than hardcoding milliseconds. The global speed lives in an
`AnimationSettings` inherited widget; `AnimationTiming.of(context)` resolves the
active timing and forces `instant` under reduced-motion or when no settings are
present (so tests stay deterministic). Design notes:
[`ai-docs/animation_system_design.md`](ai-docs/animation_system_design.md).

### Responsive UI

[`lib/ui/theme/responsive.dart`](lib/ui/theme/responsive.dart) classifies the
layout by available width into `ScreenClass.mobile` / `tablet` / `desktop`
(breakpoints 600 / 1000 px, content capped at 1400 px) so the board adapts to both
desktop browsers and phones. Design notes:
[`ai-docs/responsive_ui_design.md`](ai-docs/responsive_ui_design.md).

## How The App Works (legacy deck-draw demo)

> The sections below describe the legacy `DeckService` demo only. The active
> Shards of Infinity engine is `GameService`; see [`CLAUDE.md`](CLAUDE.md) and
> [`lib/services/CLAUDE.md`](lib/services/CLAUDE.md).

### State ownership

- `HomeScreen` owns a single `DeckService` instance.
- User actions call service methods and then trigger `setState()`.
- All game state is in memory inside `DeckService`.

### Important rules and invariants

- Drawing uses the deck first.
- If the deck is empty and the discard pile has cards, drawing reshuffles discard into deck automatically.
- Drawn cards go to `hand`.
- Only money-gain effects on cards in `playedCards` contribute to `availableMoney`.
- Buying a market card spends money and moves the bought card into `discardPile`.
- The market row shrinks when cards are bought; it is not refilled yet.
- Reset recreates the starting deck and market row and clears hand, played cards, discard pile, and spent money.

### Current card data

Starting deck:

- `c1`: Coin +1, cost 1, when played gain 1 money
- `c2`: Coin +1, cost 1, when played gain 1 money
- `c3`: Coin +2, cost 2, when played gain 2 money
- `c4`: Coin +2, cost 2, when played gain 2 money
- `c5`: Coin +3, cost 3, when played gain 3 money
- `c6`: Coin +4, cost 4, when played gain 4 money

Market row:

- `m1`: Treasure +5, cost 5, when played gain 5 money
- `m2`: Treasure +4, cost 4, when played gain 4 money
- `m3`: Treasure +3, cost 3, when played gain 3 money
- `m4`: Treasure +2, cost 2, when played gain 2 money
- `m5`: Scout, cost 3, when played draw 2 cards

## Fast Onboarding Path (legacy deck-draw demo)

If you are new to the legacy demo and want to get productive quickly:

1. Read the Quick Summary above.
2. Read [`lib/services/deck_service.dart`](lib/services/deck_service.dart) to understand the game rules.
3. Read [`test/services/deck_service_test.dart`](test/services/deck_service_test.dart) to see expected behavior in executable form.
4. Read [`lib/ui/screens/home_screen.dart`](lib/ui/screens/home_screen.dart) to see how the service is wired into the UI.
5. Run `flutter test`.
6. Run `flutter run -d chrome` for the fastest local feedback loop.

## Guidance For AI Coding Agents And Onboarders

### Source of truth

- Treat the code and tests as the source of truth.
- Treat [`ai-docs/flutter_deck_draw_plan.md`](ai-docs/flutter_deck_draw_plan.md) as background context only.
- If the README and tests ever disagree, fix the README after confirming the intended behavior from the tests and current requirements.

### How to make changes safely

- Put gameplay-rule changes in tests first.
- Keep business logic in [`lib/services/deck_service.dart`](lib/services/deck_service.dart) rather than spreading it into widgets.
- Keep UI changes small and wire them through existing keys and service methods where possible.
- Use deterministic randomness in tests when you need stable expectations. The current tests seed `Random(7)`.
- Run targeted tests after each small change, then run the broader relevant test set before stopping.

### Recommended workflow for behavior changes

1. Update or add the relevant test in [`test/services/deck_service_test.dart`](test/services/deck_service_test.dart) or [`test/widget_test.dart`](test/widget_test.dart).
2. Run the targeted test that should fail first.
3. Implement the smallest code change needed.
4. Re-run the targeted test until it passes.
5. Run the related broader test file.
6. Update this README if the gameplay loop, architecture, or setup steps changed.

### Good places to extend next

- Add market refill rules
- Add turn structure
- Add more card effects
- Add persistence for in-progress games
- Introduce a state-management approach if the UI outgrows simple `setState()`

## Current Architecture In One Sentence

This is a Flutter implementation of Shards of Infinity whose pure-Dart
`GameService` engine (31 effect types, 183-card JSON database, Focus / Destiny /
Relics, DB-built market) is reused both by the Flutter client and by an
authoritative WebSocket server in [`server/`](server/) for networked multiplayer
(undo, reconnect, multi-game lobby) — alongside a retained legacy `DeckService`
deck-draw demo.
