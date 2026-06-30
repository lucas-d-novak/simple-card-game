# lib/services

Core game logic. Three service layers — GameService is the active engine, AiService drives AI opponents, DeckService is the legacy demo.

## Files

### game_service.dart (primary — all Shards of Infinity mechanics)

`GameService` — orchestrates the full game: multiplayer turns, effect resolution, market, combat, win conditions.

`GameService` is **pure Dart** (no Flutter imports) and is reused by the
authoritative multiplayer server in [`server/`](../../server/) — the same engine
runs the rules on both client and server. Its full state is serialized to/from
JSON by `GameStateCodec`
([`lib/data/database/game_state_codec.dart`](../data/database/game_state_codec.dart))
so a snapshot can be sent over the wire. See
[`ai-docs/multiplayer_architecture.md`](../../ai-docs/multiplayer_architecture.md).

**Constructor:** `GameService({required int playerCount, Random? random,
List<Character?>? characters, List<MarketCard>? marketDeck,
Map<String, CardModel>? relicCards, List<CardModel>? destinySupply})`

- `marketDeck` — the authoritative center-deck supply (built from the card DB by
  `buildMarketDeckFromDatabase` in [`lib/data/market_deck.dart`](../data/market_deck.dart),
  carrying each card's real printed `copies` count). When omitted, `GameService`
  falls back to the legacy cost-bucket deck over the hardcoded catalog.
- `destinySupply` — OPT-IN Destiny supply (Into the Horizon). When provided, six
  cards are dealt face-up into `destinyRow` and the rest into the cascade
  `destinyDeck`; when omitted, no Destinies are claimable.
- `relicCards` — relic card-id → `CardModel` lookup used to populate each
  player's `relicOptions` from their `Character`.

**State:**
- `players` — list of PlayerState instances
- `centerRow` — 6 visible market cards
- `infinityDeck` — remaining market cards
- `destinyRow` / `destinyDeck` — the shared Destiny supply (face-up row + cascade
  draw pile); empty unless a `destinySupply` was injected
- `removedFromGame` — banished/scrapped/mercenary cards
- `currentPlayerIndex`, `turnNumber`, `isGameOver`, `winnerId`
- `winType` — `String?`: HOW the game was won — `'mastery'` (Infinity Shard
  played at mastery 30+) or `'elimination'` (all opponents at 0 health), null
  while in progress. Set at each win site (the mastery win sets it before the
  elimination check, so an Infinity Shard win never gets mislabelled). Round-tripped
  by `GameStateCodec`, and read by the server's player-stats telemetry to stamp a
  precise `winType` on each `games` row (see `server/lib/stats_store.dart`).
- `actionLog` — `List<GameLogEntry>` (`{turn, playerId?, message}`) of public game
  events (play / recruit / attack / focus / destroy / turn change / win), appended
  by the internal `_log()` helper and bounded (oldest trimmed). Serialized by
  `GameStateCodec` and shipped (recent tail) to clients in `server/lib/views.dart`
  `redactFor` for the board's **Log** sheet.

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
| `focus()` | **Character Focus** action — spend 1 gem to gain 1 mastery, once per turn (`PlayerState.focusedThisTurn`). Returns false if already focused this turn or short on gems. |
| `claimDestiny(cardId)` | Claim a face-up Destiny from the shared `destinyRow` for the current player (FREE, at Mastery 5+). Moves it into `PlayerState.claimedDestinies`. The row is NOT auto-refilled. |
| `banishDestinyToCascade(...)` | Banish a claimed Destiny to reveal `revealCount` (default 2) cascade Destinies from `destinyDeck` face-up into `destinyRow`. |
| `useDestinyAbility(cardId)` / `canUseDestinyAbility(cardId)` | Use (or test, without mutating) a claimed Destiny's per-turn ability; tracked by `PlayerState.exhaustedDestinies`. Drives the UI Destiny tray. |
| `recruitRelic(cardId)` | At Mastery 10, recruit ONE of the Character's two set-aside `relicOptions`; the other is banished and the chosen relic is shuffled into the draw pile. |
| `conditionsSatisfied(card)` | True when a card's `ConditionalEffect` predicate currently holds for the active player. Pure read-only; drives the **conditional glow** (hand + market) in the UI. The networked board mirrors it client-side over the redacted state via `redacted_condition_evaluator.dart`. |

**Effect resolution:** `_resolveEffects()` handles all 31 CardEffect subtypes (the full Engine Phase 2 vocabulary) via exhaustive switch. Scaling/conditional effects (`ScalingResourceEffect`, the `ConditionalEffect` wrapper, and the legacy `ConditionalPowerEffect`) read per-turn state from `PlayerState.cardsPlayedThisTurn` — a list of cards played this turn, appended in `playCard()` (and `fastPlayFromCenter()`) and cleared each turn. Deferred-selection effects (banish/destroy/return/recruit/fastPlay/scry/copy/tuck/reset) resolve to a no-op here and expose a public `GameService` method the UI/AI calls after the player selects a target.

**Win conditions:**
- Elimination: all opponents health <= 0
- Infinity Shard: play at mastery >= 30 → instant win (mastery added BEFORE win check)

**Infinity Shard scaling:** +1 mastery always, then power by tier: 0-4: 0, 5-9: 3, 10-14: 6, 15-19: 10, 20-24: 15, 25-29: 20, 30+: instant win.

**Infinity deck composition:** When a `marketDeck` is injected (the live game),
each card is expanded by its REAL printed `copies` count from the card DB. The
legacy fallback (no injected deck — used by the demo / older tests) approximates
copies per card cost (1-2: 4x, 3-4: 3x, 5-6: 2x, 7-8: 1x, neutral: 3x). Built in
`_buildInfinityDeck()`.

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
