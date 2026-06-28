# Shards of Infinity - Implementation Plan

> Branch: `rld-mvp-sprint`
> Generated: 2026-06-27
> Version: 6 (revised based on peer review)

## Revision History

| Version | Date | Notes |
|---------|------|-------|
| v1-v4 | 2026-06-27 | Initial drafts and iterations |
| v5 | 2026-06-27 | "Final" draft submitted for review |
| v6 | 2026-06-27 | Revised to address all 17 issues from `implementation_plan_review.md`. Key changes: added Banish/Scrap step (review #1), added missing effect types (review #2-#5), split Steps 5 and 12 (review #6-#7), resolved DeckService strategy (review #8), added open PR decision (review #9), specified test fixture cards (review #12), clarified draw timing (review #14), added cleanupTurn() (review #15), addressed all remaining MEDIUM/LOW issues. Renumbered all steps sequentially. |

This plan converts the current simple card game prototype into a faithful digital
Shards of Infinity implementation. Each step is independently testable and leaves
the app in a runnable state. Steps are ordered by dependency -- no step references
concepts introduced in a later step.

---

## Open PR Decision (Review Issue #9)

Our branch is `rld-mvp-sprint`. We are building independently and do not depend on PRs #3 (`feature/multiplayer-turn-structure`) or #4 (`feature/market-refill-rules`). Our `GameService` supersedes the scope of both PRs. If either PR merges to `main` before we do, we will reconcile at that time by rebasing or cherry-picking as needed. We will not block on them, wait for them, or build on top of them.

Rationale: Our plan introduces a complete `GameService` that covers multiplayer turns (PR #3's scope) and market refill (PR #4's scope) as part of a unified architecture. Merging either PR first would create code we immediately replace. We explicitly own our implementation independently.

---

## Guiding Principles

1. **Tests first, then implementation.** Write failing tests, then make them pass.
2. **Each step is a runnable checkpoint.** The app compiles and all tests pass after every step.
3. **Extend before rewriting.** Add new fields/classes alongside existing ones; remove old code only after the new code is wired in.
4. **Mechanics before visuals.** UI changes are deferred until the service layer is solid.
5. **One concern per step.** Each step introduces exactly one new concept or system.

---

## Dependency Graph (read top-to-bottom)

```
Step 1: Resource Enums & Effect Types
  |
Step 2: CardModel Overhaul
  |
  +---> Step 3: Player State Model
  |       |
  |       +---> Step 5a: GameService Scaffold & Init
  |       |       |
  |       |       +---> Step 5b: Draw & Play
  |       |       |       |
  |       |       |       +---> Step 5c: Buy & Market Integration
  |       |       |       |       |
  |       |       |       |       +---> Step 5d: End Turn & Cycling
  |       |       |       |               |
  |       |       |       |               +---> Step 7: Mercenary Cards
  |       |       |       |               |       |
  |       |       |       |               |       +---> Step 8: Banish & Scrap System
  |       |       |       |               |               |
  |       |       |       |               |               +---> Step 9: Ally Abilities
  |       |       |       |               |                       |
  |       |       |       |               |                       +---> Step 11: Mastery Threshold Effects
  |       |       |       |               |                               |
  |       |       |       |               |                               +---> Step 12: Infinity Shard Scaling
  |       |       |       |               |                                       |
  |       |       |       |               |                                       +---> Step 15: Win Conditions
  |       |       |       |               |
  |       |       |       |               +---> Step 10: Combat System
  |       |       |       |                       |
  |       |       |       |                       +---> Step 13a: Champion Deployment & Persistence
  |       |       |       |                       |       |
  |       |       |       |                       |       +---> Step 13b: Guard & Champion Targeting
  |       |       |       |                       |               |
  |       |       |       |                       |               +---> Step 15: Win Conditions
  |       |       |       |                       |
  |       |       |       |                       +---> Step 15: Win Conditions
  |       |       |       |
  |       |       |       +---> Step 16: UI Overhaul
  |       |
  |       +---> Step 4: Starter Deck & Test Fixture Card Definitions
  |               |
  |               +---> Step 5a (above)
  |
  +---> Step 6: Market / Center Row
  |       |
  |       +---> Step 5c (above, buy integration)
  |
  +---> Step 17: Infinity Deck Card Catalog
```

---

## Step 1: Resource Enums & Effect Types

**Depends on:** Nothing (foundational)

**What:** Introduce enums for factions and card types. Extend the `CardEffect` sealed hierarchy with all effect subclasses needed for Shards of Infinity, including effects identified in `shards_of_infinity_mechanics.md` Section 24.

**Files to modify:**
- `lib/models/card_effect.dart` -- add new effect subclasses
- Create `lib/models/faction.dart` -- enum: `homodeus`, `wraethe`, `order`, `undergrowth`, `none`
- Create `lib/models/card_type.dart` -- enum: `regular`, `champion`, `mercenary`

**New `CardEffect` subclasses:**
- `GainGemsEffect(int amount)` -- replaces `GainMoneyEffect` conceptually
- `GainPowerEffect(int amount)`
- `GainMasteryEffect(int amount)`
- `GainHealthEffect(int amount)`
- `OpponentLosesHealthEffect(int amount)` -- direct health loss, bypasses Guard (review issue #2; see mechanics doc Section 24: "Opponent loses Health -- Direct health loss (not Power-based, bypasses Guard)")
- `DrawCardsEffect(int count)` -- already exists, keep as-is
- `BanishFromHandEffect()` -- banish a card from your hand (review issue #1)
- `BanishFromDiscardEffect()` -- banish a card from your discard pile (review issue #1)
- `ScrapFromCenterRowEffect()` -- remove a card from center row without buying (review issue #1)
- `ChooseOneEffect(List<List<CardEffect>> choices)` -- player picks one option (review issue #3; see mechanics doc Section 15e: Shard Reactor)
- `ConditionalPowerEffect(PowerCondition condition)` -- power that scales with game state (review issue #4; see mechanics doc Section 24: "Gain 1 Power for each Champion you control"). Uses an enum or callback to specify the condition type.
- `InfinityShardEffect()` -- placeholder, detailed behavior in Step 12

**"Counts as all factions" support (review issue #5):** Add a `bool countsAsAllFactions` field to the `Faction` model or handle via a special card flag. Decision: add `countsAsAllFactions` as a field on `CardModel` in Step 2, and update the ally check logic in Step 9 to respect it. The `Faction` enum stays simple.

**GainMoneyEffect strategy (review issue #8, #18):** Do NOT mark `GainMoneyEffect` with `@Deprecated` in this step. Keep it as a fully functional class alongside `GainGemsEffect`. No analyzer warnings, no CI failures. `GainMoneyEffect` remains a real, non-deprecated class through Step 16, when the UI overhaul removes `DeckService` and its tests. This is a hard commitment, not a preference.

**Acceptance criteria:**
- Unit test: each new effect subclass constructs, has correct `description` getter
- Unit test: `Faction` and `CardType` enums have expected values
- Unit test: `ChooseOneEffect` constructs with multiple choice branches
- Unit test: `OpponentLosesHealthEffect` constructs with an amount
- Unit test: `ConditionalPowerEffect` constructs with a condition
- Existing 23 tests still pass (`GainMoneyEffect` is unchanged and non-deprecated)

**Complexity:** S

**Replaces/extends:** Extends `card_effect.dart`. `GainMoneyEffect` is left intact; `GainGemsEffect` is its Shards of Infinity equivalent.

---

## Step 2: CardModel Overhaul

**Depends on:** Step 1 (needs Faction, CardType, new effects)

**What:** Extend `CardModel` with all fields needed for Shards of Infinity cards. The model becomes the single source of truth for card identity.

**Files to modify:**
- `lib/models/card_model.dart`
- `lib/models/CLAUDE.md`

**New fields on `CardModel`:**
```dart
final Faction faction;                    // default: Faction.none
final CardType cardType;                  // default: CardType.regular
final int shield;                         // Champions only, default 0
final bool hasGuard;                      // Champions only, default false
final List<CardEffect> allyAbility;       // default: const []
final int? masteryThreshold;              // null = no threshold
final List<CardEffect> masteryBonus;      // default: const []
final bool countsAsAllFactions;           // default: false (review issue #5)
```

The `countsAsAllFactions` field supports cards like Universal Soldier (mechanics doc Section 15e: "Counts as all factions for ally abilities"). When true, this card satisfies the ally condition for any faction.

**Migration approach:** All new fields have defaults, so existing `const CardModel(...)` calls in `DeckService` and tests continue to compile without changes.

**Acceptance criteria:**
- Unit test: `CardModel` with all new fields constructs correctly
- Unit test: default values are correct (faction=none, cardType=regular, shield=0, countsAsAllFactions=false, etc.)
- Unit test: a Champion card model with guard and shield can be constructed
- Unit test: a card with `countsAsAllFactions: true` can be constructed
- Existing 23 tests still pass unchanged

**Complexity:** S

**Replaces/extends:** Extends existing `CardModel` non-destructively.

---

## Step 3: Player State Model

**Depends on:** Step 2 (needs updated CardModel)

**What:** Create a `PlayerState` class that owns all per-player mutable state: health, mastery, gem/power pools, deck zones, and champions in play.

**Files to create:**
- `lib/models/player_state.dart`

**Fields:**
```dart
int health;              // starts at 50
int mastery;             // starts at 0, only increases
int gemPool;             // resets each turn
int powerPool;           // resets each turn
List<CardModel> hand;
List<CardModel> drawPile;
List<CardModel> discardPile;
List<CardModel> playedThisTurn;
List<CardModel> championsInPlay;
```

**Key methods:**
- `resetTurnResources()` -- zeros gemPool and powerPool
- `cleanupTurn()` -- moves regular cards from `playedThisTurn` to `discardPile`, returns mercenaries as a separate list (for GameService to add to `removedFromGame`), clears `playedThisTurn`. This method does NOT handle draw -- draw is handled by GameService. (Review issue #15)
- `addMastery(int amount)` -- mastery += amount (never decreases)
- `takeDamage(int amount)` -- health -= amount
- `heal(int amount)` -- health += amount (no cap)
- `isEliminated` getter -- health <= 0

**Acceptance criteria:**
- Unit test: initial state (50 HP, 0 mastery, empty zones)
- Unit test: mastery only increases (calling addMastery with negative is a no-op or clamped)
- Unit test: health can go above 50 via heal
- Unit test: isEliminated at 0 and below
- Unit test: resetTurnResources zeros gems/power but not mastery
- Unit test: cleanupTurn moves regular cards to discard, returns mercenaries separately, clears playedThisTurn (review issue #15)
- Unit test: cleanupTurn does not affect championsInPlay

**Complexity:** S

**Replaces/extends:** New file. Will eventually replace the zone lists currently in `DeckService`.

---

## Step 4: Starter Deck & Test Fixture Card Definitions

**Depends on:** Steps 1-2 (needs Faction, CardType, new effects, updated CardModel)

**What:** Define the Shards of Infinity starter deck (7 Crystals, 2 Blasters, 1 Infinity Shard) and a set of test fixture cards covering all mechanical variations needed by Steps 5-15. This step is data-only -- no game logic changes.

**Files to create:**
- `lib/data/card_definitions.dart` -- static card templates
- `lib/data/starter_deck.dart` -- function to create a player's starting 10 cards

**Starter deck cards:**
- `Crystal` (x7): Regular, factionless, `GainGemsEffect(1)`
- `Blaster` (x2): Regular, factionless, `GainPowerEffect(1)`
- `Infinity Shard` (x1): Regular, factionless, special (placeholder effect for now -- full scaling in Step 12)

**Test fixture cards (review issue #12):** Define the following cards explicitly, covering all mechanical variations needed for testing Steps 5-15:

| Card Name | Faction | Type | Key Mechanic Tested |
|-----------|---------|------|-------------------|
| Reactor Monk | Homodeus | Regular | Ally ability (gain mastery) |
| Neural Relay | Homodeus | Regular | Ally ability (draw) |
| Kor Arbiter | Homodeus | Champion (no guard) | Champion without guard, mastery threshold (5+) |
| Shadow Fiend | Wraethe | Champion (no guard) | Champion persistence, mastery threshold |
| Shield Bearer | Order | Champion (guard) | Guard champion |
| Radiant Protector | Order | Champion (guard) | Guard champion, different shield value |
| Vine Guardian | Undergrowth | Champion (no guard) | Champion without guard, mastery threshold |
| Chaos Imp | Wraethe | Mercenary | Mercenary lifecycle |
| Nature's Bounty | Undergrowth | Mercenary | Mercenary with gems |
| Blood Ritualist | Wraethe | Regular | `OpponentLosesHealthEffect` via mastery bonus (mastery 10+) |
| Infinity Engine | Homodeus | Regular | Multi-effect (gain mastery + gain gem), ally ability |
| Shard Reactor | None | Regular | `ChooseOneEffect` (2 gems OR 2 power) |
| Universal Soldier | None | Champion | `countsAsAllFactions: true` |
| Dark Summoner | Wraethe | Regular | Ally ability (gain power) |
| Leaf Dancer | Undergrowth | Regular | Ally ability (gain gem) |
| Dawn Cleric | Order | Regular | Ally ability (gain health), multi-effect |
| Empowered Researcher | Homodeus | Regular | Mastery threshold with draw as bonus |

This set ensures coverage of:
- Champion with guard and without guard (per faction)
- Mercenary cards (two factions)
- Mastery threshold cards (thresholds at 5+ and 10+)
- Ally abilities across all four factions
- Draw-as-ally-ability (Neural Relay)
- Multi-effect cards (Infinity Engine, Dawn Cleric)
- All-faction card (Universal Soldier)
- Choose-one card (Shard Reactor)
- OpponentLosesHealthEffect card (Blood Ritualist)

**Acceptance criteria:**
- Unit test: `buildStarterDeck(playerId)` returns 10 cards with correct types/effects
- Unit test: starter deck has exactly 7 Crystals, 2 Blasters, 1 Infinity Shard
- Unit test: card IDs are unique within a player's deck
- Unit test: test fixture cards cover all four factions
- Unit test: at least one guard champion, one non-guard champion, one mercenary, one mastery-threshold card, one ally-ability card, one multi-effect card, one all-faction card, and one choose-one card are defined
- Unit test: Universal Soldier has `countsAsAllFactions: true`

**Complexity:** M

**Replaces/extends:** Will eventually replace `DeckService._buildStartingDeck()` and `_buildMarketRow()`.

---

## Step 5a: GameService Scaffold & Initialization

**Depends on:** Steps 3, 4 (needs PlayerState, starter deck)

**What:** Create the `GameService` shell -- constructor, player list, game state tracking, and initialization. No game actions yet. (Review issue #6: split from original monolithic Step 5)

**Files to create:**
- `lib/services/game_service.dart`

**Files to modify:**
- `lib/services/CLAUDE.md`

**GameService fields:**
- `List<PlayerState> players`
- `List<CardModel> centerRow` (scaffolded as empty; populated in Step 6)
- `List<CardModel> infinityDeck` (scaffolded as empty; populated in Step 6)
- `List<CardModel> removedFromGame`
- `int currentPlayerIndex`
- `int turnNumber`
- `Random _random` (injected for deterministic testing)

**Initialization:**
- Constructor takes player count and optional `Random`
- Creates `PlayerState` for each player with starter decks
- Shuffles each player's draw pile
- Sets `currentPlayerIndex = 0`, `turnNumber = 1`

**Acceptance criteria:**
- Unit test: 2-player game initializes with correct state (50 HP each, 10-card decks, 0 mastery)
- Unit test: 3-player game initializes with 3 players
- Unit test: each player's draw pile has 10 cards, hand is empty
- Unit test: currentPlayerIndex starts at 0, turnNumber at 1
- Unit test: removedFromGame starts empty
- Existing 23 tests still pass (DeckService is untouched)

**Complexity:** S

---

## Step 5b: Draw & Play

**Depends on:** Step 5a (needs GameService scaffold)

**What:** Implement `startTurn()` (draw cards) and `playCard()` (resolve basic effects). (Review issue #6)

**Files to modify:**
- `lib/services/game_service.dart`

**startTurn():**
- Draw 5 cards into current player's hand (3 for first player on turn 1; see mechanics doc Section 3)
- Draw from player's drawPile; if drawPile is empty, shuffle discardPile into drawPile, continue drawing

**playCard(cardId):**
- Remove card from hand
- Resolve base effects:
  - `GainGemsEffect` -> add to `currentPlayer.gemPool`
  - `GainPowerEffect` -> add to `currentPlayer.powerPool`
  - `GainMasteryEffect` -> call `currentPlayer.addMastery()`
  - `GainHealthEffect` -> call `currentPlayer.heal()`
  - `DrawCardsEffect` -> draw cards from player's draw pile
  - `OpponentLosesHealthEffect` -> placeholder; requires target selection, wired fully in Step 10 (review issue #2)
  - `ChooseOneEffect` -> placeholder; requires player choice input, wired fully in Step 5b or deferred to Step 9's choice resolution. For now, accept a `choiceIndex` parameter on `playCard` (default 0). (Review issue #3)
  - `ConditionalPowerEffect` -> placeholder; evaluate condition against game state, add result to powerPool. Basic conditions (e.g., count of champions in play) can be evaluated here. (Review issue #4)
- Place card in `playedThisTurn` (champion deployment deferred to Step 13a)
- Ally ability check: deferred to Step 9 (stub returns false)
- Mastery threshold check: deferred to Step 11

**Draw timing decision (review issue #14):** Drawing happens at the END of the current player's turn (matching the physical game, mechanics doc Section 4d). In `endTurn()` (Step 5d), after cleanup, the current player draws 5 cards. On game start, the first player's initial hand is drawn as part of game initialization or at the very start of turn 1. This means a player has cards in hand during opponents' turns (visible state). The `startTurn()` method does NOT draw cards -- it only activates champions (added in Step 13a).

**Revised draw flow:**
- Game init: each player draws their initial hand (5 cards, or 3 for first player)
- `startTurn()`: activate champions (Step 13a), no draw
- `endTurn()` (Step 5d): cleanup, then draw 5 cards

**Acceptance criteria:**
- Unit test: after game init, first player has 3 cards in hand (turn 1 rule)
- Unit test: after game init, second player has 5 cards in hand
- Unit test: `playCard` with Crystal adds 1 gem to pool
- Unit test: `playCard` with Blaster adds 1 power to pool
- Unit test: `playCard` moves card to playedThisTurn
- Unit test: `playCard` with DrawCardsEffect draws from draw pile
- Unit test: draw pile auto-reshuffles from discard when empty
- Unit test: `playCard` with `ChooseOneEffect` and `choiceIndex: 0` applies first option
- Unit test: `playCard` with `ChooseOneEffect` and `choiceIndex: 1` applies second option
- Existing 23 tests still pass

**Complexity:** M

---

## Step 5c: Buy & Market Integration

**Depends on:** Steps 5b, 6 (needs playCard and center row)

**What:** Implement `buyCard()` -- spend gems to acquire a card from the center row. (Review issue #6)

**Files to modify:**
- `lib/services/game_service.dart`

**buyCard(cardId):**
- Verify the card is in the center row
- Verify `currentPlayer.gemPool >= card.cost`
- Subtract `card.cost` from `currentPlayer.gemPool`
- Move card from center row to `currentPlayer.discardPile`
- Refill center row from infinity deck (if cards remain)

**Acceptance criteria:**
- Unit test: `buyCard` subtracts gems, card goes to player's discard
- Unit test: `buyCard` refills center row from infinity deck
- Unit test: `buyCard` fails if insufficient gems
- Unit test: `buyCard` fails if card not in center row
- Unit test: buying when infinity deck is empty does not refill (review issue #16: no always-available card)
- Existing 23 tests still pass

**Complexity:** S

---

## Step 5d: End Turn & Turn Cycling

**Depends on:** Step 5b (needs draw/play)

**What:** Implement `endTurn()` -- cleanup played cards, reset resources, draw new hand, advance to next player. (Review issue #6)

**Files to modify:**
- `lib/services/game_service.dart`

**endTurn():**
1. Call `currentPlayer.cleanupTurn()` -- moves regular cards to discard, returns mercenaries
2. Add returned mercenaries to `removedFromGame`
3. Call `currentPlayer.resetTurnResources()` -- zeros gemPool and powerPool
4. Draw 5 cards for current player (end-of-turn draw per review issue #14, matching mechanics doc Section 4d)
5. Advance `currentPlayerIndex` to next non-eliminated player
6. Increment `turnNumber` when wrapping back to player 0
7. Call `startTurn()` for the new current player (champion activation, once implemented in Step 13a)

**Acceptance criteria:**
- Unit test: `endTurn` moves played regular cards to discard via cleanupTurn
- Unit test: `endTurn` resets gem/power pools to 0
- Unit test: `endTurn` draws 5 cards for the player who just ended their turn (review issue #14)
- Unit test: turn cycling works (player 0 -> player 1 -> player 0)
- Unit test: turnNumber increments correctly
- Unit test: after endTurn, current player has 5 new cards in hand
- Existing DeckService tests still pass (DeckService is untouched, `GainMoneyEffect` is still a real class per review issue #8)

**Complexity:** S

---

## Step 6: Market / Center Row

**Depends on:** Step 1 (needs effect types for card definitions)

**What:** Implement the shared Infinity Deck and 6-card center row with auto-refill. This step can be built in parallel with Steps 3-5a since it only depends on Step 1's types.

**Files to modify:**
- `lib/services/game_service.dart` -- add market management (or create a standalone `MarketService` that GameService uses)
- `lib/data/card_definitions.dart` -- add `buildInfinityDeck()` function

**Behavior:**
- `buildInfinityDeck()` creates the full shuffled market deck from card templates (with correct copy counts)
- On game init: deal 6 cards from infinity deck to center row
- On buy: remove purchased card, immediately refill from infinity deck
- When infinity deck is empty: center row shrinks (no refill)
- Center row is visible to all players
- There is no "always available" card (review issue #16; see mechanics doc Section 10)

**Acceptance criteria:**
- Unit test: center row starts with 6 cards
- Unit test: buying a card refills center row to 6 (if infinity deck has cards)
- Unit test: buying when infinity deck is empty does not refill
- Unit test: infinity deck is shuffled (with injected Random for determinism)
- Unit test: center row cards are drawn from top of infinity deck
- Unit test: when center row has fewer than 6 cards and infinity deck is empty, no replacement cards appear; there is no always-available basic card (review issue #16)

**Complexity:** M

**Replaces/extends:** Replaces the static 5-card `_buildMarketRow()` from old DeckService.

---

## Step 7: Mercenary Cards

**Depends on:** Step 5d (needs endTurn cleanup logic)

**What:** Implement mercenary card behavior -- when played, they provide effects for the turn, then are removed from the game during cleanup (not returned to player's discard).

**Files to modify:**
- `lib/services/game_service.dart` -- verify `endTurn()` cleanup handles mercenaries correctly via `cleanupTurn()`
- `lib/models/player_state.dart` -- verify `cleanupTurn()` separates mercenaries from regular cards

**Behavior:**
- During `cleanupTurn()` on PlayerState (already specified in Step 3):
  - Regular cards in `playedThisTurn` -> move to player's `discardPile`
  - Mercenary cards in `playedThisTurn` -> returned as a separate list
- GameService's `endTurn()` adds returned mercenaries to `removedFromGame`
- Champions remain in `championsInPlay` (handled in Step 13a)

**Acceptance criteria:**
- Unit test: playing a mercenary card applies its effects normally
- Unit test: after endTurn, mercenary is NOT in player's discard pile
- Unit test: after endTurn, mercenary IS in removedFromGame pile
- Unit test: regular cards still go to discard pile after endTurn
- Unit test: mercenary counts as an ally for faction purposes during the turn it's played (ally logic itself is Step 9, but the card is "in play" in playedThisTurn)

**Complexity:** S

**Replaces/extends:** Extends the endTurn cleanup logic from Step 5d.

---

## Step 8: Banish & Scrap System

**Depends on:** Steps 5d, 6 (needs GameService with turn lifecycle and center row)

**What:** Implement the Banish/Scrap mechanic -- deck thinning by permanently removing cards from hand, discard, or center row. (Review issue #1; see mechanics doc Section 24: "Banish/Scrap Mechanic")

This is a core strategic mechanic. Without it, Crystal-heavy decks cannot be trimmed and the game's mid-to-late pacing breaks down.

**Files to modify:**
- `lib/services/game_service.dart` -- add banish/scrap resolution to `playCard()` and new action methods

**Effect resolution for banish/scrap effects:**
When a card with `BanishFromHandEffect` or `BanishFromDiscardEffect` is played, the player must choose a card to banish:
- `banishFromHand(cardId)` -- remove a card from the current player's hand and add to `removedFromGame`
- `banishFromDiscard(cardId)` -- remove a card from the current player's discard pile and add to `removedFromGame`
- `scrapFromCenterRow(cardId)` -- remove a card from the center row and add to `removedFromGame`, then refill center row from infinity deck

**Card selection mechanism:** When a banish/scrap effect triggers, GameService enters a pending state that requires the player to select a target card. The method `playCard()` returns a `PendingAction` object (or sets a flag) indicating that a selection is needed. The caller (UI or test) then calls `banishFromHand(cardId)`, `banishFromDiscard(cardId)`, or `scrapFromCenterRow(cardId)` to complete the action. If no valid targets exist (e.g., empty hand for banish-from-hand), the effect is skipped.

**Constraints:**
- The Infinity Shard cannot be banished (mechanics doc Section 18: "The Infinity Shard is a permanent part of your deck and cannot be trashed, removed, or given away by any game effect")
- Banished cards go to `removedFromGame` and never return
- Scrapping from center row triggers a refill (same as buying)

**Acceptance criteria:**
- Unit test: banishing a card from hand removes it from hand and adds to removedFromGame
- Unit test: banishing a card from discard removes it from discard and adds to removedFromGame
- Unit test: scrapping from center row removes the card and refills from infinity deck
- Unit test: Infinity Shard cannot be banished (attempting to banish it fails or is rejected)
- Unit test: banished cards are not in any player zone (hand, draw, discard) after banishment
- Unit test: if no valid targets exist, the banish effect is skipped gracefully
- Unit test: scrap triggers center row refill (if infinity deck has cards)

**Complexity:** M

**Replaces/extends:** Implements the `BanishFromHandEffect`, `BanishFromDiscardEffect`, and `ScrapFromCenterRowEffect` placeholders from Step 1.

---

## Step 9: Ally Abilities

**Depends on:** Steps 5d, 7 (needs GameService with playCard, mercenary in-play tracking)

**What:** Implement faction-based ally ability triggering. When a card is played, check if the player controls or has played another card of the same faction this turn. If so, trigger the card's `allyAbility` effects. Also handles the "counts as all factions" mechanic (review issue #5).

**Files to modify:**
- `lib/services/game_service.dart` -- add ally check to `playCard()`

**Ally check logic:**
```
hasAlly(faction, thisCard) =
  playedThisTurn.any(card => card != thisCard && (
    card.faction == faction ||
    card.countsAsAllFactions
  ))
  || championsInPlay.any(card => (
    card.faction == faction ||
    card.countsAsAllFactions
  ))
```
- Factionless cards (`Faction.none`) never trigger or satisfy ally conditions (unless `countsAsAllFactions` is true)
- A card cannot be its own ally
- Champions from previous turns count as allies
- A card with `countsAsAllFactions: true` satisfies the ally condition for ANY faction (review issue #5; see mechanics doc Section 15e: Universal Soldier)

**Retroactive ally triggering (review issue #10):** When a new card is played that creates an ally condition for already-played cards this turn, those earlier cards do NOT retroactively trigger their ally abilities. This matches the physical game's "play order matters" design and is consistent with mechanics doc Section 18: "playing a faction card first means subsequent cards of that faction will trigger their ally abilities." Add a code comment acknowledging the ambiguity: some implementations (including the official digital app) may allow retroactive triggers. Our choice is documented and tested.

**ChooseOneEffect resolution for ally abilities (review issue #3):** If an ally ability contains a `ChooseOneEffect`, use the same `choiceIndex` mechanism from Step 5b. The `playCard` method may accept an optional `allyChoiceIndex` parameter or the pending-action pattern from Step 8.

**Acceptance criteria:**
- Unit test: playing two Homodeus cards triggers ally ability on the second
- Unit test: playing one Homodeus card with a Homodeus champion already in play triggers ally ability
- Unit test: playing two cards of different factions does not trigger ally abilities
- Unit test: factionless cards never trigger allies
- Unit test: ally ability effects (gems, power, mastery, draw, heal) are applied correctly
- Unit test: mercenary with a faction counts as an ally for same-faction cards played in the same turn
- Unit test: Universal Soldier (`countsAsAllFactions: true`) satisfies ally condition for any faction card played alongside it (review issue #5)
- Unit test: playing card A (Homodeus) then card B (Homodeus) -- card A's ally ability does NOT trigger retroactively. Document this choice in a code comment citing mechanics doc Section 18. (Review issue #10)

**Complexity:** M

**Replaces/extends:** Extends the `playCard` effect resolution from Step 5b.

---

## Step 10: Combat System

**Depends on:** Step 5d (needs GameService with power pool and multi-player state)

**What:** Implement spending power to deal damage to opponents. This step handles player-to-player damage and `OpponentLosesHealthEffect`. Champion targeting comes in Step 13b.

**Files to modify:**
- `lib/services/game_service.dart` -- add `attackPlayer(targetPlayerIndex, amount)`, wire `OpponentLosesHealthEffect`

**attackPlayer(targetIndex, amount):**
- Verify `amount <= currentPlayer.powerPool`
- Verify target player is not eliminated
- (Guard check deferred to Step 13b -- for now, direct attacks always allowed)
- Subtract amount from `currentPlayer.powerPool`
- Call `targetPlayer.takeDamage(amount)`
- If target is eliminated, handle elimination (see below)
- Power can be split across multiple attacks per turn

**OpponentLosesHealthEffect resolution (review issue #2):**
- When resolved, apply `targetPlayer.takeDamage(amount)` directly -- does NOT subtract from power pool, does NOT check Guard
- Requires target selection (which opponent). Use same pending-action pattern as banish, or accept a `targetPlayerIndex` parameter.
- This effect bypasses Guard champions entirely (mechanics doc Section 24)

**Eliminated player cleanup (review issue #13):**
- When a player is eliminated (health <= 0):
  - Clear their `hand`, `drawPile`, `discardPile`, and `championsInPlay`
  - Move all their cards to `removedFromGame` (mechanics doc Section 18: "The eliminated player removes all their cards from the game")
  - Skip them in turn order

**Acceptance criteria:**
- Unit test: attacking reduces target's health
- Unit test: attacking reduces attacker's power pool
- Unit test: cannot attack for more power than available
- Unit test: attacking self is not allowed
- Unit test: splitting power across two targets works
- Unit test: eliminating a player (health reaches 0) marks them as eliminated
- Unit test: eliminated players are skipped in turn order
- Unit test: `OpponentLosesHealthEffect` reduces target health without spending power (review issue #2)
- Unit test: `OpponentLosesHealthEffect` does NOT check Guard (will be verified further in Step 13b)
- Unit test: when a player is eliminated, their hand, drawPile, discardPile, and championsInPlay are all cleared (review issue #13)
- Unit test: eliminated player's cards go to removedFromGame, not back to infinity deck (review issue #13)
- Unit test: other players' cards are unaffected by an elimination (review issue #13)

**Complexity:** M

**Replaces/extends:** New capability. No existing code handles combat.

---

## Step 11: Mastery Threshold Effects

**Depends on:** Steps 5b, 9 (needs GameService playCard with mastery tracking and effect resolution, ally abilities)

**What:** When a card with a `masteryThreshold` is played, check if the player's current mastery meets or exceeds the threshold. If so, apply the `masteryBonus` effects. (See mechanics doc Section 23)

**Key timing rule:** Mastery gained from the card's base effects is applied BEFORE checking the threshold. This means a card that grants mastery could push you over its own threshold. (Mechanics doc Section 23: "Mastery gained from the card's base effect IS counted before checking that same card's Mastery threshold.")

**Files to modify:**
- `lib/services/game_service.dart` -- update `playCard()` effect resolution order

**Resolution order for `playCard` (now complete):**
1. Apply base effects (including mastery gain)
2. Check mastery threshold -> apply mastery bonus if met
3. Check ally condition -> apply ally ability if met

This ordering matches mechanics doc Section 23.

**OpponentLosesHealthEffect in mastery bonus (review issue #2):** Blood Ritualist has "Mastery 10+: Opponent loses 3 health" -- when mastery threshold is met and the bonus contains an `OpponentLosesHealthEffect`, it triggers the same bypass-Guard direct health loss from Step 10.

**Acceptance criteria:**
- Unit test: card with mastery threshold 5 does NOT trigger bonus when mastery is 4
- Unit test: card with mastery threshold 5 DOES trigger bonus when mastery is 5
- Unit test: card that grants 1 mastery with threshold 5 triggers its own bonus if mastery was 4 before playing (4+1=5 >= 5)
- Unit test: mastery bonus effects (power, draw, health) are applied correctly
- Unit test: card with both ally ability and mastery bonus can trigger both in the same play
- Unit test: mastery bonus containing `OpponentLosesHealthEffect` triggers direct health loss (review issue #2, e.g., Blood Ritualist)

**Complexity:** S

**Replaces/extends:** Extends the `playCard` resolution from Steps 5b and 9.

---

## Step 12: Infinity Shard Scaling

**Depends on:** Steps 5b, 11 (needs mastery tracking and threshold system)

**What:** Implement the Infinity Shard's unique scaling behavior based on player mastery level. (See mechanics doc Section 13)

**Files to modify:**
- `lib/data/card_definitions.dart` -- update Infinity Shard definition
- `lib/services/game_service.dart` -- add special-case handling for Infinity Shard via `InfinityShardEffect`

**Design decision: `InfinityShardEffect` subclass.** This keeps the card definition declarative and the special logic in one place.

```dart
final class InfinityShardEffect extends CardEffect {
  // Mastery tiers and their power grants:
  // 0+:  gain 1 mastery
  // 5+:  gain 1 mastery, gain 3 power
  // 10+: gain 1 mastery, gain 6 power
  // 15+: gain 1 mastery, gain 10 power
  // 20+: gain 1 mastery, gain 15 power
  // 25+: gain 1 mastery, gain 20 power
  // 30+: infinite damage (win the game)
}
```

**Implementation note (review issue #17):** Power values at each tier should be verified against the physical card or official digital app. Define them as a configurable data structure (e.g., a `Map<int, int>` of mastery threshold to power value) rather than hardcoded conditionals. The values 3/6/10/15/20 are approximate (mechanics doc Section 13 warning).

**Acceptance criteria:**
- Unit test: Infinity Shard at mastery 0 grants 1 mastery, 0 power
- Unit test: Infinity Shard at mastery 5 grants 1 mastery, 3 power
- Unit test: Infinity Shard at mastery 10 grants 1 mastery, 6 power
- Unit test: Infinity Shard mastery gain happens before tier check (playing at mastery 4 -> mastery becomes 5 -> 5+ tier applies -> gain 3 power)
- Unit test: Infinity Shard cannot be banished/removed from the game
- Unit test: Infinity Shard power values are loaded from a configurable map, not hardcoded conditionals (review issue #17)

**Complexity:** M

**Replaces/extends:** Replaces the placeholder Infinity Shard from Step 4.

---

## Step 13a: Champion Deployment & Persistence

**Depends on:** Steps 5d, 10 (needs turn lifecycle and combat)

**What:** Implement champion deployment, persistence across turns, and activation at start of turn. (Review issue #7: split from original Step 12)

**Files to modify:**
- `lib/services/game_service.dart` -- update `playCard()` for champion deployment, update `startTurn()` for champion activation

**Champion deployment (in `playCard`):**
- If card is `CardType.champion`, place in `championsInPlay` instead of `playedThisTurn`
- Champion's effects trigger immediately on the turn it's played
- Champion stays in play across turns (not affected by `cleanupTurn()`)

**Champion activation (in `startTurn`):**
- At start of turn, each champion in `championsInPlay` provides its effects (gems, power, mastery, heal)
- Champions count as allies for faction purposes (already handled by Step 9's ally check which looks at `championsInPlay`)

**Champion timing (review issue #11):**
- On the turn a champion is played: effects trigger immediately during `playCard()`, just like a regular card
- On subsequent turns: effects trigger during `startTurn()`, BEFORE any cards are played from hand
- A champion played and then another card of the same faction played the same turn -- the champion counts as an ally (it is in `championsInPlay`)

**Acceptance criteria:**
- Unit test: playing a champion places it in championsInPlay, not playedThisTurn
- Unit test: champion persists after endTurn (not moved to discard)
- Unit test: champion provides effects at start of owner's next turn (review issue #11)
- Unit test: champion played on turn 1 provides its effects immediately during playCard (review issue #11)
- Unit test: same champion on turn 2 provides its effects during startTurn, BEFORE any cards are played from hand (review issue #11)
- Unit test: champion counts as ally for same-faction cards played in the same turn (review issue #11)
- Unit test: champion effects include gems, power, mastery, and health as appropriate

**Complexity:** M

**Replaces/extends:** Extends playCard and startTurn from Steps 5b/5d.

---

## Step 13b: Guard & Champion Targeting

**Depends on:** Step 13a (needs champion deployment and persistence)

**What:** Implement the Guard mechanic and champion-targeted attacks. (Review issue #7: split from original Step 12)

**Files to modify:**
- `lib/services/game_service.dart` -- add `attackChampion()`, update `attackPlayer()` with guard check

**Guard mechanic (in `attackPlayer`):**
- Before allowing `attackPlayer`, check if target has any champions with `hasGuard == true`
- If guard champions exist, `attackPlayer` is blocked (throws or returns error)
- Player must destroy all guard champions first via `attackChampion`

**Champion targeting (`attackChampion`):**
- `attackChampion(targetPlayerIndex, championId, amount)`:
  - Amount must be >= champion's shield value (no partial damage; mechanics doc Section 16: "you cannot chip away at a Champion")
  - Subtract champion's shield from attacker's power pool
  - Move destroyed champion to owner's discard pile
  - Excess power remains in pool for further attacks

**OpponentLosesHealthEffect and Guard (review issue #2):** Verify that `OpponentLosesHealthEffect` bypasses Guard -- it directly reduces health without checking for guard champions. This was wired in Step 10 but should have an explicit test in this step now that Guard exists.

**Acceptance criteria:**
- Unit test: attackPlayer is blocked when target has guard champions
- Unit test: attackPlayer succeeds after all guard champions are destroyed
- Unit test: attackChampion requires power >= shield (partial damage rejected)
- Unit test: destroyed champion goes to owner's discard pile
- Unit test: non-guard champions can be bypassed (attackPlayer allowed even if non-guard champions exist)
- Unit test: multiple guard champions all must be destroyed before player attack
- Unit test: `OpponentLosesHealthEffect` bypasses Guard (applies even when guard champions are in play) (review issue #2)
- Unit test: excess power after destroying a champion remains in pool

**Complexity:** M

**Replaces/extends:** Extends combat from Step 10 and champion system from Step 13a.

---

## Step 14: Placeholder (reserved)

*This step number is reserved to maintain spacing. No content.*

---

## Step 15: Win Conditions

**Depends on:** Steps 10, 12, 13b (needs combat, Infinity Shard, champion guard)

**What:** Implement game-ending conditions: elimination (last player standing) and Infinity Shard at 30+ mastery.

**Files to modify:**
- `lib/services/game_service.dart` -- add win condition checks

**Win conditions:**
1. **Elimination:** After any `attackPlayer` call or `OpponentLosesHealthEffect` resolution, check if only one player remains non-eliminated. If so, that player wins.
2. **Infinity Shard at 30+ mastery:** When `InfinityShardEffect` is resolved and player mastery is 30+, all opponents are instantly eliminated. Game over.

**Game state:**
- Add `GameStatus` enum: `inProgress`, `won`
- Add `winner` field (nullable PlayerState or index)
- All game actions check `status == inProgress` before executing

**Acceptance criteria:**
- Unit test: eliminating last opponent sets game status to `won`
- Unit test: Infinity Shard at mastery 30+ instantly wins
- Unit test: game actions are blocked after a winner is declared
- Unit test: in 3-player game, eliminating one player does not end the game
- Unit test: Infinity Shard at mastery 29: gains 1 mastery to reach 30, which DOES trigger win per timing rules (mastery gain before tier check)
- Unit test: `OpponentLosesHealthEffect` that eliminates last opponent also triggers win check

**Complexity:** M

**Replaces/extends:** Extends GameService with game-over logic.

---

## Step 16: UI Overhaul

**Depends on:** Steps 5-15 (all game logic complete)

**What:** Rewire the UI to use `GameService` instead of `DeckService`. Update the screen to show Shards of Infinity gameplay elements. This is where `DeckService` and `GainMoneyEffect` are finally retired (review issue #8).

**Files to modify:**
- `lib/ui/screens/home_screen.dart` -- rewire to GameService (or create new `game_screen.dart`)
- `lib/ui/widgets/playing_card_widget.dart` -- display faction, type, shield, guard
- `lib/main.dart` -- wire up GameService
- `test/widget_test.dart` -- rewrite to test new UI

**UI elements needed (functional, not styled):**
- Player health and mastery display
- Gem pool and power pool display
- Hand area (playable cards)
- Champions in play area
- Center row (buyable cards)
- Attack button with target selection
- End turn button
- Opponent state summary (health, mastery, guard champions)
- Banish/scrap card selection interface
- Choose-one modal/dialog for `ChooseOneEffect` cards (review issue #3)

**Files to remove:**
- `GainMoneyEffect` class (or mark deprecated now that all references are gone)
- Old `DeckService` tests (replaced by `GameService` tests covering all equivalent behavior)
- Old widget tests (replaced by new UI tests)

**Acceptance criteria:**
- Widget test: game initializes and shows player state (health 50, mastery 0)
- Widget test: playing a Crystal card updates gem pool display
- Widget test: buying a card from center row works
- Widget test: end turn advances to next player
- Widget test: attack button reduces opponent health
- All new service tests still pass
- `flutter analyze` clean

**Complexity:** L

**Replaces/extends:** Replaces old HomeScreen, DeckService, GainMoneyEffect, and widget tests entirely.

---

## Step 17: Infinity Deck Card Catalog

**Depends on:** Steps 1-15 (all mechanics must exist to define cards that use them)

**What:** Define the complete (or near-complete) Infinity Deck card catalog with all factions, costs, effects, ally abilities, mastery thresholds, and copy counts.

**Files to modify:**
- `lib/data/card_definitions.dart` -- full card catalog

**Scope:** Transcribe all cards from the mechanics doc (Section 15) into `CardModel` definitions. Assign copy counts per the distribution guidance (Section 20): 3-4 copies for 1-3 cost, 2-3 for 4-5 cost, 1-2 for 6-8 cost.

**Acceptance criteria:**
- Unit test: infinity deck has ~128 cards total
- Unit test: each faction has ~30 cards
- Unit test: all card effects are valid (no null effects, no missing fields)
- Unit test: all cards with ally abilities have a non-none faction (or `countsAsAllFactions: true`)
- Unit test: all champions have shield > 0
- Integration test: a full 2-player game can be played to completion using the real card catalog

**Complexity:** L (lots of data entry, but mechanically simple)

**Replaces/extends:** Extends the test fixture catalog from Step 4 to full coverage.

---

## Step Summary Table

| Step | Name | Depends On | Complexity | Key Files |
|------|------|-----------|-----------|-----------|
| 1 | Resource Enums & Effect Types | -- | S | `card_effect.dart`, `faction.dart`, `card_type.dart` |
| 2 | CardModel Overhaul | 1 | S | `card_model.dart` |
| 3 | Player State Model | 2 | S | `player_state.dart` |
| 4 | Starter Deck & Test Fixture Cards | 1, 2 | M | `card_definitions.dart`, `starter_deck.dart` |
| 5a | GameService Scaffold & Init | 3, 4 | S | `game_service.dart` |
| 5b | Draw & Play | 5a | M | `game_service.dart` |
| 5c | Buy & Market Integration | 5b, 6 | S | `game_service.dart` |
| 5d | End Turn & Cycling | 5b | S | `game_service.dart` |
| 6 | Market / Center Row | 1 | M | `game_service.dart`, `card_definitions.dart` |
| 7 | Mercenary Cards | 5d | S | `game_service.dart` |
| 8 | Banish & Scrap System | 5d, 6 | M | `game_service.dart` |
| 9 | Ally Abilities | 5d, 7 | M | `game_service.dart` |
| 10 | Combat System | 5d | M | `game_service.dart` |
| 11 | Mastery Threshold Effects | 5b, 9 | S | `game_service.dart` |
| 12 | Infinity Shard Scaling | 5b, 11 | M | `card_definitions.dart`, `game_service.dart` |
| 13a | Champion Deployment & Persistence | 5d, 10 | M | `game_service.dart` |
| 13b | Guard & Champion Targeting | 13a | M | `game_service.dart` |
| 15 | Win Conditions | 10, 12, 13b | M | `game_service.dart` |
| 16 | UI Overhaul | 5-15 | L | `home_screen.dart`, `playing_card_widget.dart`, `widget_test.dart` |
| 17 | Infinity Deck Card Catalog | 1-15 | L | `card_definitions.dart` |

---

## Test Migration Strategy

The current codebase has 23 tests (13 service, 10 widget). Here is how they are handled:

**Steps 1-5d (no breaking changes to old code):** All 23 existing tests continue to pass. `GainMoneyEffect` remains a real, non-deprecated class. `DeckService` is untouched. New tests are added alongside in new test files. (Review issue #8: this is a hard commitment.)

**Steps 6-15 (new mechanics, old code untouched):** All new mechanics are tested via `game_service_test.dart`. Old tests continue to pass because `DeckService` and its dependencies are never modified.

**Step 16 (UI rewrite):** Old widget tests are replaced with new ones targeting the Shards of Infinity UI. `DeckService`, `GainMoneyEffect`, and old widget tests are removed. This is the single breaking-change step for old code.

**Test file plan:**
- `test/models/card_model_test.dart` -- new (Step 2)
- `test/models/card_effect_test.dart` -- new (Step 1)
- `test/models/player_state_test.dart` -- new (Step 3)
- `test/data/card_definitions_test.dart` -- new (Step 4)
- `test/services/game_service_test.dart` -- new (Steps 5a-15, grows with each step)
- `test/services/deck_service_test.dart` -- existing, kept unchanged until Step 16
- `test/widget_test.dart` -- existing unchanged until Step 16, then rewritten

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Steps 5a-5d still too large in aggregate | Delays | Each sub-step is independently testable; can pause between sub-steps |
| Old widget tests break before Step 16 | CI failures | `GainMoneyEffect` is kept as a real class (not deprecated) through Step 16. `DeckService` is never modified. (Review issue #8) |
| Card data from mechanics doc is inaccurate | Wrong gameplay | Mark card values as "unverified" in code comments; make them easy to patch. Infinity Shard power values use configurable map. (Review issue #17) |
| Ally ability edge cases (retroactive triggers) | Bugs | Chosen behavior (no retroactive triggers) is documented and tested. Code comment cites rule source. (Review issue #10) |
| Infinity Shard timing (mastery self-trigger) | Rule ambiguity | Implement "mastery gained before threshold check" as described in mechanics doc Section 23; add a code comment noting the ambiguity |
| PRs #3/#4 merge to main and conflict | Merge conflicts | We build independently on `rld-mvp-sprint`. Our GameService supersedes both PRs' scope. Reconcile via rebase if/when they merge. (Review issue #9) |
| Champion activation timing ambiguity | Rule ambiguity | Treat champion abilities as automatic at start of turn (mechanics doc Section 23). First turn: effects during playCard. Subsequent turns: effects during startTurn. (Review issue #11) |
| GameService uses mutable state; undo/replay hard to add later | Architecture debt | Not blocking for MVP. Consider adding `toJson()`/`fromJson()` round-trip to GameState early if network play is planned. (Review issue #19) |
| `@Deprecated` annotation on `GainMoneyEffect` causes analyzer warnings | CI failures | Do NOT mark it deprecated. Keep it as a real class until Step 16 removes it entirely. (Review issue #18) |

---

## Parallel Work Opportunities

Steps that can be developed in parallel by different contributors:

- **Steps 1 + 3** can be done simultaneously (no shared files)
- **Step 6** can be started as soon as Step 1 is done (market is independent of player state)
- **Steps 8 + 10** can be done simultaneously after Step 5d (banish and combat are independent systems)
- **Steps 9 + 10** can be done simultaneously after Step 5d (ally abilities and combat are independent)
- **Step 17** (card catalog) can be started as soon as Step 2 is done (data entry only), though it cannot be fully tested until Steps 9-13b are complete

---

## Review Issue Cross-Reference

This table maps each review issue to where it is addressed in this plan:

| Review Issue | Severity | Where Addressed |
|-------------|----------|----------------|
| #1: Missing Banish/Scrap | CRITICAL | Step 1 (effect types), Step 8 (full implementation) |
| #2: Missing OpponentLosesHealthEffect | CRITICAL | Step 1 (effect type), Step 10 (combat resolution), Step 11 (mastery bonus), Step 13b (Guard bypass test) |
| #3: Missing ChooseOneEffect | HIGH | Step 1 (effect type), Step 5b (choiceIndex param), Step 9 (ally choice), Step 16 (UI modal) |
| #4: Missing conditional/scaling power | HIGH | Step 1 (ConditionalPowerEffect), Step 5b (basic evaluation) |
| #5: Missing "counts as all factions" | HIGH | Step 2 (countsAsAllFactions field), Step 4 (Universal Soldier fixture), Step 9 (ally check logic) |
| #6: Step 5 too large | HIGH | Split into Steps 5a, 5b, 5c, 5d |
| #7: Step 12 too large | HIGH | Split into Steps 13a (deployment/persistence), 13b (guard/targeting) |
| #8: DeckService survival fragile | HIGH | GainMoneyEffect kept as real class through Step 16; hard commitment documented |
| #9: Open PRs not addressed | HIGH | Open PR Decision section added at top of plan |
| #10: Ally retroactive trigger ambiguity | MEDIUM | Step 9 acceptance criteria and code comment requirement |
| #11: Champion activation timing | MEDIUM | Step 13a acceptance criteria with explicit timing tests |
| #12: Test fixture cards unspecified | MEDIUM | Step 4 now lists 17 specific cards with mechanical coverage matrix |
| #13: Eliminated player cleanup | MEDIUM | Step 10 acceptance criteria for card cleanup |
| #14: Draw timing unclear | MEDIUM | Step 5b/5d: draw at end of turn, documented with rationale |
| #15: PlayerState cleanup method | MEDIUM | Step 3: cleanupTurn() method specified |
| #16: No "always-available card" test | LOW | Step 6 acceptance criteria |
| #17: Infinity Shard values inaccurate | LOW | Step 12 implementation note: configurable map |
| #18: @Deprecated causes warnings | LOW | Step 1: do NOT mark deprecated; keep real through Step 16 |
| #19: No undo/replay consideration | LOW | Risk register entry added |

---

## Definition of Done (for the entire plan)

The implementation is complete when:

1. A 2-player game can be played from start to finish via the UI
2. All win conditions work (elimination, Infinity Shard at 30+, last player standing in 3+ player)
3. All four factions have cards with working ally abilities
4. Champions persist across turns, guard blocks direct attacks
5. Mercenaries are removed from the game after use
6. Mastery thresholds unlock bonus effects on cards
7. The center row auto-refills from the Infinity Deck
8. Banish/scrap mechanics allow deck thinning and market denial
9. OpponentLosesHealthEffect bypasses Guard
10. ChooseOneEffect presents and resolves player choices
11. Universal Soldier (countsAsAllFactions) works with all faction ally checks
12. All tests pass, `flutter analyze` is clean, CI is green
13. The app runs on web (`flutter run -d chrome`)
