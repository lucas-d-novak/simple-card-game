# Engine / mechanics readability-refactor survey

READ-ONLY survey (no source changed). Scope: `lib/services/game_service.dart`
(3433 LOC), `lib/models/card_effect.dart` (1692 LOC), the codecs, `lib/services/deck_service.dart`,
and `tool/`. Goal: identify (a) dead / unreferenced functionality and (b) duplicate
logic that could be merged, as a **plan** for a future refactor — nothing here is applied.

> DRIFT WARNING: `game_service.dart` is under active mechanics waves. Every line
> number below is a snapshot (branch `rld-mvp-sprint`, 2026-07-01). Re-grep the
> symbol before touching it. Findings tagged **[DRIFT-RISK]** sit in code that is
> most likely to move.

Method for "dead": a symbol is only truly removable if it has **zero references
on any non-test path** (engine + UI + server + codec + card DB). I distinguished
three grades:
- **DEAD** — no live reference anywhere (only its own definition, or only tests).
- **ORPHANED** — implemented + tested but never wired to a live caller (UI/server/DB);
  usually future-scoped, needs an owner call, NOT a safe silent delete.
- **CONTENT-UNUSED** — fully wired in the engine switch/codec but **no card in
  `cards.json` produces it**. It is "reachable code, unreached content." Trimming
  it shrinks the vocabulary but risks pre-empting queued card work — owner decision.

---

## 1. DEAD / ORPHANED CODE (remove candidates)

### 1a. `ConditionalPowerEffect` + `PowerCondition` enum — DEAD (superseded) [owner decision]
- **Def:** `card_effect.dart:1460-1495` (`PowerCondition` enum + `ConditionalPowerEffect`).
- **Evidence:** `ScalingResourceEffect` (added later) is a strict generalisation —
  the file's own migration note (`card_effect.dart:1497-1509`) says
  "ScalingResourceEffect with resource=power + the 4 original conditions is
  behaviourally identical." Content grep: **`"type":"conditionalPower"` = 0 in
  `cards.json`**, and 0 in the legacy `card_definitions.dart`. All 23 test
  references are the only exercise. Live refs are just plumbing: the
  `effect_codec` `'conditionalPower'` case + the `_resolveEffects` case (which
  simply maps to the same power-scaling logic) + `DeckService` no-op.
- **Recommendation:** Remove `ConditionalPowerEffect`/`PowerCondition`, its codec
  case, its `_resolveEffects` case, its `DeckService` case, and migrate the 23
  tests to `ScalingResourceEffect(resource: power, …)`. **Owner call:** keep the
  `'conditionalPower'` decode case as a back-compat alias if any persisted
  snapshot / old card JSON might still carry it (server persistence). Cheapest
  safe version: delete the *type* but keep a decode-only alias that maps the JSON
  to a `ScalingResourceEffect`.
- **Blast radius:** codec tests (`effect_codec_test`, `corrected_effects_test`),
  model test (`card_effect_test`), any `game_service_test` power-scaling cases.

### 1b. Carmine on-death under-card salvage — ORPHANED (not wired) [owner decision]
- **Methods:** `recruitUnderCard(playerId, cardId)` (`game_service.dart:1894`),
  `finishUnderCardSalvage(playerId)` (`:1922`); state `pendingUnderCardRecruit`
  (`:~209`); field `CardModel.recruitUnderCardsOnDeath`.
- **Evidence:** grep shows **zero non-test callers** — not in the server protocol
  action list (`server/lib/protocol.dart` has no `recruitUnderCard` /
  `finishUnderCardSalvage` case) and not in any UI screen. Only `test/` calls them
  (6 / 3 refs). The doc comment itself says "the protocol layer will
  off-turn-authorize this later" — i.e. deliberately half-wired. One card uses the
  trigger (`recruitUnderCardsOnDeath` = carmine_eclipse, 1 hit in `cards.json`).
- **Recommendation:** Do NOT delete — it is future work, not dead. **Flag for
  owner:** either (i) finish the wiring (server action + UI picker) or (ii)
  quarantine behind a clearly-labelled "pending" section so it is not mistaken for
  live behaviour. The on-death routing (`_disposeUnderCardsOnDeath`) IS live, so
  the salvage buckets can accumulate with no way to drain them except tests.

### 1c. `_resourceGrantsOf` (static log helper) — DEAD-ish (single use, redundant with `_grantsSince`) 
- **Def:** `game_service.dart:278`. **Only caller:** `:1738` (Ingeminex reward log).
- **Evidence:** Every other play/activate/fast-play log site uses the superior
  `_grantsSince(player, gem0, …)` which measures the ACTUAL pool delta (captures
  scaling/conditional/mastery grants), whereas `_resourceGrantsOf` statically
  reads only flat `GainX` effects and "at most under-reports" (its own doc).
- **Recommendation:** At the Ingeminex reward site, snapshot the killer's pools
  before `_resolveEffects(entity.rewardEffects, killer)` and log
  `_grantsSince(killer, …)`; then delete `_resourceGrantsOf`. One reader instead
  of two. **Blast:** `action_log_extras_test`, `ingeminex_test` (assert grant
  icons on the reward line — verify amounts still match).

### 1d. `GainMoneyEffect` — DEAD in production (legacy demo only)
- **Def:** `card_effect.dart:32`. **Evidence:** produced only by `DeckService`'s
  hardcoded coin/treasure cards; `"type":"gainMoney"` never appears in `cards.json`.
  Lives and dies with the DeckService legacy island (see §3).
- **Recommendation:** Remove together with DeckService quarantine (§3).

### 1e. CONTENT-UNUSED vocabulary (handled + codec, zero card content) — owner decision, likely KEEP
These are reachable engine code with **0 occurrences in `cards.json`**. None are
"dead" by strict grep (the switch handles them), but no content exercises them, so
they are only covered by unit tests. Listed so the owner can decide "complete
vocabulary" vs. "trim":

| Symbol | Def | cards.json | Note |
|---|---|---|---|
| `ScrapFromCenterRowEffect` | `card_effect.dart:189` | 0 | Fully UI-wired (`game_screen`, `network_game_screen`) + server action — infra ready, no card uses it. |
| `ScalingCondition.perAllyPlayedThisTurn` | `card_effect.dart:1520` | 0 | Mirrors `PowerCondition`; content uses the `perFaction*` variants instead. |
| `ScalingCondition.perCardInDiscard` | `:1527` | 0 | Same. |
| `GameConditionKind.gemParityCardsPlayed` (+ `GemParity`) | `:1272` | 0 | Parity gate; no card. |
| `GameConditionKind.masteryAtLeast` | `:1285` | 0 | Note: mastery gating is normally done via `masteryThreshold`/`masteryBonus`, not this condition. |
| `ScryDisposition.drawOrBanish` | `:587` | 0 | `scry` content uses `toHand` / health-cost variants. |
| `ScryDisposition.toHandLosePowerEqualToCost` | `:600` | 0 | The CENTER-deck twin (`CenterScryDisposition.toHandLosePowerEqualToCost`) is the one used. |
| `TuckSource.centerDeck` | `:991` | 0 | Makes `_tuckTopOfCenterDeck` (`:1265`) reachable only via tests (gene_scavs is out of scope). |
| `BanishSource.playedThisTurn` | `:161` | 1 | (kept — one card) |

- **`CardModel.countsAsAllFactions`** is CONTENT-UNUSED too (`"countsAsAllFactions"`
  = 0 in `cards.json`) but has **26 engine references** (threaded through every
  faction-match call) — do NOT remove; it is architecturally load-bearing and the
  "Universal Soldier" mechanic may return via content.
- **Recommendation:** No removal without owner sign-off; these represent queued
  card designs (see `docs/card_mechanics_backlog.md`). Best action is to add a
  short "handled but no card yet" note near each, or leave as-is.

### 1f. No dead PRIVATE methods in `game_service.dart`
- Swept every `_foo(` private symbol for single-reference (definition-only) — none
  found. Every private helper has ≥1 live caller. (The public test-only methods in
  §1b are the only orphans.)

---

## 2. DUPLICATION / MERGE CLUSTERS

### 2a. Copy-effect family — `copyPlayedCard` / `_copyAllPlayedCards` / `copyUnderCards` [DRIFT-RISK]
- **Sites:** `game_service.dart:1127`, `:1176`, `:1286`.
- **Shared shape:** each iterates a set of source cards and, per card, builds a
  "copyable" effect list that **excludes `InfinityShardEffect`** (and, for
  `copyUnderCards`, also `TuckUnderChampionEffect` + `CopyUnderCardsEffect`) then
  calls `_resolveEffects(copyable, player, sourceCard: card)`. Two of the three
  also share the `_containsCopyEffect` re-entrancy guard and the same
  `filter`/`faction` gate (identical `_factionsMatch(faction, false, card.faction,
  card.countsAsAllFactions, aliasPlayer:…, extraB:…)` block, copy-pasted at `:1147`
  and `:1194`).
- **Merged abstraction:**
  ```dart
  void _replayCardEffects(PlayerState player, CardModel card,
      {Set<Type> extraExclusions = const {}}) {
    final copyable = [
      for (final e in card.playEffects)
        if (e is! InfinityShardEffect && !extraExclusions.contains(e.runtimeType)) e,
    ];
    _resolveEffects(copyable, player, sourceCard: card);
  }
  ```
  plus a `_matchesCopyFilter(card, filter, faction, player)` helper for the shared
  filter/faction gate. The three public methods keep their distinct selection /
  iteration logic but delegate the exclusion+replay+filter to the shared helpers.
- **Win:** the "never let a copy grant a shard win / never recurse" rule lives in
  ONE place. Today it is spelled out three times with subtly different exclusion
  sets — exactly the kind of drift a reader must diff by hand.
- **Verify:** `copy_centerdeck_opponent_test`, `characters_undercard_test`,
  `mastery_abilities_test`, `new_mechanics_test`.

### 2b. Fast-play sites — `fastPlayFromCenter` (free warp) vs `payAndFastPlayFromCenter` (paid mercenary) [DRIFT-RISK]
- **Sites:** `:2006` and `:2069`. Bodies are ~90% identical:
  find card in `centerRow` → remove → `playedThisTurn.add` + `cardsPlayedThisTurn.add`
  → snapshot pools → `_resolvePlayOrMastery` → `_checkAllyAbility` →
  `playedThisTurn.removeWhere(identical)` → `_disposeFastPlayedCard` →
  `_refillCenterRow` → `_log(verb, grants: _grantsSince(...))`.
- **Diffs:** the paid path charges `_discountedCost` first and requires
  `cardType == mercenary`; the free path has the `maxCost` / `alliesOnly` gates and
  a different log verb ("warped" vs "fast-played … for N gems").
- **Merged abstraction:** a private `_playFromCenterEphemeral(CardModel card,
  PlayerState player, {required String logVerb, int? price})` that does the shared
  bookkeeping; the two public methods keep only their eligibility gate + cost.
- **Win:** the tricky "stays in `cardsPlayedThisTurn` but leaves `playedThisTurn`,
  then `_disposeFastPlayedCard` decides tuck-vs-recruit-vs-remove" sequence — with
  its two big justifying comments duplicated verbatim — is written once.
- **Verify:** `new_mechanics_test`, `deferred_swyft_carmine_test`,
  `characters_undercard_test`.

### 2c. Resource-grant readers — three parallel implementations
- `resourceGrantsOf` (UI, `lib/ui/widgets/resource_grant.dart`), engine
  `_resourceGrantsOf` (`:278`), engine `_grantsSince` (`:309`).
- **Merge:** collapse the two engine readers to `_grantsSince` (see §1c). The UI
  copy is a separate layer (Flutter) and can stay, but note in a comment that the
  engine's canonical grant source is the pool-delta measurement, not the static read.

### 2d. Instance builders — `_instanceOf` vs `_relicInstanceFor`
- `_instanceOf(template, copy)` → `copyWith(id: '${id}_$copy')` (`:3353`);
  `_relicInstanceFor(template, playerId)` → `copyWith(id: '${id}_relic_$playerId')`
  (`:592`). Identical body modulo the id suffix.
- **Merge:** one `CardModel _instanceWithId(CardModel t, String idSuffix)` (or make
  `_instanceOf` take a `String suffix`). Trivial win but removes a whole duplicated
  "copyWith carries EVERY field — a manual list previously dropped fields" comment
  that must stay in sync in two places.

### 2e. Faction-match call-site boilerplate — ~20 sites
- `_factionsMatch(...)` (`:2721`) is called ~20 times; the overwhelming majority
  pass the identical trailer `aliasPlayer: player, extraB: _extraFactions(c, player)`
  (and for the "played vs source" case, also `extraA: _extraFactions(sourceCard,…)`).
  See `:772, :977, :1147, :1194, :3008, :3019, :3085, :3114, :3142, :3169, :3181, :3230`.
- **Merged abstraction:** a thin `bool _cardCountsAs(Faction want, CardModel card,
  PlayerState player)` wrapper (mirroring the SIMPLER 3-arg `_factionsMatch(want,
  card, mastery)` that already exists in `redacted_condition_evaluator.dart:104`).
  Most sites collapse to `_cardCountsAs(f, c, player)`; the handful needing `extraA`
  keep the full call.
- **Win:** biggest raw-line reduction and the biggest readability gain — the
  intent ("does this card count as faction X for this player") stops being buried
  under four keyword arguments.
- **Cross-file note:** `redacted_condition_evaluator.dart` re-implements faction
  matching (its own `_factionsMatch`, `_countPlayed`, condition evaluation) as a
  deliberate parallel over redacted client state. This is justified duplication
  (one runs on full engine state, one on the wire view) but is a maintenance pair
  — flag it so the two stay behaviourally aligned when conditions change.

### 2f. Deferred-selection method family — shared preamble (lower priority)
- ~13 public methods (`banishCard`, `destroyChampion`, `returnFromDiscard`,
  `returnFromDiscardToDeckTop`, `recruitFromCenter`, `fastPlayFromCenter`,
  `scryResolve`, `copyPlayedCard`, `tuckUnderChampion`, `resetChampion`,
  `centerDeckScryResolve`, `scrapFromCenterRow`, `payAndFastPlayFromCenter`) open
  with the same guard: `if (!_currentPlayerCanAct) return false; final player =
  currentPlayer; final index = <zone>.indexWhere((c)=>c.id==cardId); if (index==-1)
  return false;`.
- **Merge:** a small `(PlayerState, int)? _actAndLocate(List<CardModel> zone, String
  cardId)` guard helper. Modest win — the bodies diverge sharply after the
  preamble, so this is a nice-to-have, not a headline. Do it LAST.

---

## 3. LEGACY: DeckService + demo island

- **`DeckService`** (`lib/services/deck_service.dart`, 284 LOC), **`HomeScreen`**
  (`lib/ui/screens/home_screen.dart`), and **`DeckDrawApp`** (`main.dart:109`,
  labelled "Legacy demo app — kept for existing widget tests") form a
  **self-contained island**. The real app entry is
  `runApp(FragmentsOfBoundlessnessApp())` (`main.dart:40`); `DeckDrawApp`/`HomeScreen`
  are instantiated **only from `test/widget_test.dart`** (11 pumps) and
  `test/services/deck_service_test.dart`. They are NOT reachable in the shipped app.
- **Maintenance tax:** `DeckService._applyCardEffects` (`:220-270`) enumerates ALL
  37 `CardEffect` subtypes as no-ops in an exhaustive `switch` — so **every new
  effect type forces an edit here** (and the `CLAUDE.md` "Extending" note codifies
  that chore). `GainMoneyEffect` (§1d) exists solely for this island.
- **Recommendation (owner decision):** three options, safest-first —
  1. **Keep but de-tax:** replace the exhaustive no-op `switch` with
     `for (final e in card.playEffects) { if (e is DrawCardsEffect) drawCards(e.count); }`
     (drop the 35-case no-op). Removes the per-effect maintenance burden with
     near-zero risk; `deck_service_test` still passes.
  2. **Quarantine:** move `deck_service.dart` + `home_screen.dart` + `DeckDrawApp`
     under a `legacy/` folder, clearly out of the engine surface.
  3. **Delete:** remove the island + `GainMoneyEffect` + the two test files. Blast
     radius is contained (widget_test + deck_service_test only) since it is
     test-reachable-only. Confirm no golden depends on `HomeScreen`.
- **`card_definitions.dart`** (legacy 55-card catalog) still feeds (a) DeckService's
  market and (b) `GameService._buildInfinityDeck`'s **legacy fallback** (the
  cost-bucket path at `:3327`, used only when no `marketDeck` is injected — i.e.
  demo/older tests). The live game always injects `buildMarketDeckFromDatabase`, so
  the fallback + catalog are test/demo-only. Keep for now (many tests construct
  `GameService` without a deck), but note it as scope for a later "tests always
  inject a deck" cleanup.

## 4. tool/ (out of refactor blast radius, noted)
- `tool/selfplay/oracle.dart` (494 LOC) **re-implements effect semantics** (43
  effect-case references) as a DIFFERENTIAL ORACLE — an intentional second
  implementation used to catch engine bugs. Do NOT unify with the engine; that
  would defeat its purpose. Just be aware new effects need an oracle case too.
- `tool/validate_card_db.dart`, `tool/gen_coverage_readme.dart`,
  `tool/bug_pipeline/`, `tool/*.py` are dev tooling, not engine — outside the
  readability refactor.

---

## 5. Recommended execution order (safest-first) + verification

Each step is independently shippable and behaviour-preserving. Run
`flutter test` (791 + goldens) and `cd server && dart test` (64) after each.

1. **§2d instance builders** — pure rename/merge, no behaviour change. Verify:
   `market_deck_test`, `characters_undercard_test`, full suite.
2. **§1c + §2c resource-grant merge** — delete `_resourceGrantsOf`, route the
   Ingeminex site through `_grantsSince`. Verify: `action_log_extras_test`,
   `ingeminex_test` (assert reward-line grant icons unchanged).
3. **§2a copy-family unification** — extract `_replayCardEffects` +
   `_matchesCopyFilter`. Verify: `mastery_abilities_test`,
   `copy_centerdeck_opponent_test`, `characters_undercard_test`, `new_mechanics_test`.
   [DRIFT-RISK — re-grep first.]
4. **§2b fast-play unification** — extract `_playFromCenterEphemeral`. Verify:
   `new_mechanics_test`, `deferred_swyft_carmine_test`, `characters_undercard_test`.
   [DRIFT-RISK.]
5. **§2e faction-match wrapper** — add `_cardCountsAs`, migrate the ~15 simple
   sites. Verify: `game_service_test`, `conditions_glow_test`,
   `game_condition_test`, `static_modifiers_test`. (Touches many lines — do after
   the drift-prone waves settle.)
6. **§2f deferred-selection preamble helper** — optional, last.
7. **§3 DeckService** — do option (1) de-tax first (safe); options (2)/(3) only
   after owner sign-off.
8. **§1a `ConditionalPowerEffect` removal** — owner decides on the back-compat
   decode alias first, then migrate the 23 tests to `ScalingResourceEffect`.
9. **§1e content-unused trims** — only if the owner confirms the corresponding card
   designs are dropped (cross-check `docs/card_mechanics_backlog.md`). Otherwise KEEP.

## 6. Needs an OWNER decision
- **§1a** keep-or-drop the `conditionalPower` JSON decode alias (server persistence
  back-compat).
- **§1b** finish-wiring vs quarantine the Carmine salvage feature (currently a
  dead-end: buckets fill, only tests can drain them).
- **§1e** trim vs keep the content-unused vocabulary (tied to backlog card plans).
- **§3** de-tax vs quarantine vs delete the DeckService/HomeScreen legacy island.
