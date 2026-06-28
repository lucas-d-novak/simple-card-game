# Shards of Infinity — Digital Card Game

A Flutter implementation of the Shards of Infinity deck-building card game. Targets Windows, iOS, Android, and web. All game logic runs locally in memory — no backend or persistence yet.

## Project goal

Build a playable digital version of Shards of Infinity with all core mechanics: 4 factions, mastery system, champions with guard, ally abilities, banish/scrap, Infinity Shard win condition, and a visually engaging card game UI.

## Quick start

```bash
flutter pub get              # install dependencies
flutter test                 # run all tests (198 tests)
flutter run -d windows       # run on Windows
flutter run -d chrome        # run in browser
flutter analyze              # static analysis
```

## Flutter version

Pinned to **Flutter 3.41.5** (installed at `C:/Users/rldun/code/flutter/`). CI enforces this version.

## Branch strategy

- **`main`** — owned by someone else, don't push directly
- **`rld-mvp-sprint`** — our working branch, branch features off this

## Architecture

Two-layer architecture:
- **DeckService** (legacy) — single-player deck demo, kept intact for backward compatibility
- **GameService** (new) — full Shards of Infinity orchestrator with multiplayer turn structure

```
lib/
├── main.dart                           # App entry, routes to GameSetupScreen
├── data/
│   ├── card_definitions.dart           # Full card catalog (55 unique cards, all factions)
│   ├── card_art_map.dart               # Card name → asset image path mapping
│   └── starter_deck.dart               # 10-card starter deck builder
├── models/
│   ├── card_model.dart                 # CardModel with faction, type, shield, guard, etc.
│   ├── card_effect.dart                # Sealed class hierarchy (12 effect types)
│   ├── card_type.dart                  # regular | champion | mercenary
│   ├── faction.dart                    # homodeus | wraethe | order | undergrowth | none
│   └── player_state.dart              # Per-player mutable state (HP, mastery, zones)
├── services/
│   ├── game_service.dart              # ** Core game engine ** — all mechanics
│   ├── ai_service.dart                # AI opponent (heuristic-based)
│   └── deck_service.dart              # Legacy single-player demo
└── ui/
    ├── screens/
    │   ├── game_setup_screen.dart      # Player count selection, start game
    │   ├── game_screen.dart            # Main game board (market, hand, play area)
    │   └── home_screen.dart            # Legacy demo screen
    ├── widgets/
    │   ├── game_card_widget.dart        # Styled card with faction colors & badges
    │   ├── card_fan.dart                # Fan-of-cards hand display
    │   ├── card_art.dart                # Procedural card art (faction patterns)
    │   ├── resource_bar.dart            # Health/mastery/gems/power display
    │   └── playing_card_widget.dart     # Legacy card widget
    └── theme/
        ├── game_theme.dart              # Dark board theme
        └── faction_colors.dart          # Faction color palettes
```

## Game loop (Shards of Infinity)

1. Each player starts with 10 cards: 7 Crystals (1 gem), 1 Blaster (1 power), 1 Infinity Shard, 1 Shard Reactor
2. Draw 5 cards into hand
3. Play cards to generate gems (currency) and power (damage)
4. Buy cards from the 6-card center row using gems
5. Spend power to attack opponent or destroy their champions
6. Champions persist across turns; mercenaries are removed after use
7. End turn: discard remaining hand, draw 5 new cards
8. Win by eliminating all opponents (reduce health to 0) or playing Infinity Shard at mastery 30+

## Core mechanics implemented

| Mechanic | Status | File |
|----------|--------|------|
| Turn lifecycle (play/buy/end) | Done | `game_service.dart` |
| All 12 card effect types | Done | `card_effect.dart` |
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
| ChooseOneEffect (player choice) | Done | `game_service.dart` |
| ConditionalPowerEffect (per champion) | Done | `game_service.dart` |
| Banish/Scrap UI (target selection dialogs) | Done | `game_screen.dart` |
| AI opponent (heuristic, solo play) | Done | `ai_service.dart` |
| Card detail popup (long-press) | Done | `game_screen.dart` |
| Multiplayer target selection | Done | `game_screen.dart` |
| Mastery progress indicator (bar to 30) | Done | `resource_bar.dart` |
| Rematch flow (game over → replay) | Done | `game_screen.dart` |
| Card play animations (scale + highlight) | Done | `game_screen.dart` |
| Full card catalog (55 unique cards) | Done | `card_definitions.dart` |

## Factions

| Faction | Color | Theme | Example cards |
|---------|-------|-------|--------------|
| **Homodeus** | Gold | Technology, mastery, draw | Reactor Monk, Neural Relay, Kor Arbiter |
| **Wraethe** | Purple | Destruction, aggression, power | Shadow Fiend, Blood Ritualist, Chaos Imp |
| **Order** | Blue | Healing, defense, guard | Shield Bearer, Radiant Protector, Dawn Cleric |
| **Undergrowth** | Green | Nature, gems, ramp | Vine Guardian, Leaf Dancer, Nature's Bounty |

## Testing

```bash
flutter test                              # all 198 tests
flutter test test/services/               # game service + deck service + AI tests
flutter test test/data/                   # card definition + starter deck tests
flutter test test/models/                 # model-level tests
flutter test test/widget_test.dart        # legacy widget tests
flutter test test/screenshot_test.dart --update-goldens  # regenerate screenshots
bash scripts/generate_report.sh           # generate visual QA report (HTML)
```

- **198 total tests** across game mechanics, models, data, AI, and widgets
- Tests use deterministic `Random` injection (`Random(7)`, `ZeroRandom`)
- Game service tests cover: initialization, effects, buying, turn cycling, champions, guard, ally abilities, mastery thresholds, banish/scrap, infinity shard scaling, combat, win conditions, and integration scenarios

## CI

GitHub Actions (`.github/workflows/flutter-ci.yml`) runs `pub get`, `analyze`, `test` on every PR and push to `main`.

## Key files to read first

1. `lib/services/game_service.dart` — all game mechanics (the brain)
2. `lib/models/card_effect.dart` — sealed effect hierarchy (the vocabulary)
3. `lib/data/card_definitions.dart` — 55 unique cards, full catalog (the content)
4. `test/services/game_service_test.dart` — mechanic tests (the spec)
5. `lib/ui/screens/game_screen.dart` — game board UI
6. `lib/services/ai_service.dart` — AI opponent logic

## Research docs

Cross-referenced. The mechanics doc is source of truth for game rules.

- [`ai-docs/shards_of_infinity_mechanics.md`](ai-docs/shards_of_infinity_mechanics.md) — **Source of truth for game rules.** Complete mechanics: rules, turn structure, factions, mastery, card list, edge cases.
- [`ai-docs/frontend_assets_research.md`](ai-docs/frontend_assets_research.md) — Flutter packages, art sources, card design patterns, faction color palettes, animation approaches.
- [`ai-docs/visual_iteration_system.md`](ai-docs/visual_iteration_system.md) — Playwright + Claude Code screenshot-driven visual QA workflow.
- [`ai-docs/implementation_plan.md`](ai-docs/implementation_plan.md) — v6 implementation plan (17 steps). Steps 1-13b, 15 complete.
- [`ai-docs/implementation_plan_review.md`](ai-docs/implementation_plan_review.md) — Peer review of v5 plan, all issues addressed in v6.

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
- [`lib/services/CLAUDE.md`](lib/services/CLAUDE.md) — DeckService API, invariants, and card data
- [`lib/ui/CLAUDE.md`](lib/ui/CLAUDE.md) — UI layout, widget keys, and patterns
- [`test/CLAUDE.md`](test/CLAUDE.md) — test structure, helpers, and running conventions

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
