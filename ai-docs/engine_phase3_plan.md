# Engine Phase 3 — Final coverage push

Phase 2 took the `CardEffect` vocabulary from 14 → 31 subtypes and lifted
verified coverage from 19 → 63 cards. After re-encoding the 66 Phase-2 gap
cards, **22 cards remain blocked** by mechanics the vocabulary still can't
express. This document catalogues those 22 cards, groups them into the
mechanic families that unblock them, and specifies the exact engine
extension each family needs.

The goal of Phase 3 is **complete, honest coverage**: every card either fully
encoded + verified, or left partial only because a rule genuinely can't be
modelled without a much larger system (and tagged `[encode-gap]` saying so).

## Method (iteration loop)

Same loop that worked for Phase 2, per family:

1. **Design** — this doc; one section per family.
2. **Implement** — add the subtype/field, wire BOTH exhaustive switches
   (`GameService._resolveEffects` / `_resolvePlayOrMastery` and
   `DeckService._applyCardEffects`) + `effect_codec` decode/encode +
   `schema.json`.
3. **Review** — a dedicated adversarial reviewer agent per family checks
   correctness, edge cases, regressions. Fix HIGH/MED before moving on.
4. **Encode** — re-encode the family's cards from local art (ground truth:
   `assets/cards/<id>.jpg`).
5. **Verify** — confirm each encoding matches printed text; revert
   over-claims to honest partial.

Waves are ordered so shared-file edits don't collide and downstream families
build on upstream ones.

---

## Family inventory (22 cards)

### F1 — On-recruit triggers
Cards fire an effect *the moment they're recruited from the center*, before
they're ever played. `conditional`/`isCharacter` gate *play* effects only;
there's no recruit-time hook.

- **breaker** — "When you Recruit this, put it into your hand."
- **nexus_datic_hunter** — "If you are Tetra, put this into your hand when you
  Recruit it." (character-gated recruit-to-hand)

**Extension:** add `CardModel.onRecruit` (a `List<CardEffect>` resolved by
`GameService.recruitFromCenter`/`buyCard` against the recruiting player) plus a
new `RecruitToHandEffect` (move *this* card to hand instead of discard). The
character gate reuses `ConditionalEffect{isCharacter}`.

### F2 — Self-champion sacrifice as a cost
"Destroy a Champion you control to gain X" — paying with one of your own
champions. No effect models a self-sacrifice cost; we must not grant the
benefit unconditionally.

- **power_struggle** — "Exhaust: Destroy a Champion you control to gain 5 (power)."

**Extension:** `SacrificeChampionCost` on `ActivationCost` (or a
`SacrificeOwnChampionEffect` deferred-selection effect that, once a target is
chosen, removes the champion then resolves a follow-on effect list). Deferred-
selection pattern (like `BanishCardEffect`): no-op in `_resolveEffects`, a
public `GameService.resolveSacrifice(...)` finishes after UI/AI picks.

### F3 — Choose-N-distinct
`ChooseOneEffect` always picks exactly one group. Several cards (esp. at a
mastery threshold) let you pick **two distinct** options, or acquire **N** from
a scry.

- **red_fortune** — Mastery 15: "Choose two instead (distinct)."
- **stolen_future** — Mastery 10 Exhaust: "look at top 4 of Destiny Deck,
  acquire 2."
- **the_shard_defiant** — reveal top of Center Deck, "recruit OR banish it",
  repeat if you played an Aion card.

**Extension:** generalise `ChooseOneEffect` → `ChooseEffect{pick: int,
distinct: bool}` (pick defaults to 1 → backwards compatible). For scry-acquire,
extend `CenterDeckScryEffect`/`ScryEffect` with an `acquireCount` and a
per-revealed-card `recruit | banish` disposition choice.

### F4 — Opponent resource drain / target gains mastery
No effect makes an opponent *lose gems*, and none makes a *chosen* player gain
mastery.

- **wandering_ghost** — "Choose a player. That player loses 6 (gems) and gains
  3 (mastery)." (note: the *chosen* player gains the mastery)

**Extension:** `OpponentLosesGemsEffect{amount}` and a `targetGainsMastery`
flag/affected-player selector on a generalised resource-drain effect. Reuse the
existing target-selection plumbing (`attackPlayer` style).

### F5 — Odd/even gem-cost counting
`gemParityCardsPlayed` exists but is the *parity of the count of cards played*,
not "count of cards whose **cost** is odd/even".

- **advanced_weapons** — "If you played 2+ odd gem-cost cards this turn, gain 3
  (power)."
- **advanced_medicine** — "2+ even gem-cost cards this turn …"

**Extension:** add `GameConditionKind.oddCostCardsPlayed` /
`evenCostCardsPlayed` (count cards in `playedThisTurn` whose `cost` has the
given parity, compared against `threshold`).

### F6 — Banish "a card you played this turn"
`BanishSource` only covers hand / discard / handOrDiscard.

- **blood_for_blood** — banish target is "a card you played this turn".

**Extension:** add `BanishSource.playedThisTurn`.

### F7 — Faction filter on copied card
`CopyFilter` has no faction restriction.

- **taur_archpriest** — "Copy a non-Champion **Undergrowth** card you played
  this turn."

**Extension:** add an optional `Faction faction` to `CopyPlayedCardEffect` /
`CopyFilter`.

### F8 — Player-chosen treat-faction-as
`TreatFactionAsEffect` takes a *fixed* pair (from→to). One card lets the player
*choose* the from-faction.

- **isa_tel_tor_the_axe** — Mastery 20: "treat an additional faction **of your
  choice** as Wraethe."

**Extension:** allow `TreatFactionAsEffect.fromFaction == null` to mean
"player chooses", resolved via deferred selection into
`PlayerState.factionAliasesThisTurn`.

### F9 — Mastery-gated activated ability (whole-Exhaust gating)
`ActivatedAbility.masteryThreshold` only gates *bonus* effects; the *base*
Exhaust still resolves below the threshold.

- **synthesis** — "(Mastery 15), Exhaust: Draw a card." The draw must NOT be
  available below mastery 15.

**Extension:** add `ActivatedAbility.requiresMastery` (int?) that gates the
entire ability — `useActivatedAbility` refuses below it.

### F10 — On-destroy under-card disposition
Cards tucked *under* a champion need a hook for when that champion is
**destroyed** (not just self-banished).

- **paradigm_the_archivist** — "when this is destroyed, put all cards under it
  into your discard pile."

**Extension:** `CardModel.onDestroy` (`List<CardEffect>`) resolved when a
champion leaves play via destruction, plus a `ReleaseUnderCardsEffect{to:
discard}` (the engine already has `_releaseUnderCards`; expose it as an effect).

### F11 — Fast-play disposition conversion (character-gated)
"may recruit any card you fast-play" / "instead of banishing, …" — converts the
disposition of a fast-played/warped card.

- **swyft** — "If you are Rez, you may recruit any card you fast-play."
- **carmine_eclipse** — "whenever you fast-play a card, instead of banishing it,
  …"

**Extension:** a `StaticModifierKind.fastPlayDisposition` (recruit | keep)
gated by character, layered into `FastPlayFromCenterEffect`/warp resolution.

### F12 — Return-THIS-from-discard self-trigger
`returnFromDiscard` is a deferred-selection effect choosing *any* matching
discard card; one card returns *itself* conditionally.

- **se_soc_tar_the_inquisitor** — "If you played a Wraethe card this turn, you
  may return THIS from your discard to your hand."

**Extension:** `ReturnFromDiscardEffect` gains a `self: bool` flag (return the
source card specifically), wrapped in `ConditionalEffect{sameFactionPlayed}`.

### F13 — Scry disposition variant (opponents lose power)
`CenterDeckScryEffect` has no "opponents lose power instead" disposition for its
mastery variant.

- **oblivion_gatekeeper** — Mastery 20: "all opponents lose power instead."

**Extension:** add a `ScryDisposition.allOpponentsLosePower` (or fold into the
mastery-replace path with `AllPlayersLoseHealthEffect`-style targeting on
power).

---

## Residual hard gaps (likely to stay partial)

A few clauses may remain `[encode-gap]` even after Phase 3 if they require
whole subsystems (a real Destiny Deck zone, an interactive "you may" stack, the
"non-Item" subtype). Those will be documented honestly on the card rather than
faked. The bar: **never set `verified: true` on an approximated encoding.**

## Done when

- All 22 cards either fully encoded + verified, or partial with a precise
  `[encode-gap]` note naming the missing subsystem.
- `dart run tool/validate_card_db.dart` → OK, no hard errors.
- `flutter analyze` clean; `flutter test` green (incl. new per-family tests).
- `COVERAGE.md` regenerated.
