# lib/models

Immutable data classes and enums for the Fragments of Boundlessness card game.

## Files

### card_model.dart
`CardModel` — immutable card definition with all Fragments of Boundlessness fields:
- `id`, `name`, `cost`, `playEffects` — core identity
- `faction` (Faction enum) — which of the 4 factions (or none)
- `cardType` (CardType enum) — regular, champion, or mercenary
- `shield` (int) — a champion's base HEALTH (power needed to destroy, via `GameService._effectiveHealth`); on a card in HAND it contributes to the owner's per-hit damage reduction (owner combat model)
- `shieldEqualsMastery` (bool, default false) — dynamic shield: the card's shield equals the owner's CURRENT mastery instead of a fixed value (Datic Robes)
- `hasGuard` (bool) — must destroy before attacking player
- `allyAbility` (List\<CardEffect\>) — triggers when same-faction card in play
- `masteryThreshold` / `masteryBonus` — bonus effects at mastery level
- `masteryReplaces` (bool, default false) — when false (legacy default) `masteryBonus` is ADDITIVE on top of `playEffects` at/above the threshold; when true it REPLACES `playEffects` ("gain 5/5 instead of 2/2 at mastery 15")
- `countsAsAllFactions` (bool) — matches any faction for ally abilities
- `art` (String?, default null) — optional art asset filename (e.g. `kor_arbiter.jpg`) from the card database; when set the UI loads `assets/cards/<art>` directly. See the card-art pipeline in [`lib/ui/CLAUDE.md`](../ui/CLAUDE.md).

All fields have defaults for backward compatibility with legacy DeckService.

### card_effect.dart
`CardEffect` — sealed class hierarchy, **37 subtypes** (the full Engine Phase 2/3 vocabulary; the `_resolveEffects` switch in `GameService` is exhaustive over them):
- **Resource effects:** `GainGemsEffect`, `GainPowerEffect`, `GainMasteryEffect`, `GainHealthEffect`, `GainMoneyEffect` (legacy)
- **Draw / mill:** `DrawCardsEffect`, `MillEffect` (mill top N of your own deck to discard)
- **Opponent interaction:** `OpponentLosesHealthEffect`, `OpponentLosesMasteryEffect` (raw mastery subtraction, floored at 0), `AllPlayersLoseHealthEffect`, `OpponentDrawsEffect`, `OpponentDiscardsEffect`
- **Deck thinning:** `BanishCardEffect` (with `BanishSource` enum: hand/discard/handOrDiscard/playedThisTurn), `ScrapFromCenterRowEffect`, `SelfBanishEffect`
- **Champion control:** `DestroyChampionEffect` (`all` flag: single chosen target vs. all enemy champions; no power cost), `ResetChampionEffect`
- **Discard recursion:** `ReturnFromDiscardEffect` (with `ReturnFilter` enum: any/champion/mercenary/faction + optional `Faction`; `self` returns THIS card inline, `all` returns every match inline), `ReturnFromDiscardToDeckTopEffect` (return to top of deck), `ReturnSelfWhenChampionPlayedEffect` (passive while-in-discard: playing a Champion returns this to hand — praetorian_01)
- **Recruit routing:** `RecruitToHandEffect` (on-recruit-to-hand, optional Character gate), `RedirectNextRecruitEffect` (turn-scoped single-use redirect of the next matching recruit to play or hand — numeri_drones / anomaly_cleric)
- **Center-row recursion:** `RecruitFromCenterEffect`, `FastPlayFromCenterEffect`, `CenterDeckScryEffect`, `ScryEffect`
- **Board / static:** `TreatFactionAsEffect`, `IgnoreShieldThisTurnEffect` (attacker ignores the target's per-hit damage reduction), `AddStaticModifierEffect` (carries a `StaticModifier` of `StaticModifierKind`: `shieldBuff` / `healthBuff` / `cardCostReduction` / `cannotBeAttacked` / `recruitToTopOfDeck` / `shieldPerCardUnder`; may be mastery-scaled via `masteryThreshold`/`masteryAmount`), `TuckUnderChampionEffect`, `CopyUnderCardsEffect`, `CopyPlayedCardEffect`
- **Complex:** `ChooseOneEffect` (player picks from effect groups), `ConditionalEffect` (board-state predicate wrapping an effect list), `ConditionalPowerEffect` (scales POWER with game state via `PowerCondition`: `perChampionControlled`, `perAllyPlayedThisTurn`, `perFactionPlayedThisTurn`, `perCardInDiscard`), `ScalingResourceEffect` (generalises the above to any resource pool), `InfinityShardEffect` (scales with mastery, instant win at 30+)

**Activated abilities (Exhaust) — implemented as value types, not effects:**
`ActivatedAbility` and `ActivationCost` (also in `card_effect.dart`) model
Fragments of Boundlessness's "Exhaust: <effect>" champion abilities **structurally**, NOT
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
- `health` (50), `mastery` (0), `gemPool`, `powerPool`. `maxHealth` is a global
  **50-HP cap**; `heal(amount)` clamps to it (over-heal is wasted)
- `staticModifiers` (List\<StaticModifier\>) — persistent board-wide buffs/
  protections added by `AddStaticModifierEffect` (rest-of-game lifetime); read by
  the combat / acquisition methods (`_playerDamageReduction`, `_effectiveHealth`,
  `buyCard`, `attackPlayer`)
- `pendingRecruitRedirect` (RecruitRedirect?) — a turn-scoped, single-use redirect
  installed by `RedirectNextRecruitEffect`; consumed by the next matching recruit,
  cleared at end of turn
- Card zones: `hand`, `drawPile`, `discardPile`, `playedThisTurn`, `championsInPlay`
- `activatedChampions` — champion ids that used their free play-effect activation this turn
- `exhaustedChampions` — champion ids tapped this turn by their Exhaust-gated `activatedAbility` (independent of `activatedChampions`); both clear in `resetTurnResources()`
- `focusedThisTurn` (bool) — true once the player has used the **Character Focus** action this turn (`GameService.focus()` — spend a gem to gain mastery, once per turn); cleared in `resetTurnResources()`
- `claimedDestinies` (List\<CardModel\>) — Destinies this player has claimed from the shared Destiny row (a persistent per-player zone; NOT reset between turns)
- `exhaustedDestinies` (Set\<String\>) — ids of claimed Destinies whose per-turn ability has been used this turn (`GameService.useDestinyAbility`); cleared in `resetTurnResources()`
- `relicOptions` (List\<CardModel\>) — the Character's set-aside relic choices, available to recruit once (see `GameService.recruitRelic` and `lib/data/character_relics.dart`)
- `fastPlayedThisTurn` (List\<CardModel\>) — cards WARPED / fast-played this turn: they stay VISIBLE in the play area (rendered greyed by the UI) for the rest of the turn, then leave the game (moved to removed-from-game by `cleanupTurn()`, NOT discarded). Shipped in the redacted view so both players can see them.
- `cardsUnderChampion` (Map\<String, List\<CardModel\>\>) — cards tucked face-down under a champion (`cardsUnderCount(id)` helper); count-only in redacted views.
- `cardsPlayedThisTurn` (List\<CardModel\>) — the play-history list scaling/conditional effects read (appended in `playCard`/fast-play; includes warped cards so play-history scaling still counts them); cleared each turn.
- `isEliminated` — true when health <= 0
- `cleanupTurn()` — moves regular cards to discard, returns mercenaries for removal, sweeps `fastPlayedThisTurn` to removed-from-game
- `resetTurnResources()` — zeros gem and power pools, clears `focusedThisTurn`, `activatedChampions`, `exhaustedChampions`, `exhaustedDestinies`

## Extending
To add a new card effect: add a `final class` extending `CardEffect` in `card_effect.dart`, then handle the new case in `GameService._resolveEffects()` and `DeckService._applyCardEffects()`.
