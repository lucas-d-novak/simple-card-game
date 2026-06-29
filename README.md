# Simple Card Game

## Quick Summary

This repo is a small Flutter card-game prototype aimed at iOS, Android, and web.

The current gameplay loop is:

1. Game starts with multiple players, each with a shuffled six-card money deck.
2. Draw cards into your hand automatically at start of your turn.
3. Play cards from your hand to generate money or trigger card effects.
4. Buy cards from the shared market row if you can afford them.
5. Put purchased cards into your discard pile.
6. End your turn. Your played cards move to discard pile, your turn passes, and the next player draws.
7. If your deck is empty when drawing, your discard pile is automatically shuffled into a new deck.

Today, the whole game runs locally in memory. There is no backend, persistence, or package-based state management. It supports local multiplayer, orchestrated by a `GameService`. Specific deck and card rules live in `lib/services/deck_service.dart`, while global rules (market, turns) live in `lib/services/game_service.dart`, and the UI is a thin Flutter layer over those services.

If you only need to get oriented quickly, read this section, then open:

- `lib/services/game_service.dart`
- `lib/services/deck_service.dart`
- `lib/ui/screens/home_screen.dart`
- `test/services/deck_service_test.dart`

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
flutter run -d ios
flutter run -d android
flutter analyze
```

To see which targets are available on your machine:

```bash
flutter devices
```

## What Is Implemented

- Complete local multiplayer turn structure with alternating players
- A starting deck of six money cards with values 1, 1, 2, 2, 3, and 4
- A shared market row with five purchasable cards, including four treasure cards and `Scout`
- Distinct hand, played area, and discard piles per player
- Played cards automatically move to the discard pile on turn end
- Manual reshuffling of discard cards into the deck
- Automatic discard-to-deck reshuffle during draw when the deck is empty
- Hand-size limits cap the number of cards a player can draw
- Reset back to a fresh shuffled game state for all players
- Card data modeled with separate `cost` and `playEffects` fields

## Repo Map

### Core app files

- `lib/main.dart`: app entry point, theme, and `DeckDrawApp`
- `lib/models/player_state.dart`: models each player's individual state, deck, hand, and discard
- `lib/services/game_service.dart`: orchestrates multiplayer turns and global market row
- `lib/services/deck_service.dart`: local player rules for drawing, playing, and shuffling
- [`lib/models/card_effect.dart`](lib/models/card_effect.dart): card effect types and display descriptions
- [`lib/models/card_model.dart`](lib/models/card_model.dart): card data model
- [`lib/ui/screens/home_screen.dart`](lib/ui/screens/home_screen.dart): main screen and user actions
- [`lib/ui/widgets/playing_card_widget.dart`](lib/ui/widgets/playing_card_widget.dart): reusable card display widget

### Tests

- [`test/services/deck_service_test.dart`](test/services/deck_service_test.dart): game-rule coverage for deck, draw, play, buy, reset, and reshuffle behavior
- [`test/widget_test.dart`](test/widget_test.dart): UI-level coverage for draw, play, buy, reset, empty-deck messaging, and shuffle controls

### Supporting docs

- [`ai-docs/flutter_deck_draw_plan.md`](ai-docs/flutter_deck_draw_plan.md): historical design notes from an earlier stage of the prototype

The `android/`, `ios/`, and `web/` folders are the main product targets. The desktop folders are standard Flutter scaffolding and are not the stated focus of the project right now.

## How The App Works

### State ownership

- `HomeScreen` owns a single `GameService` instance.
- `GameService` orchestrates multiple `PlayerState` instances, each holding its own `DeckService`.
- User actions call service methods and then trigger `setState()`.
- All game state is in memory inside `GameService` and the nested `DeckService`s.

### Important rules and invariants

- Drawing uses the active player's deck first.
- If the deck is empty and the discard pile has cards, drawing reshuffles discard into deck automatically.
- Drawn cards go to `hand`, capped by an optional `maxHandSize`.
- Only money-gain effects on cards in `playedCards` contribute to `availableMoney`.
- Buying a market card spends money and moves the bought card into the active player's `discardPile`.
- Ending a turn clears `playedCards` to `discardPile`, advances to the next player, and draws their starting hand.
- The market row shrinks when cards are bought; it is not refilled yet.
- Reset recreates the starting deck for all players, rebuilds market row, and clears hand, played cards, discard pile, and spent money.

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

## Fast Onboarding Path

If you are new to the repo and want to get productive quickly:

1. Read the Quick Summary above.
2. Read `lib/services/game_service.dart` and `lib/services/deck_service.dart` to understand the multi-player orchestration and core card mechanics respectively.
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
- Keep business logic in `lib/services/game_service.dart` and `lib/services/deck_service.dart` rather than spreading it into widgets.
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
- Add more card effects
- Add persistence for in-progress games
- Introduce a state-management approach if the UI outgrows simple `setState()`

## Current Architecture In One Sentence

This is a test-backed Flutter prototype where a single screen drives an in-memory `GameService` orchestrating multiplayer turn rotations, shared market cards, and discrete `PlayerState` structures that map to self-contained `DeckService`s managing localized hand/discard/play logic.
