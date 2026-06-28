# test

Test suite covering game logic and UI behavior.

## Files

### services/deck_service_test.dart
Unit tests for `DeckService` — the game rules layer. 13 tests covering:
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
flutter test                              # all tests
flutter test test/services/               # just service tests
flutter test test/widget_test.dart         # just widget tests
```

## Conventions
- Deterministic randomness via `Random` injection — never rely on real randomness in tests.
- Widget tests find elements by `ValueKey` strings matching the keys defined in `home_screen.dart`.
- Tests are the source of truth for expected behavior (per AGENTS.md).
