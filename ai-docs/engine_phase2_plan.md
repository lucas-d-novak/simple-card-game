# Engine Phase 2 — Implementation Plan (all 13 mechanic families)

> Design produced 2026-06-29. Scope: "truly everything" — implement all mechanic
> families that the Phase-B encode loop flagged as unmodelable, including the
> novel board-state systems (characters + UI, static buffs, copy-effect,
> under-card stacking, center-deck scry, opponent draw/discard).

## Core architectural moves
1. **One generic `ConditionalEffect` wrapper** (`CardEffect` holding a
   `GameCondition` predicate + `then` effect list) instead of N conditional leaf
   types. Works uniformly in `playEffects` AND inside `activatedAbility.effects`
   (since `useActivatedAbility` calls `_resolveEffects(ability.effects,...)`).
   Covers play-history conditions (22) + mastery-gate (2b) + dormant
   character-conditionals (4).
2. **Generalize `ConditionalPowerEffect` → `ScalingResourceEffect`**
   (resource-agnostic: power/gems/health/mastery, with faction-filtered
   conditions + `perN`). Covers filtered-scaling (15).

These two cover ~42 of 66 cards.

## Constraints (every change must respect)
- `CardEffect` drives TWO exhaustive switches with no default:
  `GameService._resolveEffects` and `DeckService._applyCardEffects`. Every new
  subtype breaks compile until BOTH get a case. Codec + schema enum must update
  in lockstep.
- Deferred-selection pattern (like `BanishCardEffect`): effect is a no-op in
  `_resolveEffects`; a public `GameService` method resolves after UI/AI picks.
- `masteryReplaces` defaults to **false** — additive mastery stays the behavior
  for every existing card (back-compat).

## Build waves (dependency-ordered)

### Wave 0 — Foundations
1. `GameCondition` + `GameConditionKind` + `ConditionalEffect` wrapper;
   `_evaluateGameCondition`; `_resolveEffects` case; codec; schema; DeckService no-op.
2. `ConditionalPowerEffect` → `ScalingResourceEffect` (+ `ScalingResource`,
   extended `ScalingCondition` with faction-filtered variants). Migrate existing
   4 conditions; update codec/schema/DeckService/AiService.

### Wave 1 — Mastery replace
3. `masteryReplaces` flag (CardModel + ActivatedAbility); refactor
   `_checkMasteryBonus`/`playCard`/`activateChampion`/`useActivatedAbility`.

### Wave 2 — Self-contained leaf effects
4. `SelfBanishEffect`. 5. `ResetChampionEffect`.
6. `AllPlayersLoseHealthEffect` / `OpponentLosesHealthEffect` flags (incl-self, ignore-shield).
7. `unblockedDamageThisTurn` counter + condition kind (`blood_for_blood`).

### Wave 3 — Deferred-selection action effects
8. `RecruitFromCenterEffect` + `recruitFromCenter()`.
9. `FastPlayFromCenterEffect` + `fastPlayFromCenter()` (plain warp).
10. `ScryEffect` + `scryReveal/scryResolve` (keeper-style).

### Wave 4 — Turn-scoped matching modifiers
11. `TreatFactionAsEffect` + `factionAliasesThisTurn` + alias-aware `_factionsMatch`.
    (`spirit_leech` "ignore shield" rides the same turn-modifier slot.)

### Wave 5 — Novel board-state systems (the "truly everything" additions)
12. **Characters:** `Character` enum, `PlayerState.character`, setup-screen
    picker, AI assignment; activates `ConditionalEffect(isCharacter)` cards.
13. **Static modifiers:** `List<StaticModifier>` on PlayerState consulted by
    `attackChampion` (shield buff), `buyCard` (acquisition cost), recruit
    destination, protection (`zetta` can't-be-attacked), acquisition reductions
    (`aedifex`), recruit-placement (`maglev_tunnels`).
14. **Copy-effect:** `CopyPlayedCardEffect{filter}` deferred-selection over
    `cardsPlayedThisTurn`, re-resolves target `playEffects` (guard re-entrancy).
15. **Under-card stacking:** state for cards tucked under a champion
    (`carmine_eclipse`, `paradigm_the_archivist`, `breaker`).
16. **Center-deck reveal/repeat:** `the_shard_defiant`, `stolen_future` scry
    half — reveal from a specific deck and act on cost.
17. **Opponent draw/discard:** `OpponentDrawsEffect`/`OpponentDiscardsEffect`
    (`blitz_shard_runner`).

## Per-mechanic review gate
Each mechanic above gets a DEDICATED reviewer agent: correctness vs printed card
semantics, schema↔codec↔engine consistency, test coverage, no regression to the
263 existing tests / verified cards. A mechanic is not done until its reviewer
signs off.

## Key risks
- Exhaustive-switch compile breaks (fast-fail; checklist: add case to BOTH
  switches + codec + schema for every new type).
- `ConditionalPowerEffect`→`ScalingResourceEffect` migration breaks codec
  round-trip + card data + AiService — do atomically, keep `conditionalPower`
  decodable or migrate all call sites.
- Additive→replace mastery: default false; audit cards whose "instead" semantics
  were approximated additively (`praetorian_02`, `synthetica_artifex`, `the_voiceless`).
- Deferred-selection effects are inert in AI hands until AiService is taught.

## Test strategy
Codec round-trip + malformed-input `FormatException` per new type; per
`GameConditionKind` a met/not-met pair (incl. inside an activated ability);
scaling fixtures per faction-filtered condition + regression on the 4 migrated;
mastery replace vs additive distinguishing assertions; deferred-selection
no-op-then-method-validates tests; whole-`cards.json` decode guard.
