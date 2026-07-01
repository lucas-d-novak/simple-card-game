# test

Test suite covering game logic and UI behavior.

## Totals

- **608 engine tests** — run with `flutter test --exclude-tags golden` (what CI runs).
- **8 golden screenshot tests** — tagged `golden`, run locally with plain `flutter test`.
- **52 server tests** — the separate `server/` Dart package; run with
  `cd server && dart test`. Cover state redaction (hidden hands / deck order; the
  recipient's OWN draw-pile contents shipped SORTED — contents visible, order
  hidden; the trailing `actionLog` tail; the `cards` dictionary shipped to
  clients), action authorization (on-turn vs off-turn), same-turn server UNDO,
  reconnect / resync, custom game names, JSON/SQLite persistence (games survive a
  restart), lobby flow (create / join / start), and **player-stats / ML
  telemetry** (`stats_test.dart` — `StatsStore` events/decisions/games rows + the
  `decision_export` view, capture via `GameSession.apply`, `playerWon` backfill at
  game end, and the HIDDEN-INFO guarantee that no opponent hand-card id ever
  appears in a recorded decision's option set / state JSON).

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
flutter test --exclude-tags golden        # what CI runs (skips goldens) — 608 tests
cd server && dart test                    # the 52 server tests (redaction / auth / undo / reconnect / persistence / lobby / stats telemetry)
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
