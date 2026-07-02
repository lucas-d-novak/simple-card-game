# test

Test suite covering game logic and UI behavior.

## Totals

- **791 engine tests** — run with `flutter test --exclude-tags golden` (what CI runs).
- **8 golden screenshot tests** — tagged `golden`, run locally with plain `flutter test`.
- **64 server tests** — the separate `server/` Dart package; run with
  `cd server && dart test`. Cover state redaction (hidden hands / deck order; the
  recipient's OWN draw-pile contents shipped SORTED — contents visible, order
  hidden; the trailing `actionLog` tail; the `cards` dictionary shipped to
  clients; `staticModifiers` incl. the public `sourceChampionId`), action
  authorization (on-turn vs off-turn), same-turn server UNDO,
  reconnect / resync, custom game names, JSON/SQLite persistence (games survive a
  restart, and a finished game's WINNER is re-derived rather than defaulting to a
  draw), lobby flow (create / join / start), **spectator views + admin forfeit**
  (`spectator_test.dart`, `forfeit_test.dart` — winType `'forfeit'`), and
  **player-stats / ML telemetry** (`stats_test.dart` — `StatsStore`
  events/decisions/games rows + the `decision_export` view, capture via
  `GameSession.apply`, `playerWon` backfill at game end, and the HIDDEN-INFO
  guarantee that no opponent hand-card id ever appears in a recorded decision's
  option set / state JSON).

The bulk of the engine coverage is `test/services/game_service_test.dart`
(the Fragments of Boundlessness engine spec). The legacy `DeckService` demo tests below
are a small subset.

## Files

### data/
- `card_database_test.dart`, `card_definitions_test.dart`, `effect_codec_test.dart`,
  `starter_deck_test.dart`, `card_art_map_test.dart` — card catalog + JSON
  database + codec + art-map coverage.
- `market_deck_test.dart` — `buildMarketDeckFromDatabase` / `buildDestinySupplyFromDatabase`:
  asserts the market excludes Destinies, starters, off-scope, and Aion-group cards,
  and that copy counts come from the DB `copies` field.
- `game_state_codec_test.dart` — round-trips a full `GameService`/`PlayerState`
  snapshot through `GameStateCodec` (the multiplayer serialization layer).
- `new_effects_codec_test.dart`, `ingeminex_codec_test.dart`,
  `corrected_effects_test.dart` — codec coverage for the new effect types and the
  Ingeminex entity.

### services/ (engine spec)
The bulk of engine coverage is `game_service_test.dart`. Sprint-added engine
suites include: `shield_combat_model_test.dart` + `owner_shield_data_test.dart`
(the owner combat model — in-hand shield reduction, champion HEALTH, 50-HP cap,
Datic Robes / Praetorian / One Mind), `ingeminex_test.dart` (neutral entity
spawn / attack / kill-reward), `recruit_redirect_test.dart` (Numeri Drones
redirect-next-recruit), `new_mechanics_test.dart`, `static_modifiers_test.dart`,
`turn_modifiers_test.dart`, `characters_undercard_test.dart`,
`copy_centerdeck_opponent_test.dart`, `game_condition_test.dart`,
`conditions_glow_test.dart`, `cloud_oracles_test.dart`, `action_log_extras_test.dart`.

### ui/ (widget behaviour)
Sprint-added widget suites: `card_list_screen_test.dart` (card-list grid + zoom),
`played_this_turn_tray_test.dart` (played/warped strip + fast-play shading),
`champion_unused_border_test.dart` (blue unused-action border),
`game_log_line_test.dart` (inline log icons + seat-id → name resolution),
`network_forfeit_spectate_test.dart` (spectate + forfeit-in-log-popout),
`network_attack_ends_turn_test.dart` (Attack + End Turn),
`opponent_bar_strip_test.dart` (4-player Phase A bars), plus the existing
passive-champion, portrait-ticker, game-over-draw, and board-animation suites.

### services/deck_service_test.dart
Unit tests for `DeckService` — the legacy demo rules layer. 13 tests covering:
- Initialization (deck size, market row, empty state)
- Drawing cards (single, batch, deck depletion, auto-reshuffle from discard)
- Playing cards (move to played, money calculation, rejection of invalid ids)
- Buying cards (affordability check, money subtraction, market removal, multiple purchases)
- Scout effect (draw-on-play without adding money, discard reshuffle during draw effect)
- Reset (full state restoration)
- Manual shuffle (discard into deck)

**Test helpers:**
- `ZeroRandom` — always returns 0, gives deterministic "first element" shuffles
- `gainMoneyAmount(card)` — sums `GainMoneyEffect` amounts on a card
- `drawAndPlayUntilAffordable(service, cardId)` — draws and plays cards until the player can afford a specific market card

**Seeding:** Most tests use `Random(7)` for reproducible shuffle order. Scout tests use `ZeroRandom` for fully deterministic sequences.

### widget_test.dart
Widget/integration tests that pump the full `DeckDrawApp` and interact via tap. 10 tests covering:
- Initial render state (labels, counts, market cards displayed)
- Draw-and-play flow (hand updates, played area updates, money display)
- Reset after draws/plays/purchases
- Empty deck snackbar (only when both deck and discard are empty)
- Scout play effect (draws into hand in UI, money unchanged)
- Market buy button enable/disable based on affordability
- Shuffle discard button enable/disable
- Buy flow (market card removal, discard count update, money subtraction)

**Test helpers (in addition to the ones from deck_service_test.dart):**
- `MaxRandom` — returns `max - 1`, gives deterministic "last element" shuffles
- `pumpDeckDrawApp(tester, {deckService})` — pumps the app with optional service injection
- `tapKey(tester, key)` — finds by `ValueKey`, ensures visible, taps, and settles
- `playUntilAffordable(tester, service, cardId)` — UI-level version of draw-and-play-until-affordable

## Running tests

```bash
flutter test                              # all tests (incl. goldens) — run locally
flutter test test/services/               # just service tests
flutter test test/widget_test.dart         # just widget tests
flutter test --exclude-tags golden        # what CI runs (skips goldens) — 791 tests
cd server && dart test                    # the 64 server tests (redaction / auth / undo / reconnect / persistence / lobby / spectate / forfeit / stats telemetry)
```

## Golden screenshot tests (the `golden` tag)

Golden / screenshot tests are platform-sensitive — fonts and anti-aliasing
differ between Windows dev machines and the Linux CI runner, so the same render
produces slightly different pixels. They are therefore **tagged `golden`** (tag
declared in [`dart_test.yaml`](../dart_test.yaml)) and **excluded in CI** via
`flutter test --exclude-tags golden`. There are **8 golden test cases** in
`test/screenshot_test.dart`.

- **Locally:** plain `flutter test` runs them along with everything else.
- **Regenerate goldens** after an intentional visual change:

  ```bash
  flutter test test/screenshot_test.dart --update-goldens
  ```

  Generated images live in `test/goldens/*.png`. Regenerate on the same platform
  you intend to compare against; don't commit goldens produced on a different OS
  than your reviewers'.

Animation determinism: tests don't wrap the tree in `AnimationSettings`, so
`AnimationTiming.of` falls back to `AnimationSpeed.instant` (see
[`lib/ui/CLAUDE.md`](../lib/ui/CLAUDE.md)) — no pending timers, no settle
flakiness.

## Conventions
- Deterministic randomness via `Random` injection — never rely on real randomness in tests.
- Widget tests find elements by `ValueKey` strings matching the keys defined in `home_screen.dart`.
- Tests are the source of truth for expected behavior (per AGENTS.md).
