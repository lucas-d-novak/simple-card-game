# Implementation Plan Review

> Reviewer: Senior Game Developer (automated review)
> Date: 2026-06-27
> Documents reviewed: `implementation_plan.md` (v5 final), `fragments_of_boundlessness_mechanics.md`
> Codebase files reviewed: `deck_service.dart`, `card_model.dart`, `card_effect.dart`, `deck_service_test.dart`, `widget_test.dart`

---

## Executive Summary

The plan is well-structured with clear dependency ordering, sensible step sizing, and a solid test-first philosophy. However, it has several significant gaps: multiple mechanics from the source-of-truth mechanics doc are entirely absent (banish/scrap, opponent health loss effects, choose-one effects, conditional power, "counts as all factions"), the two Large steps (5 and 12) need decomposition, and the strategy of keeping DeckService alive through Step 14 is fragile given how quickly GameService will diverge. The plan should also explicitly account for open PRs #3 and #4 rather than treating them as a footnote in the risk register.

---

## Issues

### 1. CRITICAL -- Missing mechanic: Banish/Scrap effects
**Affects:** Steps 1, 5, and the entire effect resolution pipeline
**Problem:** The mechanics doc Section 24 describes a Banish/Scrap mechanic: "Some cards allow you to banish (permanently remove) a card from your hand or discard pile" and "Scrapping from the Center Row lets you deny opponents access to a card." Step 1 adds a `BanishCardEffect()` placeholder but no subsequent step ever implements it. There is no step that handles:
- Banishing a card from your own hand or discard pile (deck thinning)
- Scrapping a card from the Center Row (market denial)
- The UI for selecting which card to banish (a targeting/selection sub-system)

This is not a minor feature -- deck thinning is a core strategic mechanic in Fragments of Boundlessness. Without it, Crystal-heavy decks cannot be trimmed and the game's mid-to-late pacing breaks down.

**Suggested fix:** Add a new Step 7.5 or renumber: "Banish & Scrap System" between mercenaries and ally abilities. This step needs:
- `BanishFromHandEffect`, `BanishFromDiscardEffect`, `ScrapFromCenterRowEffect` subclasses (or a parameterized `BanishCardEffect(BanishSource source)`)
- A card-selection mechanism in GameService (player chooses which card to banish)
- Tests for: banishing from hand, banishing from discard, scrapping from center row triggers refill, banished cards go to removedFromGame, Infinity Shard cannot be banished

---

### 2. CRITICAL -- Missing mechanic: "Opponent loses health" effect (bypasses Guard)
**Affects:** Steps 1, 9, 12
**Problem:** Mechanics doc Section 24 lists "Opponent loses Health -- Direct health loss (not Power-based, bypasses Guard)" as a distinct effect type. The card list confirms this exists (e.g., Blood Ritualist: "Mastery 10+: Opponent loses 3 health" in Section 15b). The plan has no effect subclass for this and no handling in the combat system. This is mechanically distinct from `attackPlayer` because it bypasses Guard champions.

**Suggested fix:** Add `OpponentLosesHealthEffect(int amount)` to Step 1's effect list. Add resolution logic in Step 9 (combat system) or Step 10 (since the example is a mastery bonus). Add tests confirming it bypasses Guard. Also requires target selection for multiplayer (which opponent loses health?).

---

### 3. HIGH -- Missing mechanic: Choose-one effects
**Affects:** Steps 1, 5
**Problem:** Mechanics doc Section 24 lists "Choose one -- Pick one of multiple effects" and Section 15e has a concrete example: Shard Reactor (cost 3) -- "Gain 2 Gems OR Gain 2 Power (choose one)." The plan's CardEffect hierarchy has no representation for choice effects. This requires both a new effect type and a player-decision mechanism in GameService.

**Suggested fix:** Add `ChooseOneEffect(List<List<CardEffect>> choices)` to Step 1. Implement the choice resolution in Step 5 (playCard must pause for player input or accept a choice index). This interacts with the UI in Step 14 (modal to pick an option).

---

### 4. HIGH -- Missing mechanic: Conditional/scaling power effects
**Affects:** Steps 1, 5
**Problem:** Mechanics doc Section 24 lists "Conditional Power -- Power that scales based on game state" with the example "Gain 1 Power for each Champion you control." No effect subclass or resolution logic handles this. The plan only creates `InfinityShardEffect` as a special scaling effect but does not generalize the concept.

**Suggested fix:** Add a `ConditionalPowerEffect` or more general `ScalingEffect` to Step 1 with a strategy/callback pattern. Alternatively, defer to Step 15 but note in the plan that some card definitions will need a custom effect resolver.

---

### 5. HIGH -- Missing mechanic: "Counts as all factions" (Universal Soldier)
**Affects:** Steps 2, 8
**Problem:** Mechanics doc Section 15e describes Universal Soldier: "Counts as all factions for ally abilities." The current plan's faction model is a single enum value per card. There is no support for a card that satisfies ally conditions for every faction. Step 8's ally check logic (`card.faction == faction`) would fail for this card.

**Suggested fix:** Either add a `Faction.all` enum value handled specially in the ally check, or change CardModel to support `Set<Faction>` instead of a single `Faction`, or add a `bool countsAsAllFactions` field. The ally check in Step 8 must account for this. Add test: Universal Soldier satisfies ally condition for any faction card played alongside it.

---

### 6. HIGH -- Step 5 is too large and should be decomposed
**Affects:** Step 5
**Problem:** Step 5 is marked "L" and is described as "the largest single step and the architectural pivot point." It introduces GameService, multi-player state, turn lifecycle (startTurn, playCard, buyCard, endTurn), effect resolution, draw mechanics, and the DeckService migration -- all in one step. The plan's own risk register acknowledges this: "Split into 5a (scaffold + init), 5b (draw/play), 5c (buy), 5d (endTurn) if needed." This should not be "if needed" -- it should be the default.

**Suggested fix:** Split Step 5 into:
- **5a:** GameService scaffold -- constructor, `List<PlayerState>`, `currentPlayerIndex`, `turnNumber`, game initialization with starter decks. Tests: initialization state only.
- **5b:** Draw and play -- `startTurn()` (draw 5 / 3 on first turn), `playCard()` with basic effect resolution. Tests: drawing, playing cards, effect application.
- **5c:** Buy and market integration -- `buyCard()` spending gems. Tests: buying, affordability.
- **5d:** End turn and turn cycling -- `endTurn()` cleanup, player advancement, reshuffle. Tests: cleanup, turn order, resource reset.

---

### 7. HIGH -- Step 12 is too large and should be decomposed
**Affects:** Step 12
**Problem:** Step 12 combines champion deployment, champion persistence across turns, champion activation at start of turn, the Guard mechanic, and champion-targeted attacks. These are at least three distinct mechanical systems bundled into one step with 10 acceptance criteria.

**Suggested fix:** Split into:
- **12a:** Champion deployment and persistence -- playing a champion places it in championsInPlay, it survives endTurn, it activates at startTurn.
- **12b:** Guard mechanic and champion targeting -- attackPlayer checks for Guard, attackChampion method, destroyed champions go to discard.

Note: champion deployment (placing in championsInPlay) could even be moved earlier to Step 5 as part of playCard, since it's a natural extension of card type handling.

---

### 8. HIGH -- DeckService survival through Step 14 is fragile
**Affects:** Steps 5-14
**Problem:** The plan says "Keep DeckService compiling (but unused) until Step 14." However, Steps 1-4 modify shared files (`card_effect.dart`, `card_model.dart`) that DeckService depends on. Step 1 deprecates `GainMoneyEffect` and Step 5 removes it. The 10 widget tests all depend on `DeckService` via the UI, and they use `GainMoneyEffect` directly in helper functions (`gainMoneyAmount`). Once `GainMoneyEffect` is removed in Step 5, both `deck_service_test.dart` and `widget_test.dart` will break -- not at Step 14.

The plan says Step 5 will either keep `GainMoneyEffect` as a redirect to `GainGemsEffect` or migrate the old tests. But the widget tests also depend on UI elements (text like "Gain 5 money", ValueKeys like "market-card-m4") that will no longer exist once the UI is rewritten.

**Suggested fix:** Be explicit about what happens to the 23 existing tests at Step 5:
- Option A (preferred): Keep `GainMoneyEffect` as a real class (not just deprecated) that extends or wraps `GainGemsEffect`. Keep `DeckService` fully functional with its own starting deck and market. The old tests pass unchanged. This is the "parallel service" approach.
- Option B: At Step 5, migrate the 13 service tests to GameService equivalents. Mark the 10 widget tests as `skip: 'Pending UI overhaul in Step 14'`. Accept that CI will show skipped tests.
- Whichever option is chosen, document it as a hard commitment, not a "preferred/fallback."

---

### 9. HIGH -- Open PRs #3 and #4 are not adequately addressed
**Affects:** Steps 5, 6, and the entire plan
**Problem:** The repo has branches `feature/multiplayer-turn-structure` (PR #3) and `feature/market-refill-rules` (PR #4). The plan's risk register mentions PR #3 with a vague mitigation: "we can adopt PR #3's GameService concept while using our own implementation." This is not a plan -- it is handwaving. If PR #3 already implements a GameService with multiplayer turns, and PR #4 already implements market refill, the plan either:
- Duplicates that work (waste), or
- Conflicts with it (merge pain), or
- Should build on top of it (dependency)

**Suggested fix:** Before starting implementation:
1. Review PR #3 and PR #4 in detail.
2. Decide: merge them first and build on top, or explicitly supersede them (close them with a note).
3. If merging first, update Steps 5 and 6 to note which parts are already done.
4. If superseding, document why and what their code gets wrong or misses.

---

### 10. MEDIUM -- Effect resolution order: ally abilities should re-trigger earlier cards
**Affects:** Step 8
**Problem:** Step 8 states: "When a new card is played that creates an ally condition for already-played cards this turn, those earlier cards do NOT retroactively trigger." However, the mechanics doc Section 4a says ally abilities trigger "if you have played (or have in play) another card of the same faction during this turn" -- it does not explicitly say retroactive triggering is forbidden. The mechanics doc Section 18 FAQ says "playing a faction card first means subsequent cards of that faction will trigger their ally abilities" which matches the plan's interpretation. However, some implementations of Fragments of Boundlessness (including the official digital app) DO allow retroactive ally triggers when a second faction card is played. The plan should at minimum acknowledge this ambiguity and make the choice explicit with a code comment.

**Suggested fix:** Add a note to Step 8 acceptance criteria: "Test: playing card A (Homodeus) then card B (Homodeus) -- verify whether A's ally ability triggers retroactively. Document the chosen behavior in a code comment citing the rule source."

---

### 11. MEDIUM -- Champion activation timing ambiguity not resolved
**Affects:** Steps 5, 12
**Problem:** The mechanics doc Section 23 notes: "There is some ambiguity about whether Champion abilities trigger automatically at the start of your turn or whether you 'activate' them during your play phase." Step 5 says `startTurn()` will "activate champions in play (add their resources to pools)." Step 12 says champions "provide effects at start of owner's next turn." But Step 12 also says "Champion's effects trigger immediately on the turn it's played" which implies champions act like regular cards on their first turn but become start-of-turn triggers thereafter. This dual behavior is not clearly specified in the acceptance criteria.

**Suggested fix:** Add explicit acceptance criteria to Step 12:
- "Test: champion played on turn 1 provides its effects immediately during playCard."
- "Test: same champion on turn 2 provides its effects during startTurn, BEFORE any cards are played from hand."
- "Test: champion played and then another card of same faction played same turn -- champion counts as ally."

---

### 12. MEDIUM -- Card data deferred too late (Step 15)
**Affects:** Steps 4-13
**Problem:** Step 15 defers the full card catalog to after all mechanics are built. But Steps 8, 10, and 12 need representative cards from each faction with ally abilities, mastery thresholds, and guard to write meaningful tests. Step 4 says "Define at least 2-3 cards per faction" which is good, but the plan does not specify WHICH cards or ensure they cover all needed mechanical variations.

**Suggested fix:** Step 4 should explicitly list the test fixture cards it will define, ensuring coverage of:
- At least one Champion per faction (one with Guard, one without)
- At least one Mercenary
- At least one card with a mastery threshold
- At least one card with an ally ability
- At least one card with a draw effect as ally ability
- At least one card with multiple effects (e.g., "Gain 1 Gem, Gain 1 Mastery")
- The factionless cards (Shard Reactor with choose-one, Universal Soldier with all-faction)

This ensures Steps 8-12 have realistic test data without waiting for Step 15.

---

### 13. MEDIUM -- Missing: Eliminated player cleanup in multiplayer
**Affects:** Steps 9, 13
**Problem:** Mechanics doc Section 18 FAQ states: "The eliminated player removes all their cards from the game (hand, deck, discard pile, and any Champions in play)." Step 9 says "handle elimination (remove from turn order but keep their cards out of play)" which is vague. Champions of an eliminated player that are "in play" need to be explicitly removed. What about cards that were purchased by other players from the same center row -- those stay, but the eliminated player's personal cards must all be removed.

**Suggested fix:** Add acceptance criteria to Step 9 or Step 13:
- "Test: when a player is eliminated, their hand, drawPile, discardPile, and championsInPlay are all cleared."
- "Test: eliminated player's cards go to removedFromGame (not back to infinity deck)."
- "Test: other players' cards are unaffected by an elimination."

---

### 14. MEDIUM -- No "end turn draw" in cleanup
**Affects:** Step 5
**Problem:** The mechanics doc Section 4d Cleanup Phase states: "Draw 5 new cards from your personal draw pile" as part of cleanup. Step 5's `endTurn()` description says "move played regular cards to discard, remove mercenaries from game, reset gem/power pools, advance to next player" but does NOT mention drawing 5 cards. The `startTurn()` description says "draw 5 cards" but in the physical game, you draw at the END of your turn (cleanup phase), not the start of the next. This distinction matters because opponents can see your drawn hand during their turn.

**Suggested fix:** Clarify whether draw happens at end of current player's turn (matching the physical game) or start of next player's turn (functionally equivalent in 2-player but different in multiplayer for visibility). Document the choice. Either way, add an explicit acceptance criterion: "Test: after endTurn, current player has 5 cards in hand (drawn from their deck)."

---

### 15. MEDIUM -- PlayerState.playedThisTurn not cleared in Step 3
**Affects:** Steps 3, 5
**Problem:** Step 3 defines `playedThisTurn` as a field on PlayerState but does not mention a method to clear it. Step 5's `endTurn()` moves cards from playedThisTurn to discard, but Step 3's `resetTurnResources()` only "zeros gemPool and powerPool." The playedThisTurn list should also be handled during cleanup, either in resetTurnResources or via a separate method.

**Suggested fix:** Add to Step 3: a `cleanupTurn()` method that handles moving playedThisTurn to discardPile (regular cards) and returns mercenaries for removal. Or document that playedThisTurn is managed entirely by GameService.

---

### 16. LOW -- Missing acceptance criterion: "no always-available purchase card"
**Affects:** Step 6
**Problem:** Mechanics doc Section 10 explicitly states: "There is no 'always available' card (unlike some deck-builders like Star Realms)." The plan does not test for this. Since the current DeckService has a static market, it would be easy for a developer to accidentally add a permanent basic card.

**Suggested fix:** Add acceptance criterion to Step 6: "Test: when center row has fewer than 6 cards and infinity deck is empty, no replacement cards appear. There is no always-available basic card."

---

### 17. LOW -- Infinity Shard power values may be inaccurate
**Affects:** Step 11
**Problem:** The mechanics doc Section 13 explicitly warns: "The exact Power numbers at each Mastery tier above are approximate reconstructions... The specific numbers (3/6/10/15/20) may vary slightly from the printed card." Step 11 hardcodes these exact values. The plan does not acknowledge the uncertainty or provide a mechanism to update them.

**Suggested fix:** Add a comment in Step 11's implementation notes: "Power values at each tier should be verified against the physical card or official digital app. Define them as a configurable data structure (e.g., a Map<int, int> of mastery threshold to power value) rather than hardcoded conditionals."

---

### 18. LOW -- Step 1 deprecation approach may cause analyzer warnings
**Affects:** Step 1
**Problem:** Step 1 says to mark `GainMoneyEffect` with `@Deprecated` but keep it as an alias/redirect to `GainGemsEffect`. Dart's `@Deprecated` annotation will cause analyzer warnings on every existing usage (all 6 card definitions in DeckService, all test helpers). If CI enforces `flutter analyze` clean (which the plan requires), this will cause CI failures.

**Suggested fix:** Either do NOT mark it `@Deprecated` in Step 1 (just add the new classes alongside), or accept the analyzer warnings and address them in Step 5. Document which approach is chosen.

---

### 19. LOW -- No consideration for undo/replay or game state serialization
**Affects:** Overall architecture
**Problem:** The plan builds GameService as a mutable, imperative service. There is no mention of game state serialization, undo capability, or replay. While these are not required for MVP, the architectural choices made now (mutable lists, no state snapshots) will make them hard to add later. For a card game where players may want to undo or where network play requires state sync, this matters.

**Suggested fix:** Not blocking for MVP, but add a note in the risk register: "GameService uses mutable state. Adding undo/replay or network sync will require either an event-sourcing refactor or deep-copy snapshots. Consider adding a `toJson()`/`fromJson()` round-trip to GameState early."

---

## What the Plan Gets Right

1. **Dependency ordering is mostly correct.** The dependency graph is well-thought-out. Enums before models, models before player state, player state before game service, basic mechanics before advanced ones. No step references a concept introduced later (with the exception of the missing mechanics noted above).

2. **Test-first philosophy is clear and practical.** Each step has concrete acceptance criteria written as test descriptions. The test file plan in the "Test Migration Strategy" section is well-organized.

3. **Incremental complexity curve.** Starting with data models (Steps 1-4), then core loop (Step 5), then layering on mechanics (Steps 6-13), then UI (14), then full data (15) is the right order for a deck-building game engine.

4. **Random injection for deterministic testing.** The plan inherits the existing codebase's excellent pattern of injecting `Random` for reproducible tests and extends it to GameService.

5. **Parallel work opportunities are identified.** The plan correctly identifies which steps can be parallelized (1+3, 6+7, 8+9).

6. **Risk register exists and is honest.** The plan acknowledges its biggest risks (Step 5 size, card data accuracy, PR conflicts) even if the mitigations need strengthening.

7. **Mercenary lifecycle is well-specified.** Step 7 correctly handles the mercenary removal-from-game behavior, including the edge case that mercenaries count as allies during their turn of play.

8. **Mastery self-trigger timing is correct.** Step 10's resolution order (base effects including mastery gain -> threshold check -> ally check) matches the mechanics doc Section 23 exactly.

9. **Guard champion stacking is handled.** Step 12 correctly requires ALL guard champions to be destroyed before player damage, matching the mechanics doc.

10. **The plan acknowledges the mechanics doc's confidence levels.** It does not treat approximate card data as gospel.

---

## Recommended Changes Before Starting Implementation

- [ ] **Add a new step for Banish/Scrap mechanics** (Issue #1). This is a core strategic mechanic that cannot be deferred or omitted.
- [ ] **Add `OpponentLosesHealthEffect`** to Step 1's effect list and wire it into combat/mastery resolution (Issue #2).
- [ ] **Add `ChooseOneEffect`** to Step 1 and plan for player-choice resolution in GameService (Issue #3).
- [ ] **Add "counts as all factions" support** to the faction model and ally check logic (Issue #5).
- [ ] **Split Step 5** into 5a/5b/5c/5d as outlined in the risk register -- make this the default plan, not a contingency (Issue #6).
- [ ] **Split Step 12** into 12a (deployment/persistence) and 12b (guard/targeting) (Issue #7).
- [ ] **Resolve the open PR strategy**: review PRs #3 and #4, decide to merge-then-build or supersede, and update the plan accordingly (Issue #9).
- [ ] **Specify test fixture cards in Step 4**: list exactly which cards will be defined as test data, ensuring coverage of all mechanical variations needed by Steps 8-13 (Issue #12).
- [ ] **Clarify draw timing** (end of turn vs start of turn) and document the choice (Issue #14).
- [ ] **Decide on GainMoneyEffect deprecation strategy**: either keep it non-deprecated until Step 5, or accept analyzer warnings and document that choice (Issue #18).
- [ ] **Add eliminated player cleanup tests** to Step 9 or 13 (Issue #13).
- [ ] **Add conditional power / scaling effects** to the effect hierarchy or document how they will be handled in Step 15's card definitions (Issue #4).
