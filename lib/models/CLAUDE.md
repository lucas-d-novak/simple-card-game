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
- `masteryReplaces` (bool, default false) — when false (legacy default) `masteryBonus` is ADDITIVE on top of `playEffects` at/above the threshold; when true it REPLACES `playEffects` ("gain 5/5 instead of 2/2 at mastery 15")
- `countsAsAllFactions` (bool) — matches any faction for ally abilities
- `art` (String?, default null) — optional art asset filename (e.g. `kor_arbiter.jpg`) from the card database; when set the UI loads `assets/cards/<art>` directly. See the card-art pipeline in [`lib/ui/CLAUDE.md`](../ui/CLAUDE.md).

All fields have defaults for backward compatibility with legacy DeckService.

### card_effect.dart
`CardEffect` — sealed class hierarchy, **31 subtypes** (the full Engine Phase 2/3 vocabulary; the `_resolveEffects` switch in `GameService` is exhaustive over them):
- **Resource effects:** `GainGemsEffect`, `GainPowerEffect`, `GainMasteryEffect`, `GainHealthEffect`, `GainMoneyEffect` (legacy)
- **Draw:** `DrawCardsEffect`
- **Opponent interaction:** `OpponentLosesHealthEffect`, `AllPlayersLoseHealthEffect`, `OpponentDrawsEffect`, `OpponentDiscardsEffect`
- **Deck thinning:** `BanishCardEffect` (with `BanishSource` enum: hand/discard/handOrDiscard), `ScrapFromCenterRowEffect`, `SelfBanishEffect`
- **Champion control:** `DestroyChampionEffect` (`all` flag: single chosen target vs. all enemy champions; no power cost), `ResetChampionEffect`
- **Discard recursion:** `ReturnFromDiscardEffect` (with `ReturnFilter` enum: any/champion/mercenary/faction, plus an optional `Faction`) — return a discard card to hand
- **Center-row recursion:** `RecruitFromCenterEffect`, `FastPlayFromCenterEffect`, `CenterDeckScryEffect`, `ScryEffect`
- **Board / static:** `TreatFactionAsEffect`, `IgnoreShieldThisTurnEffect`, `AddStaticModifierEffect`, `TuckUnderChampionEffect`, `CopyUnderCardsEffect`, `CopyPlayedCardEffect`
- **Complex:** `ChooseOneEffect` (player picks from effect groups), `ConditionalEffect` (board-state predicate wrapping an effect list), `ConditionalPowerEffect` (scales POWER with game state via `PowerCondition`: `perChampionControlled`, `perAllyPlayedThisTurn`, `perFactionPlayedThisTurn`, `perCardInDiscard`), `ScalingResourceEffect` (generalises the above to any resource pool), `InfinityShardEffect` (scales with mastery, instant win at 30+)

**Activated abilities (Exhaust) — implemented as value types, not effects:**
`ActivatedAbility` and `ActivationCost` (also in `card_effect.dart`) model
Shards of Infinity's "Exhaust: <effect>" champion abilities **structurally**, NOT
as a `CardEffect` subtype. An `ActivatedAbility` is a *container* of ordinary
`CardEffect`s plus an optional `ActivationCost` (`gems` / `mastery` / `health`,
all default 0; `ActivationCost.none` = Exhaust-only). It is attached to a card
via the optional `CardModel.activatedAbility` field (null for cards without
one). The per-champion **exhausted** lifecycle lives in `PlayerState`
(`exhaustedChampions`) and `GameService.useActivatedAbility` — see those files.
This is deliberately distinct from `playEffects`: a champion's normal effects
(re-resolvable each turn via the free `activateChampion`) vs. its separate,
Exhaust-gated activated ability.

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
- `activatedChampions` — champion ids that used their free play-effect activation this turn
- `exhaustedChampions` — champion ids tapped this turn by their Exhaust-gated `activatedAbility` (independent of `activatedChampions`); both clear in `resetTurnResources()`
- `focusedThisTurn` (bool) — true once the player has used the **Character Focus** action this turn (`GameService.focus()` — spend a gem to gain mastery, once per turn); cleared in `resetTurnResources()`
- `claimedDestinies` (List\<CardModel\>) — Destinies this player has claimed from the shared Destiny row (a persistent per-player zone; NOT reset between turns)
- `relicOptions` (List\<CardModel\>) — the Character's set-aside relic choices, available to recruit once (see `GameService.recruitRelic` and `lib/data/character_relics.dart`)
- `isEliminated` — true when health <= 0
- `cleanupTurn()` — moves regular cards to discard, returns mercenaries for removal
- `resetTurnResources()` — zeros gem and power pools, clears `focusedThisTurn`, `activatedChampions`, `exhaustedChampions`

## Extending
To add a new card effect: add a `final class` extending `CardEffect` in `card_effect.dart`, then handle the new case in `GameService._resolveEffects()` and `DeckService._applyCardEffects()`.
