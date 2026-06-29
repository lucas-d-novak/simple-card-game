# lib/models

Immutable data classes and enums for the Shards of Infinity card game.

## Files

### card_model.dart
`CardModel` — immutable card definition with all Shards of Infinity fields:
- `id`, `name`, `cost`, `playEffects` — core identity
- `faction` (Faction enum) — which of the 4 factions (or none)
- `cardType` (CardType enum) — regular, champion, or mercenary
- `shield` (int) — champion HP, power needed to destroy
- `hasGuard` (bool) — must destroy before attacking player
- `allyAbility` (List\<CardEffect\>) — triggers when same-faction card in play
- `masteryThreshold` / `masteryBonus` — bonus effects at mastery level
- `countsAsAllFactions` (bool) — matches any faction for ally abilities

All fields have defaults for backward compatibility with legacy DeckService.

### card_effect.dart
`CardEffect` — sealed class hierarchy:
- **Resource effects:** `GainGemsEffect`, `GainPowerEffect`, `GainMasteryEffect`, `GainHealthEffect`, `GainMoneyEffect` (legacy)
- **Draw:** `DrawCardsEffect`
- **Opponent interaction:** `OpponentLosesHealthEffect`
- **Deck thinning:** `BanishCardEffect` (with `BanishSource` enum: hand/discard/handOrDiscard), `ScrapFromCenterRowEffect`
- **Champion removal:** `DestroyChampionEffect` (`all` flag: single chosen target vs. all enemy champions; no power cost)
- **Discard recursion:** `ReturnFromDiscardEffect` (with `ReturnFilter` enum: any/champion/mercenary/faction, plus an optional `Faction`) — return a discard card to hand
- **Complex:** `ChooseOneEffect` (player picks from effect groups), `ConditionalPowerEffect` (scales POWER with game state via `PowerCondition`: `perChampionControlled`, `perAllyPlayedThisTurn`, `perFactionPlayedThisTurn`, `perCardInDiscard`), `InfinityShardEffect` (scales with mastery, instant win at 30+)

> **Deferred (later phase):** Exhaust / activated champion abilities are NOT
> modelled yet — they need a structural per-champion ability model (cost,
> once-per-turn exhaust state) rather than a single `CardEffect` subtype. Do not
> shoehorn them into `CardEffect`.

Each subclass has a `description` getter for UI display.

### card_type.dart
```dart
enum CardType { regular, champion, mercenary }
```
- **regular** — played, effects resolve, discarded at end of turn
- **champion** — deployed to `championsInPlay`, persists across turns, re-triggers each turn
- **mercenary** — played once, removed from game (not discarded) at end of turn

### faction.dart
```dart
enum Faction { homodeus, wraethe, order, undergrowth, none }
```
Used for ally ability matching and visual theming (colors, art patterns).

### player_state.dart
`PlayerState` — mutable per-player state:
- `health` (50), `mastery` (0), `gemPool`, `powerPool`
- Card zones: `hand`, `drawPile`, `discardPile`, `playedThisTurn`, `championsInPlay`
- `isEliminated` — true when health <= 0
- `cleanupTurn()` — moves regular cards to discard, returns mercenaries for removal
- `resetTurnResources()` — zeros gem and power pools

## Extending
To add a new card effect: add a `final class` extending `CardEffect` in `card_effect.dart`, then handle the new case in `GameService._resolveEffects()` and `DeckService._applyCardEffects()`.
