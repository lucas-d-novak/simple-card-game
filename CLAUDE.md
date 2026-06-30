# Shards of Infinity — Digital Card Game

A Flutter implementation of the Shards of Infinity deck-building card game. Targets Windows, iOS, Android, and web. The Flutter client runs the full game engine locally; an **authoritative Dart server** (`server/`) reuses that same engine for networked cross-device multiplayer (Phase 0/1 working — see [`ai-docs/multiplayer_architecture.md`](ai-docs/multiplayer_architecture.md)).

## Project goal

Build a playable digital version of Shards of Infinity with all core mechanics: 4 factions, mastery system, champions with guard, ally abilities, banish/scrap, Infinity Shard win condition, and a visually engaging card game UI.

## Quick start

```bash
flutter pub get              # install dependencies
flutter test                 # run all tests (563 + 8 goldens)
flutter run -d windows       # run on Windows
flutter run -d chrome        # run in browser
flutter analyze              # static analysis

# Multiplayer server (pure Dart, reuses the engine):
cd server && dart pub get && dart test       # 39 server tests
cd server && dart run bin/server.dart 8080   # run the WebSocket server
```

## Flutter version

Pinned to **Flutter 3.41.5** (installed at `C:/Users/rldun/code/flutter/`). CI enforces this version.

## Branch strategy

- **`main`** — owned by someone else, don't push directly
- **`rld-mvp-sprint`** — our working branch, branch features off this

## Architecture

- **DeckService** (legacy) — single-player deck demo, kept intact for backward compatibility
- **GameService** (core engine) — full Shards of Infinity orchestrator with multiplayer turn structure. **Pure Dart** (no Flutter imports) so it runs identically in the Flutter client and the server. Now also drives Character Focus (gem→mastery), the Destiny system (claim / use / banish-to-cascade), and Relic recruitment.
- **`server/`** (authoritative multiplayer) — a `dart:io` WebSocket server that depends on the engine package via `path: ../` and reuses the exact rules code. Clients send actions; the server validates + applies + broadcasts each player a redacted view (hidden-info filter). See [`ai-docs/multiplayer_architecture.md`](ai-docs/multiplayer_architecture.md).

```
lib/
├── main.dart                           # App entry, routes to GameSetupScreen
├── data/
│   ├── card_definitions.dart           # Legacy hardcoded catalog (55 unique cards)
│   ├── card_art_map.dart               # Card name → asset image path mapping (fallback when CardModel.art is unset)
│   ├── market_deck.dart                # buildMarketDeckFromDatabase (96 in-scope market cards) + buildDestinySupplyFromDatabase (29 destinies)
│   ├── character_relics.dart           # Character/relic recruitment options (recruitRelic supply)
│   ├── starter_deck.dart               # 10-card starter deck builder
│   └── database/                       # JSON-backed authoritative card DB
│       ├── card_database.dart          # CardDatabase + CardRecord (PURE DART — server-reusable)
│       ├── card_database_asset.dart    # Flutter-only rootBundle loader (CardDatabaseAsset.load)
│       ├── effect_codec.dart           # JSON ⇄ CardEffect codec
│       ├── card_serialization.dart     # CardModel ⇄ JSON (multiplayer)
│       └── game_state_codec.dart       # GameStateCodec: full GameService/PlayerState snapshot ⇄ JSON
├── models/
│   ├── card_model.dart                 # CardModel with faction, type, shield, guard, art, etc.
│   ├── card_effect.dart                # Sealed class hierarchy (31 effect types)
│   ├── card_type.dart                  # regular | champion | mercenary
│   ├── faction.dart                    # homodeus | wraethe | order | undergrowth | none
│   └── player_state.dart              # Per-player mutable state (HP, mastery, zones, claimedDestinies, relicOptions, focusedThisTurn)
├── services/
│   ├── game_service.dart              # ** Core game engine ** — all mechanics (incl. Focus, Destiny, Relics)
│   ├── ai_service.dart                # AI opponent (heuristic-based)
│   ├── game_client.dart              # Networked client (sendAction/undo, applies redacted views)
│   └── deck_service.dart              # Legacy single-player demo
└── ui/
    ├── screens/
    │   ├── game_setup_screen.dart      # Player count selection, start game
    │   ├── game_screen.dart            # Main game board (market, hand, play area, local undo)
    │   ├── network_auto_screen.dart    # Auto-enter most-recent game / back-to-lobby flow
    │   ├── network_game_screen.dart    # Networked board (opponent plays visible, server undo)
    │   ├── network_lobby_screen.dart   # Multi-game lobby (create/join, custom names, rejoin)
    │   ├── online_lobby_screen.dart    # Online lobby entry
    │   └── home_screen.dart            # Legacy demo screen
    ├── widgets/
    │   ├── game_card_widget.dart        # Faction-framed card (on-card text suppressed when real art present)
    │   ├── scrollable_board.dart        # Landscape scrollable board layout
    │   ├── card_detail_modal.dart       # Tap-to-zoom modal w/ context actions (Recruit/Play/Activate/Exhaust)
    │   ├── card_fan.dart                # Hand row display
    │   ├── card_art.dart                # Procedural card art (faction patterns) fallback
    │   ├── resource_icons.dart          # Custom-painted gem/power/mastery/health/shield icons
    │   ├── beveled_button.dart          # Beveled-teal chrome buttons
    │   ├── resource_bar.dart            # Health/mastery/gems/power display
    │   └── playing_card_widget.dart     # Legacy card widget
    └── theme/
        ├── game_theme.dart              # Dark board theme
        ├── board_chrome.dart            # Board background + chrome palette/painters
        ├── faction_colors.dart          # Faction color palettes
        ├── animation_timing.dart        # 3-speed animation system (slow/fast/instant)
        └── responsive.dart              # Screen-class breakpoints & sizing helpers

server/                                  # Authoritative multiplayer (pure-Dart, reuses lib/)
├── bin/server.dart                      # dart:io WebSocket entrypoint
├── lib/views.dart                       # redactFor() — per-player hidden-info filter (+ id→CardModel `cards` dict, focusedThisTurn/canUndo)
├── lib/protocol.dart                    # applyAction() — actions → GameService + auth gates
├── lib/game_session.dart               # one GameService + lobby↔seat id mapping + per-turn UNDO stack
└── lib/lobby.dart                       # in-memory create/join/auto-start, custom game names, reconnect/resync
```

## Subsystems

- **Card database** — [`assets/card_db/`](assets/card_db/README.md) holds the
  authoritative `cards.json` (183 entries), its `schema.json` contract, and a
  data-entry workflow. Loaded by
  [`lib/data/database/`](lib/data/CLAUDE.md) (`CardDatabase`, `CardRecord`,
  `effect_codec`) and validated by
  [`tool/validate_card_db.dart`](tool/validate_card_db.dart)
  (`dart run tool/validate_card_db.dart`).
- **Market & Destiny supplies** — [`lib/data/market_deck.dart`](lib/data/market_deck.dart):
  the center deck is built from the authoritative DB via
  `buildMarketDeckFromDatabase` (96 in-scope market cards, with real printed
  per-card `copies` counts — NOT a cost-bucket formula, NOT only the legacy
  `card_definitions.dart`). Destinies are a SEPARATE supply built by
  `buildDestinySupplyFromDatabase` (29 cards), excluded from the market; the
  engine deals six face-up into `GameService.destinyRow` and the rest into the
  cascade `destinyDeck`.
- **Card art pipeline** — precedence is `CardModel.art` (from the DB) → name→file
  map ([`lib/data/card_art_map.dart`](lib/data/card_art_map.dart)) → procedural
  fallback ([`lib/ui/widgets/card_art.dart`](lib/ui/widgets/card_art.dart)).
  Starter cards (Crystal / Blaster / Shard Reactor / Infinity Shard) use
  procedural glyphs. On-card text is suppressed when a card has real art (full
  text lives in the zoom modal).
- **Animation system** — [`lib/ui/theme/animation_timing.dart`](lib/ui/theme/animation_timing.dart):
  three speeds (slow / fast / instant), role-based durations, `AnimationSettings`
  inherited widget wired in `main.dart`; falls back to `instant` in tests. See
  [`lib/ui/CLAUDE.md`](lib/ui/CLAUDE.md) and design notes in
  [`ai-docs/animation_system_design.md`](ai-docs/animation_system_design.md).
- **Responsive UI** — [`lib/ui/theme/responsive.dart`](lib/ui/theme/responsive.dart):
  `ScreenClass` (mobile / tablet / desktop) + width breakpoints for browser and
  mobile. See [`lib/ui/CLAUDE.md`](lib/ui/CLAUDE.md) and
  [`ai-docs/responsive_ui_design.md`](ai-docs/responsive_ui_design.md).
- **Action log** — `GameService.actionLog` (`List<GameLogEntry>`{turn, playerId?,
  message}) recorded via the `_log()` helper for public events (play / recruit /
  attack / focus / destroy / turn / win); bounded. Serialized by
  `GameStateCodec` (encode/decode `actionLog`) and shipped (recent tail) per-view
  in `server/lib/views.dart`'s `redactFor` as `actionLog`. The networked board's
  **Log** button opens a newest-first sheet.
- **Draw-pile contents viewer** — `redactFor` ships the recipient's OWN draw pile
  as `drawPileContents` **sorted** (contents visible, ORDER hidden — anti-scry
  rule intact); opponents still get count only. The networked board's draw-pile
  tap lists the cards A→Z.
- **Destiny ability tray** — [`lib/ui/widgets/destiny_tray.dart`](lib/ui/widgets/destiny_tray.dart)
  (`showDestinyTray`): a **Destinies** button by Focus opens a tray of claimed
  Destinies with Use actions (`GameService.useDestinyAbility` /
  `canUseDestinyAbility`); `redactFor` ships `exhaustedDestinies`.
- **Conditional glow** — cards whose `ConditionalEffect` currently holds get an
  amber glow (hand + market). `GameService.conditionsSatisfied(card)` (engine) +
  [`lib/services/redacted_condition_evaluator.dart`](lib/services/redacted_condition_evaluator.dart)
  (client-side mirror over the redacted state for the networked board);
  `GameCardWidget.conditionsMet`.
- **About page** — [`lib/ui/screens/about_screen.dart`](lib/ui/screens/about_screen.dart):
  fan-made / non-commercial / own-the-physical-game notice, credits Stone Blade /
  Ultra PRO. Reachable via an ABOUT button on the setup screen and `?about=1`.

## Game loop (Shards of Infinity)

1. Each player starts with 10 cards: 7 Crystals (1 gem), 1 Blaster (1 power), 1 Infinity Shard, 1 Shard Reactor
2. Draw 5 cards into hand
3. Play cards to generate gems (currency) and power (damage)
4. Buy cards from the 6-card center row using gems
5. Spend power to attack opponent or destroy their champions
6. Optionally **Focus** once per turn: spend 1 gem to gain 1 mastery (`GameService.focus()`)
7. Champions persist across turns; mercenaries are removed after use
8. End turn: discard remaining hand, draw 5 new cards
9. Win by eliminating all opponents (reduce health to 0) or playing Infinity Shard at mastery 30+

## Core mechanics implemented

| Mechanic | Status | File |
|----------|--------|------|
| Turn lifecycle (play/buy/end) | Done | `game_service.dart` |
| All 31 card effect types | Done | `card_effect.dart` |
| Center row / market (6 cards, auto-refill) | Done | `game_service.dart` |
| Champion deployment & persistence | Done | `game_service.dart` |
| Champion manual activation (tap to activate) | Done | `game_service.dart` |
| Guard system (must destroy before attacking player) | Done | `game_service.dart` |
| Ally abilities (same-faction trigger) | Done | `game_service.dart` |
| countsAsAllFactions (Universal Soldier) | Done | `game_service.dart` |
| Mastery thresholds & bonuses | Done | `game_service.dart` |
| Banish from hand/discard | Done | `game_service.dart` |
| Scrap from center row | Done | `game_service.dart` |
| Infinity Shard scaling (6 tiers) | Done | `game_service.dart` |
| Infinity Shard instant win at mastery 30+ | Done | `game_service.dart` |
| Combat (attack player/champions) | Done | `game_service.dart` |
| Multi-player turn cycling | Done | `game_service.dart` |
| Elimination & game over detection | Done | `game_service.dart` |
| Mercenary cleanup (removed from game) | Done | `game_service.dart` |
| Character Focus (once-per-turn gem→mastery, `GameService.focus()`) | Done | `game_service.dart` |
| Destiny system (claim / use ability / banish-to-cascade, `destinyRow`/`destinyDeck`) | Done | `game_service.dart` |
| Relics (recruit from `relicOptions`, `GameService.recruitRelic`) | Done | `game_service.dart`, `character_relics.dart` |
| DB-driven market + separate Destiny supply (96 + 29) | Done | `market_deck.dart` |
| ChooseOneEffect (player choice) | Done | `game_service.dart` |
| ConditionalPowerEffect (per champion / per ally / per faction / per discard) | Done | `game_service.dart` |
| DestroyChampionEffect (single target / all enemy champions) | Done | `game_service.dart` |
| ReturnFromDiscardEffect (any / champion / mercenary / faction filter) | Done | `game_service.dart` |
| Banish/Scrap UI (target selection dialogs) | Done | `game_screen.dart` |
| AI opponent (heuristic, solo play) | Done | `ai_service.dart` |
| Tap-to-zoom card modal w/ context actions (Recruit/Play/Activate/Exhaust) | Done | `card_detail_modal.dart` |
| Drag-to-play (long-press) gesture model | Done | `game_screen.dart` |
| Local UNDO (per-turn, via `GameStateCodec`) | Done | `game_screen.dart` |
| Networked server-authoritative UNDO (same turn) | Done | `game_session.dart`, `game_client.dart` |
| Reconnect / resync + custom game names + per-game rejoin | Done | `lobby.dart`, `network_lobby_screen.dart` |
| Server persistence (JSON/SQLite, games survive restart) | Done | `server/lib/persistence.dart` |
| Action log (public events; serialized + per-view tail) | Done | `game_service.dart`, `game_state_codec.dart`, `server/lib/views.dart` |
| Draw-pile contents viewer (own pile sorted, order hidden) | Done | `server/lib/views.dart`, `network_game_screen.dart` |
| Destiny ability tray (Use claimed Destinies) | Done | `destiny_tray.dart`, `game_service.dart` |
| Conditional glow (amber when a card's condition holds) | Done | `redacted_condition_evaluator.dart`, `game_card_widget.dart` |
| Fan-made About page (non-commercial credits) | Done | `about_screen.dart` |
| Opponent plays visible on networked board | Done | `network_game_screen.dart` |
| Landscape scrollable board + web PWA meta | Done | `scrollable_board.dart`, `web/manifest.json` |
| Multiplayer target selection | Done | `game_screen.dart` |
| Mastery progress indicator (bar to 30) | Done | `resource_bar.dart` |
| Rematch flow (game over → replay) | Done | `game_screen.dart` |
| Card play animations (scale + highlight) | Done | `game_screen.dart` |
| Legacy demo catalog (55 unique cards) | Done | `card_definitions.dart` |
| Authoritative card DB (183 cards, 101/142 in-scope verified, 41 out-of-scope) | In progress | `assets/card_db/cards.json` |
| Engine Phase 2 + 3 (31 effect types) | Done | `card_effect.dart`, `game_service.dart` |
| Game-state serialization (multiplayer snapshot) | Done | `game_state_codec.dart` |
| Authoritative multiplayer server (Phase 0/1) | Done | `server/` |

## Factions

| Faction | Color | Theme | Example cards |
|---------|-------|-------|--------------|
| **Homodeus** | Gold | Technology, mastery, draw | Reactor Monk, Neural Relay, Kor Arbiter |
| **Wraethe** | Purple | Destruction, aggression, power | Shadow Fiend, Blood Ritualist, Chaos Imp |
| **Order** | Blue | Healing, defense, guard | Shield Bearer, Radiant Protector, Dawn Cleric |
| **Undergrowth** | Green | Nature, gems, ramp | Vine Guardian, Leaf Dancer, Nature's Bounty |

## Testing

```bash
flutter test                              # all tests (563 + 8 goldens)
flutter test --exclude-tags golden        # what CI runs (563)
flutter test test/services/               # game service + deck service + AI tests
flutter test test/data/                   # card db, codecs, serialization, starter deck
flutter test test/models/                 # model-level tests
flutter test test/widget_test.dart        # legacy widget tests
flutter test test/screenshot_test.dart --update-goldens  # regenerate screenshots
bash scripts/generate_report.sh           # generate visual QA report (HTML)
cd server && dart test                    # 39 server tests (redaction + auth + lobby + undo + reconnect + persistence)
```

- **563 engine tests** (+ 8 goldens, + 39 server tests) across game mechanics,
  models, data, codecs/serialization, AI, widgets, and the multiplayer server
- Tests use deterministic `Random` injection (`Random(7)`, `ZeroRandom`)
- Game service tests cover: initialization, all 31 effect types, buying, turn cycling, champions, guard, ally abilities, mastery thresholds (additive + replace), banish/scrap, infinity shard scaling, combat, win conditions, Character Focus, Destiny (claim/use/cascade) and Relics, Phase 2/3 board conditions, and integration scenarios. Serialization tests round-trip a full mid-game snapshot (including the action log). Server tests assert hidden-info redaction (including draw-pile contents sorted/order-hidden and the action-log tail), action authorization, per-turn undo, reconnect/resync/multi-game lobby flow, and JSON/SQLite persistence across a restart.

## CI

GitHub Actions (`.github/workflows/flutter-ci.yml`) runs `pub get`, `analyze`, `test` on every PR and push to `main`.

**Golden tests are excluded in CI.** Screenshot/golden tests are platform-sensitive
(font / anti-aliasing differs between Windows dev and the Linux runner), so they
are tagged `golden` in [`dart_test.yaml`](dart_test.yaml) and CI runs
`flutter test --exclude-tags golden`. Goldens still run locally with plain
`flutter test`; regenerate them with `flutter test test/screenshot_test.dart --update-goldens`.
See [`test/CLAUDE.md`](test/CLAUDE.md).

## Key files to read first

1. `lib/services/game_service.dart` — all game mechanics (the brain)
2. `lib/models/card_effect.dart` — sealed effect hierarchy, 31 types (the vocabulary)
3. `assets/card_db/cards.json` — authoritative 183-card DB (the content; 101/142 in-scope verified, 41 out-of-scope). Legacy `lib/data/card_definitions.dart` (55 cards) still drives the live demo.
4. `test/services/game_service_test.dart` — mechanic tests (the spec)
5. `lib/ui/screens/game_screen.dart` — game board UI
6. `lib/services/ai_service.dart` — AI opponent logic
7. `server/` + `ai-docs/multiplayer_architecture.md` — authoritative multiplayer

## Research docs

Cross-referenced. The mechanics doc is source of truth for game rules.

- [`ai-docs/shards_of_infinity_mechanics.md`](ai-docs/shards_of_infinity_mechanics.md) — **Source of truth for game rules.** Complete mechanics: rules, turn structure, factions, mastery, card list, edge cases.
- [`ai-docs/frontend_assets_research.md`](ai-docs/frontend_assets_research.md) — Flutter packages, art sources, card design patterns, faction color palettes, animation approaches.
- [`ai-docs/visual_iteration_system.md`](ai-docs/visual_iteration_system.md) — Playwright + Claude Code screenshot-driven visual QA workflow.
- [`ai-docs/implementation_plan.md`](ai-docs/implementation_plan.md) — v6 implementation plan (17 steps). Steps 1-13b, 15 complete.
- [`ai-docs/implementation_plan_review.md`](ai-docs/implementation_plan_review.md) — Peer review of v5 plan, all issues addressed in v6.
- [`ai-docs/animation_system_design.md`](ai-docs/animation_system_design.md) — Design (5 iterations) behind the 3-speed animation system (`lib/ui/theme/animation_timing.dart`).
- [`ai-docs/responsive_ui_design.md`](ai-docs/responsive_ui_design.md) — Design (5 iterations) behind the responsive breakpoints (`lib/ui/theme/responsive.dart`).
- [`ai-docs/engine_gaps.md`](ai-docs/engine_gaps.md) — Catalogue of unmodeled competitive-multiplayer card mechanics the current `CardEffect` vocabulary can't express, plus a phased plan to extend the engine.
- [`ai-docs/engine_phase2_plan.md`](ai-docs/engine_phase2_plan.md) / [`ai-docs/engine_phase3_plan.md`](ai-docs/engine_phase3_plan.md) — the Phase 2 (14→31 effect types) and Phase 3 (final gap families) engine-extension designs.
- [`ai-docs/multiplayer_architecture.md`](ai-docs/multiplayer_architecture.md) — **Authoritative-server multiplayer design** (transport, action protocol, hidden-info redaction, lobby, Pi/Cloudflare-Tunnel deploy, phased rollout). Phase 0/1 implemented in `server/`.
- [`ai-docs/design_reference/`](ai-docs/design_reference/DESIGN_SPEC.md) — official-client UI mockups + `DESIGN_SPEC.md`, the visual target for the board/modals/lobby.

## Open pull requests (temporary)

### PR #3: Feature/multiplayer turn structure
- **Branch:** `feature/multiplayer-turn-structure` -> `main`
- **Author:** ryuxik | **Status:** Awaiting review
- **Note:** Our `rld-mvp-sprint` branch implements a different (independent) approach to multiplayer via `GameService`. This PR is stale relative to our work.

### PR #4: Market refill rules
- **Branch:** `feature/market-refill-rules` -> `feature/multiplayer-turn-structure` (stacked on PR #3)
- **Author:** ryuxik | **Status:** Awaiting review
- **Note:** Stale — our implementation already has market refill via `_refillCenterRow()`.

## Subdirectory guides

- [`lib/models/CLAUDE.md`](lib/models/CLAUDE.md) — card data model and effect type hierarchy
- [`lib/data/CLAUDE.md`](lib/data/CLAUDE.md) — card catalog + JSON database layer (CardDatabase, CardRecord, effect_codec)
- [`lib/services/CLAUDE.md`](lib/services/CLAUDE.md) — DeckService API, invariants, and card data
- [`lib/ui/CLAUDE.md`](lib/ui/CLAUDE.md) — UI layout, animation system, responsive helper, widget keys
- [`test/CLAUDE.md`](test/CLAUDE.md) — test structure, helpers, golden-tag convention, running conventions
- [`assets/card_db/README.md`](assets/card_db/README.md) — card database files, schema, and data-entry workflow

## Visual QA / Screenshot reports

Generate a self-contained HTML report with screenshots of key game states:

```bash
bash scripts/generate_report.sh    # generates screenshots/report.html
```

The report embeds 6 golden screenshots: setup screen, game start, after playing cards, mid-game with champions, game over, and 3-player game. Open `screenshots/report.html` on any device (phone, tablet, desktop) — no server needed.

Individual goldens are at `test/goldens/*.png`. Regenerate with:
```bash
flutter test test/screenshot_test.dart --update-goldens
```

Note: Text renders as blocks (Ahem font) in the test environment. Layout, colors, and structure are fully visible.

## Dependencies

Minimal — only Flutter SDK + `cupertino_icons` and `flutter_lints`. No third-party packages. See `pubspec.yaml`.
