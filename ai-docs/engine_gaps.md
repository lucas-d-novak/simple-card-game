# Engine Gaps — Unmodeled Multiplayer Card Mechanics

A catalogue of Fragments of Boundlessness card mechanics that the current engine's
`CardEffect` vocabulary **cannot express**, plus a proposed, phased plan to
extend the engine. Scope is **competitive multiplayer only** — co-op content is
out of scope (see the project's multiplayer-only memory note). **Update:** since
this catalogue was written, Destiny is now **in scope and implemented**
(Destiny supply + `claimDestiny`/`useDestinyAbility`/`banishDestinyToCascade`),
along with Character **Focus** and **Relics**; see
[`fragments_of_boundlessness_mechanics.md`](fragments_of_boundlessness_mechanics.md) §24b.

Cross-references:
- Effect model & extension recipe: [`lib/models/CLAUDE.md`](../lib/models/CLAUDE.md)
- Codec + JSON DB layer (must mirror any new effect):
  [`lib/data/CLAUDE.md`](../lib/data/CLAUDE.md)
- Source of truth for rules:
  [`ai-docs/fragments_of_boundlessness_mechanics.md`](fragments_of_boundlessness_mechanics.md)

## Current vocabulary (baseline)

`CardEffect` is a sealed hierarchy of 14 types
([`lib/models/card_effect.dart`](../lib/models/card_effect.dart)), resolved by
`GameService._resolveEffects()`
([`lib/services/game_service.dart`](../lib/services/game_service.dart)) and
mirrored by `effect_codec.dart` + the `type` enum in
[`assets/card_db/schema.json`](../assets/card_db/schema.json):

`GainGemsEffect`, `GainPowerEffect`, `GainMasteryEffect`, `GainHealthEffect`,
`GainMoneyEffect` (legacy), `DrawCardsEffect`, `OpponentLosesHealthEffect`,
`BanishCardEffect` (`BanishSource` hand/discard/handOrDiscard),
`ScrapFromCenterRowEffect`, `DestroyChampionEffect` (single target / `all`),
`ReturnFromDiscardEffect` (`ReturnFilter` any/champion/mercenary/faction),
`ChooseOneEffect`, `ConditionalPowerEffect` (`PowerCondition`:
perChampionControlled / perAllyPlayedThisTurn / perFactionPlayedThisTurn /
perCardInDiscard), `InfinityShardEffect`.

> **Status note:** this "14 types" figure is the **original baseline** when this
> catalogue was written. The sealed hierarchy has since grown to **31
> `CardEffect` types** (Phase 2 + Phase 3 — see
> [`engine_phase2_plan.md`](engine_phase2_plan.md) /
> [`engine_phase3_plan.md`](engine_phase3_plan.md)). `DestroyChampionEffect`,
> `ReturnFromDiscardEffect`, the per-turn `PowerCondition` values, the
> `PlayerState.cardsPlayedThisTurn` per-turn play history, plus Scry / static
> modifiers / under-card tucking / recruit / fast-play / center-deck scry have all
> landed — most items the phased plan below lists as future work are now
> implemented. Treat the plan as the original roadmap; cross-check against
> `card_effect.dart` for current reality.

Three structural facts that shape every gap below:

1. **Champions resolve their full `playEffects` on activation.** There is no
   separate "activated/Exhaust ability" slot, and no exhausted/tapped state —
   `activateChampion()` just gates re-use to once per turn via
   `activatedChampions`. (`game_service.dart:75-92`)
2. **No per-turn play history beyond `playedThisTurn`.** Ally checks look at
   `playedThisTurn` + `championsInPlay` for a same-faction card
   (`_checkAllyAbility` / `_hasAllyInPlay`). There is no record of *which
   factions* were played, *how many allies*, *what was revealed*, or *gems
   gained this turn* — so every "if you played another X this turn" conditional
   is currently inexpressible.
3. **`masteryBonus` only ever ADDS effects** (`_checkMasteryBonus` resolves an
   extra list). It cannot *replace* a base value ("gain X instead").

---

## 1. Catalogue (grouped, deduplicated, MP-assessed)

Frequency is a rough estimate of how many cards in the catalog appear to need
the mechanic: **common** (many), **some** (a handful), **rare** (one/few).

### A. Champion activated abilities ("Exhaust")

| # | Mechanic | Example text | MP scope | Freq |
|---|----------|--------------|----------|------|
| 1 | **Exhaust / tap activated ability** — a champion ability usable once, gated by an exhausted state separate from its on-deploy effect | "Exhaust: Gain 7 power" | **IN** — core to champions | **common** (most gap) |

The engine half-models this (once-per-turn activation), but conflates "deploy
effect" and "activated ability" into one `playEffects` list, and has no
exhausted flag distinct from `activatedChampions`. **This is a structural change,
not just a new effect type.** See §2.0.

### B. Conditional wrappers (gate an effect on game state)

| # | Mechanic | Example text | MP scope | Freq |
|---|----------|--------------|----------|------|
| 2 | **Inspire** — "…if you have a Champion in play" | "Gain 2 power; Inspire: gain 2 more" | IN | some |
| 3 | **Unify** — "…if you played/revealed another <faction> Ally this turn" | "Unify: draw a card" | IN | common |
| 4 | **Echo** — "…if there is a <faction> card in your discard pile" | "Echo: gain 1 mastery" | IN | some |
| 5 | **Dominion** — "…if you played Homodeus AND Undergrowth AND Wraethe this turn" | "Dominion: gain 6 power" | IN | rare |
| 16 | **Character-identity** — "If you are Decima/Rez/Volos…" | "If you are Rez, gain 2 power" | **OUT** — identities belong to the Aion/character variant; competitive MP here uses generic players with no identity | rare |

2-5 are the same shape: a predicate over per-turn / board state wrapping an
effect list. They differ only in the predicate. 16 is the same shape but its
predicate has no MP referent.

### C. Per-X scaling values

| # | Mechanic | Example text | MP scope | Freq |
|---|----------|--------------|----------|------|
| 13 | **Per-X scaling** — value = N × (champions in play / allies played this turn / gems gained / factions played / cards in discard) | "Gain 1 power per Champion you control" (already partly done), "Draw 1 per Ally played this turn" | IN | common |
| 15 | **Mastery-scaling** — value derived from mastery | "Gain power equal to half your mastery", "Double your power" | IN | some |
| 22 | **Variable shield** — champion shield = a game-state value | "Shield equal to your mastery" | IN | rare |

`ConditionalPowerEffect` already does the simplest case (per champion). These
generalize it: same idea (compute a number from state), but over more counters,
more resources (not just power), and including the mastery-derived family.

### D. New action effects (things the engine can't do at all)

| # | Mechanic | Example text | MP scope | Freq |
|---|----------|--------------|----------|------|
| 8 | **Return from discard to hand** (Champion / Mercenary / faction-filtered) | "Return a Champion from your discard to your hand" | IN | some |
| 9 | **Destroy enemy Champion(s)** — direct removal, not power-based combat | "Destroy target enemy Champion" / "Destroy all enemy Champions" | IN | some |
| 10 | **Recruit (free acquire)** — take a center-row card cost ≤ N for free, to discard / hand / directly into play | "Recruit a card costing 4 or less for free" | IN | some |
| 11 | **Copy an Ally / non-Champion effect** | "Copy the effect of an Ally you played this turn" | IN | rare |
| 12 | **Next recruit into play** — next <faction> Champion recruited this turn enters play directly | "Put the next Homodeus Champion you acquire this turn into play" | IN | rare |
| 17 | **Scry / dig** — reveal top N, keep one (hand / top), rest to discard | "Reveal top 2, put one in hand, discard the rest" | IN | some |
| 18 | **Banish up to N (optional, multi)** — current `BanishCardEffect` is exactly one, mandatory | "Banish up to 2 cards from your hand or discard" | IN | some |
| 19 | **Take an additional turn** (Aion extra-turn, once per game) | "Take an additional turn after this one" | **OUT** — the printed card is an Aion/character power; not in competitive MP card pool | rare |
| 23 | **chooseOne branch with no engine effect** — a branch is e.g. free-recruit, which itself isn't modeled | "Choose: gain 2 power OR recruit a card free" | IN (blocked on #10) | some |

### E. Passives / ongoing modifiers

| # | Mechanic | Example text | MP scope | Freq |
|---|----------|--------------|----------|------|
| 14 | **"can't be attacked"** — self / your other champions / by players with less mastery | "Your other Champions can't be attacked" | IN | some |
| 20 | **On-trigger return** — "When you play a Champion, return this from discard to hand" | reactive trigger from discard | IN | rare |
| 21 | **Ongoing passive power grant** — "You have 3 power" (a static pool floor, not a one-time gain) | "You have 3 power" | IN | rare |

These are **ongoing/triggered passives**, fundamentally different from the
current one-shot, resolve-and-forget effects. They require a passive/trigger
layer the engine does not have. Lower priority because most can be approximated
(#21 ≈ `GainPowerEffect` on activation; #14 needs real combat-time checks).

### F. Replacement / base-value modifiers

| # | Mechanic | Example text | MP scope | Freq |
|---|----------|--------------|----------|------|
| 7 | **"Gain X instead"** — mastery/conditional REPLACES a base value (current `masteryBonus` only adds) | "Gain 2 power; at mastery 15+, gain 5 instead" | IN | some |

### G. Faction identity

| # | Mechanic | Example text | MP scope | Freq |
|---|----------|--------------|----------|------|
| 24 | **Multi-faction but not all** — counts as a *specific subset* | "Counts as Homodeus, Wraethe and Undergrowth" | IN | rare |
| 6 | **Warp / fast-play** — "Fast-play any Ally in the Center Row for free" | (a recruit-and-play-now variant) | IN | rare |

24 needs `countsAsAllFactions` (a bool) generalized to a *set* of factions. 6 is
a sibling of #10/#12 (recruit + immediate play).

### Out-of-scope summary

- **#16 Character-identity conditionals** — no player identity in competitive MP.
- **#19 Take an additional turn** — Aion/character power, not a MP card.
- (Per the task's own framing, all co-op / Destiny / Ingeminex group cards are
  excluded; the `group` field in the DB already isolates these.)

Everything else is in scope.

---

## 2. Proposed design (highest-value items)

Three distinct extension shapes, called out explicitly:
- **(a) Structural change** — champion activated-ability model (Exhaust).
- **(b) New conditional wrapper** — one effect type that gates an inner list.
- **(c) New effect types / field additions** — concrete new `CardEffect`s.

### 2.0 Exhaust — structural change (a)

**Not** a new effect type. Split a champion's printed text into two slots and
add an exhausted state.

- **`CardModel`**: add `final List<CardEffect> activatedAbility` (default
  `const []`) alongside `playEffects`. Deploy effects stay in `playEffects`;
  "Exhaust:" abilities go in `activatedAbility`.
- **`PlayerState`**: the existing `activatedChampions` set already gates
  once-per-turn use and is cleared in `resetTurnResources()` — repurpose it as
  the **exhaust** state. Add a longer-lived set only if a card must stay
  exhausted across turns (rare).
- **`GameService.activateChampion()`**: resolve `champion.activatedAbility`
  (not `playEffects`) and mark exhausted. Deploy effects already fire in
  `playCard()` when the champion enters play, so this removes the current
  double-firing of `playEffects`.
- **Codec/schema**: `activatedAbility` is just another effect array — add it to
  `CardRecord.fromJson` / the model projection and as a sibling property of
  `playEffects` in `schema.json`. No new `type` enum entry needed.
- **UI**: `game_screen.dart` already has tap-to-activate; show an
  exhausted/greyed state when the champion is in `activatedChampions`.

> Migration note: existing champion cards put their activatable effect in
> `playEffects`. Moving it to `activatedAbility` is a data migration, but the
> field defaulting to `[]` keeps every current card compiling and passing.

### 2.1 Conditional wrapper — `ConditionalEffect` (b)

One new effect type covers Inspire / Unify / Echo / Dominion (#2-5) and the
"instead" base-value family can build on it (#7).

```dart
enum EffectCondition {
  hasChampionInPlay,        // Inspire
  playedAllyThisTurn,       // Unify (faction-filtered)
  factionCardInDiscard,     // Echo (faction-filtered)
  playedAllThreeFactions,   // Dominion
  masteryAtLeast,           // threshold (param: amount)
}

final class ConditionalEffect extends CardEffect {
  const ConditionalEffect({
    required this.condition,
    required this.effects,        // applied if condition true
    this.elseEffects = const [],  // applied if false — enables "X else Y" / "instead"
    this.faction,                 // for faction-scoped conditions
    this.amount,                  // for masteryAtLeast / counts
  });
  final EffectCondition condition;
  final List<CardEffect> effects;
  final List<CardEffect> elseEffects;
  final Faction? faction;
  final int? amount;
}
```

- **Resolution** (`_resolveEffects`): evaluate `condition` against `player` /
  board, then `_resolveEffects(effects)` or `_resolveEffects(elseEffects)`.
- **Prerequisite — per-turn history.** Add tracking to `PlayerState`:
  `Set<Faction> factionsPlayedThisTurn` and `int alliesPlayedThisTurn`, updated
  in `playCard()` (and counting `countsAsAllFactions`). `playedAllThreeFactions`
  and Unify read these; Echo reads `discardPile`; Inspire reads
  `championsInPlay`. **This is the dependency that unblocks the most cards** and
  must land first.
- **"Gain X instead" (#7)** becomes
  `ConditionalEffect(masteryAtLeast, effects:[gain5], elseEffects:[gain2])`,
  retiring the add-only limitation without changing `masteryBonus`.
- **Codec/schema**: new `type: "conditional"` with keys
  `condition`, `effects`, `elseEffects`, `faction`, `amount`.

### 2.2 Generalize scaling — extend `ConditionalPowerEffect` → `ScaledEffect` (c)

Generalize the existing per-champion power to any resource × any counter, and
fold in mastery-scaling (#13, #15).

```dart
enum ScaledResource { gems, power, mastery, health, draw }

enum ScaleCounter {
  championsInPlay,
  alliesPlayedThisTurn,
  factionsPlayedThisTurn,
  cardsInDiscard,
  masteryHalf,        // half your mastery
  masteryFull,        // equal to your mastery (also covers variable shield)
}

final class ScaledEffect extends CardEffect {
  const ScaledEffect({required this.resource, required this.counter, this.multiplier = 1});
  final ScaledResource resource;
  final ScaleCounter counter;
  final int multiplier;
}
```

- **Resolution**: compute `multiplier * counterValue(counter)`, add to the named
  pool (or draw that many).
- **Back-compat**: keep `ConditionalPowerEffect` (tests + DeckService no-op
  reference it) and optionally re-express it as
  `ScaledEffect(power, championsInPlay)`; do **not** delete it to avoid churning
  the existing exhaustive switch contract until a follow-up.
- **Variable shield (#22)** is the odd one out: shield is read at combat time
  from `CardModel.shield` (a plain `int`). A truly variable shield needs the
  shield to be computed when targeted, so defer it (Phase 4) or model as a fixed
  approximation initially.
- **Codec/schema**: `type: "scaled"` with `resource`, `counter`, `multiplier`.

### 2.3 New action effects (c)

Independent, additive `CardEffect` subclasses (each needs codec + schema enum +
a `_resolveEffects` case + usually a UI target dialog like banish/scrap):

| New type | Fields | Resolution sketch |
|----------|--------|-------------------|
| `DestroyEnemyChampionEffect` | `bool all` | Like `attackChampion` but free; if `all`, sweep every opponent's `championsInPlay` to their discard. (#9) |
| `ReturnFromDiscardEffect` | `CardType? typeFilter`, `Faction? factionFilter` | Move a matching card from `discardPile` to `hand` (target-select). (#8) |
| `RecruitEffect` | `int maxCost`, `RecruitDest dest` (discard/hand/play) | Take a center-row card with `cost <= maxCost` for free into the chosen zone; `_refillCenterRow()`. (#10, #6 warp = `dest: play`) |
| `BanishCardEffect` (extend) | add `int count`, `bool optional` | Loop selection up to `count`; optional allows zero. (#18) |
| `ScryEffect` | `int reveal`, `ScryDest dest` | Reveal top N of `drawPile`, keep one to hand/top, rest to discard. (#17) |
| `CopyEffect` | (none) | Re-resolve the `playEffects` of a chosen non-champion in `playedThisTurn`. (#11) |
| Multi-faction (extend model) | replace `countsAsAllFactions` bool semantics with `Set<Faction> countsAsFactions` (keep bool as sugar) | `_factionsMatch` checks set membership. (#24) |

### 2.4 Passives / triggers (c, deferred)

#14/#20/#21 need an ongoing **passive/trigger layer** (evaluate at combat time /
on game events) that the resolve-and-forget model lacks. Recommend a later phase:
introduce a small `passives` list on `CardModel` and hook checks into
`attackPlayer`/`attackChampion` (#14) and `playCard` (#20). #21 can be faked now
as an activated `GainPowerEffect`.

---

## 3. Phased implementation plan

Ordered by **value / risk**. Each phase is independently shippable and keeps the
exhaustive `_resolveEffects` switch + codec round-trip + schema in lockstep.

### Phase 1 — Per-turn history + Exhaust (highest value, low risk)
- Add `factionsPlayedThisTurn`, `alliesPlayedThisTurn` to `PlayerState`,
  populated in `playCard()` and cleared in `resetTurnResources()`.
- Add `activatedAbility` to `CardModel`; switch `activateChampion()` to use it;
  exhaust state via existing `activatedChampions`.
- No new effect types yet — pure structural + state plumbing.
- **Test impact:** new unit tests for the counters and for activate-vs-deploy
  separation; existing champion tests may need data updates if any relied on
  `activateChampion` re-running `playEffects`. Codec round-trip tests unaffected
  (no new `type`).

### Phase 2 — `ConditionalEffect` (unblocks Inspire/Unify/Echo/Dominion + "instead")
- Add the type, `EffectCondition` enum, resolution, codec, schema enum.
- Depends on Phase 1 counters.
- **Test impact:** one new test file for the wrapper (true/false/else branches,
  faction filtering); a codec round-trip case; schema validator passes new
  `type`. Retire add-only "instead" cards onto `elseEffects`.

### Phase 3 — `ScaledEffect` + action effects
- `ScaledEffect` (generalizes `ConditionalPowerEffect`), then
  `DestroyEnemyChampionEffect`, `ReturnFromDiscardEffect`, `RecruitEffect`,
  `BanishCardEffect` count/optional extension, `ScryEffect`. Each lands with its
  codec + schema + a UI target dialog (mirroring banish/scrap flows in
  `game_screen.dart`) + AI handling in `ai_service.dart`.
- Unblocks chooseOne free-recruit branches (#23) once `RecruitEffect` exists.
- **Test impact:** per-effect unit tests + codec round-trips; AI tests for the
  new actions; golden/widget updates for new dialogs.

### Phase 4 — Faction set, copy, next-recruit-into-play, passives
- `Set<Faction> countsAsFactions` (#24) + `_factionsMatch` update.
- `CopyEffect` (#11), next-recruit-into-play (#12) and Warp (#6) as
  state-flag mechanics on the turn.
- Passive/trigger layer for #14/#20/#21; variable shield (#22) computed at
  combat time.
- **Test impact:** broadest — touches combat, ally matching, and turn flags;
  most likely to need golden regen and AI heuristic tweaks.

### Explicitly NOT planned (out of MP scope)
- #16 character-identity conditionals.
- #19 take-an-additional-turn.
- All co-op / Destiny / Ingeminex group cards (already isolated by DB `group`).

---

## 4. Invariants to preserve when extending

- `_resolveEffects` is an **exhaustive switch** over the sealed hierarchy —
  every new `CardEffect` must add a case (and `DeckService._applyCardEffects`
  must add a no-op case to keep legacy tests compiling).
- `effect_codec.dart` must round-trip every new type (decode **and** encode),
  and the `type` enum in `schema.json` must list it — these three are a contract
  (see [`lib/data/CLAUDE.md`](../lib/data/CLAUDE.md)).
- Keep `GameService` Flutter-free (pure Dart) and `Random`-injected for
  deterministic tests.
- New target-selecting effects follow the banish/scrap pattern: the effect is a
  no-op marker in `_resolveEffects`, and the UI calls a dedicated
  `GameService` method (`banishCard`-style) to apply the player's selection.
