# lib/services

Core game logic. Three service layers — GameService is the active engine, AiService drives AI opponents, DeckService is the legacy demo.

## Files

### game_service.dart (primary — all Shards of Infinity mechanics)

`GameService` — orchestrates the full game: multiplayer turns, effect resolution, market, combat, win conditions.

**Constructor:** `GameService({required int playerCount, Random? random})`

**State:**
- `players` — list of PlayerState instances
- `centerRow` — 6 visible market cards
- `infinityDeck` — remaining market cards
- `removedFromGame` — banished/scrapped/mercenary cards
- `currentPlayerIndex`, `turnNumber`, `isGameOver`, `winnerId`

**Key methods:**

| Method | What it does |
|--------|-------------|
| `playCard(cardId, {choiceIndex})` | Play from hand. Champions → championsInPlay, others → playedThisTurn. Resolves effects, checks mastery bonus, checks ally ability. |
| `playAllCards()` | Plays all hand cards left-to-right. Returns count played. |
| `buyCard(cardId)` | Buy from center row using gems. Card → discard, center row refills. |
| `endTurn()` | Discards remaining hand, cleans up played cards, resets resources, draws 5, advances turn. |
| `attackPlayer(targetId, amount)` | Spend power to deal damage. Blocked by guard champions. |
| `attackChampion(championId, targetPlayerId)` | Spend power >= shield to destroy. Champion → owner's discard. |
| `banishCard(cardId, source)` | Remove card from hand/discard permanently. |
| `scrapFromCenterRow(cardId)` | Remove from center row permanently, refill. |
| `destroyChampion(championId, targetPlayerId)` | Destroy a single chosen enemy champion with no power cost (champion → owner's discard). Fulfils a single-target `DestroyChampionEffect` after target selection; the `all` variant destroys every enemy champion inline during effect resolution. |
| `returnFromDiscard(cardId, {filter, faction})` | Return a card from the current player's discard pile to hand, validated against the `ReturnFromDiscardEffect` filter. Fulfils the effect after target selection (mirrors `banishCard`). |
| `startTurn()` | Empty — champions require manual activation via `activateChampion()`. |
| `activateChampion(championId)` | Use a champion's FREE once-per-turn play-effect activation — resolves its `playEffects`, mastery bonus, ally ability. Tracked by `PlayerState.activatedChampions`. |
| `useActivatedAbility(championId)` | Use a champion's Exhaust-gated `activatedAbility` (a SEPARATE action from `activateChampion`). Validates the champion is in play, has an ability, is not already exhausted, and the cost is payable; then pays the cost, resolves the ability effects, and marks it exhausted (`PlayerState.exhaustedChampions`). Returns false (no state change) on any failure. Exhaust clears at the owner's next turn (cleared in `resetTurnResources`). |

**Effect resolution:** `_resolveEffects()` handles all 14 CardEffect subtypes via exhaustive switch. `ConditionalPowerEffect`'s per-turn conditions (`perAllyPlayedThisTurn`, `perFactionPlayedThisTurn`) read `PlayerState.cardsPlayedThisTurn` — a per-turn list of cards played, appended in `playCard()` and cleared each turn.

**Win conditions:**
- Elimination: all opponents health <= 0
- Infinity Shard: play at mastery >= 30 → instant win (mastery added BEFORE win check)

**Infinity Shard scaling:** +1 mastery always, then power by tier: 0-4: 0, 5-9: 3, 10-14: 6, 15-19: 10, 20-24: 15, 25-29: 20, 30+: instant win.

**Infinity deck composition:** Variable copies per card cost (1-2: 4x, 3-4: 3x, 5-6: 2x, 7-8: 1x, neutral: 3x).

### ai_service.dart (AI opponent)

`AiService` — plays a full turn automatically using heuristics.

**Constructor:** `AiService({required GameService game, required String aiPlayerId})`

**Strategy:**
1. Play all hand cards (ChooseOneEffect: prefer gems if < 3, else power)
2. Activate all champions
3. Buy most expensive affordable card, repeat
4. Attack guard champions first, then weakest opponent
5. End turn

**UI integration:** `GameScreen` accepts optional `AiService?`. After human ends turn, if next player is AI, calls `takeTurn()` with 300ms phase delays.

### deck_service.dart (legacy — original demo)

`DeckService` — single-player deck demo with 6 coin cards and 5-card market. Kept intact for backward compatibility with existing widget tests. All new CardEffect subtypes are handled as no-ops in its `_applyCardEffects` switch.

## Patterns
- Constructor injection of `Random` for deterministic testing
- Unmodifiable list views via public getters
- No Flutter imports — pure Dart business logic
