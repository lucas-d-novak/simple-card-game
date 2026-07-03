# Card Database

The **authoritative source of card info** for the game. Everything about a card —
its mechanics, set, copy count, art, and verification status — lives here.

## Files

| File | What it is |
|------|-----------|
| `cards.json` | The database. One entry per unique card. Loaded by the app. |
| `schema.json` | JSON Schema documenting every field. The contract. |
| `COVERAGE.md` | Auto-generated coverage matrix (art / effects / raw text / verified) per card, with per-set and per-faction rollups. Regenerate with `dart run tool/gen_coverage_readme.dart`. |
| `README.md` | This file. |

See also [`ai-docs/card_coverage_gaps.md`](../../ai-docs/card_coverage_gaps.md)
— the working gap list: which cards are encodable now (have raw text) vs. which
still need effect-info hunting.

## How a card flows into the game

```
cards.json  ──(CardDatabase.load)──►  CardRecord  ──.model──►  CardModel  ──►  GameService
                                          │
                                          └── set / copies / art / verified / group  (catalog tooling)
```

The DB is now the **live content source**: `lib/data/market_deck.dart` builds the
in-game market (88 unique in-scope cards, 155 total copies via real per-card
`copies`) and the SEPARATE Destiny supply (29 cards) directly from these records
and injects them into `GameService`.

- `lib/data/database/card_database.dart` — loads & parses `cards.json`.
- `lib/data/database/effect_codec.dart` — JSON ⇄ `CardEffect`.
- `lib/data/market_deck.dart` — `buildMarketDeckFromDatabase` / `buildDestinySupplyFromDatabase`.
- `tool/validate_card_db.dart` — completeness + correctness checker.

## Data-entry workflow (phone photos + OCR)

1. **Photograph** each card. Save the image to `assets/cards/<id>.jpg`, where
   `<id>` matches the card's `id` in `cards.json` (lowercase, underscores).
2. **OCR / transcribe** the card's printed text into the entry's `rawText` field
   as working notes — this is reference only, not shipped to the UI.
3. **Encode the mechanics** into structured fields (`cost`, `faction`,
   `cardType`, `playEffects`, `allyAbility`, `masteryThreshold`/`masteryBonus`,
   `shield`, `hasGuard`). Use your own effect encoding — do not paste verbatim
   card text into shipped fields.
4. Set `art` to the filename and, once you've confirmed every field against the
   physical card, set `verified: true`.
5. Run the validator to see what's left:

   ```
   dart run tool/validate_card_db.dart
   ```

   It prints per-set counts vs. the known physical composition (base 88, RotF 24,
   SoS 9, IoH 25, Ingeminex 5, Promos 5) and lists every gap (missing art,
   unverified, missing fields). **Hard errors** (bad JSON, duplicate id,
   undecodable effect) fail with exit 1; **gaps** are informational.

## The `group` field (non-playable factions)

The engine's `faction` enum only knows the four playable factions
(`homodeus`, `wraethe`, `order`, `undergrowth`) plus `none`. The source card
list also includes cards belonging to **non-playable, faction-like categories**
(e.g. `Aion`, `Destiny`, `Ingeminex`, and various boss/co-op groups). For those
cards, set `faction: "none"` and record the real category in the optional
top-level `group` string. `group` is reference/catalog metadata only — it does
not affect ally matching. Leave it absent for ordinary cards.

## `chapter` and `ksOnly` (provenance metadata)

- `chapter` (int 1–5) — the Saga chapter the card belongs to, from the BGG
  card-list ordering. Backfilled for all base-list cards.
- `ksOnly` (bool) — true for Kickstarter-edition-exclusive cards (not in the
  retail box). Print-availability only; **does not affect gameplay**. 16 cards
  are flagged per the BGG thread's confirmed list.

## Minimum entry

Only `id` is required. Everything else can be filled in incrementally:

```json
{ "id": "reactor_monk" }
```

## Full entry example

```json
{
  "id": "kor_arbiter",
  "name": "Kor Arbiter",
  "set": "base",
  "faction": "homodeus",
  "cardType": "champion",
  "cost": 2,
  "copies": 3,
  "shield": 3,
  "hasGuard": false,
  "masteryThreshold": 5,
  "playEffects": [{ "type": "gainMastery", "amount": 1 }],
  "masteryBonus": [{ "type": "gainPower", "amount": 2 }],
  "art": "kor_arbiter.jpg",
  "rawText": "(your OCR notes here)",
  "verified": true,
  "notes": ""
}
```

## Effect types

See `schema.json` `definitions.effect` for the full list. Quick reference:

| `type` | params | meaning |
|--------|--------|---------|
| `gainGems` | `amount` | gain gems |
| `gainPower` | `amount` | gain power |
| `gainMastery` | `amount` | gain mastery |
| `gainHealth` | `amount` | heal |
| `drawCards` | `count` | draw cards |
| `opponentLosesHealth` | `amount` | direct health loss (bypasses Guard) |
| `banishCard` | `source` (`hand`/`discard`/`handOrDiscard`) | banish |
| `scrapFromCenterRow` | — | remove a center-row card |
| `destroyChampion` | `all` (bool) | destroy a single chosen enemy champion (or all when `all: true`), no power cost |
| `returnFromDiscard` | `filter` (`any`/`champion`/`mercenary`/`faction`), `faction` (when filter is `faction`) | return a discard-pile card to hand |
| `chooseOne` | `choices` (array of effect groups) | player picks one group |
| `conditionalPower` | `condition` (`perChampionControlled`/`perAllyPlayedThisTurn`/`perFactionPlayedThisTurn`/`perCardInDiscard`) | scaling power (legacy) |
| `scalingResource` | `resource`, `condition`, optional `perN`/`faction` | generalises `conditionalPower` to any pool |
| `conditional` | `condition` (a `GameCondition` object), `then` | resolve effects only when a board predicate holds |
| `addStaticModifier` | `kind`, optional `amount`/`faction`/`cardType` | add a rest-of-game board modifier |
| `selfBanish` | — | the source card banishes itself (list LAST) |
| `recruitFromCenter` / `fastPlayFromCenter` | filters | recruit / fast-play a center-row card |
| `centerDeckScry` / `scry` | `disposition` | reveal & dispose top center / draw-pile cards |
| `opponentDraws` / `opponentDiscards` | `count` | each OTHER player draws / discards N |
| `infinityShard` | — | the Infinity Shard's mastery scaling |

> The list above is a subset. There are **50 `CardEffect` subtypes** in total —
> see `schema.json` `definitions.effect` and
> [`lib/data/CLAUDE.md`](../../lib/data/CLAUDE.md) for the complete `type`
> vocabulary and parameters, plus the Exhaust `activatedAbility` encoding.

> `cards.json` currently holds **183 entries**, of which **150 are in-scope** and
> **33** are out-of-scope cards flagged `outOfScope: true` (excluded from the
> verification target). The Ingeminex bosses, `power_struggle`, and the Prism
> cards Stricture / Shard Cultist were brought in-scope in Batches 13–14. **All
> 115 verified entries are in-scope** (`verified: true`); the remaining in-scope
> cards still need their fields confirmed against the physical cards before
> flipping `verified: true`. No in-scope card is left blank — every in-scope entry
> is encoded.

> **Verification status.** This block is a HISTORICAL snapshot from the
> adversarial re-check pass. Its claim that the remaining unverified cards carry
> **unmodellable** mechanics "requiring engine work, not data entry" is now
> **STALE** — the engine grew from ~14 to **50 `CardEffect` subtypes** (Phases
> 2/3 + Batches 1–14), and the examples it cited are all modelled: **variable
> shields** → `CardModel.shieldEqualsMastery` / mastery-scaled `StaticModifier` /
> `shieldPerCardUnder`; **per-resource scaling** → `ScalingResourceEffect`;
> **reveal-from-hand** → the `factionAllyPlayedOrInHand` condition. The remaining
> unverified in-scope cards now mostly need **data-entry verification against the
> physical card**, not new effect types. (A few cosmetic data gaps were also noted:
> `the_shard_defiant` / `unconditional_conscription` / `stolen_future` lack a
> `cost` field; `dash` lacks a `shield` field.) See
> [`ai-docs/engine_gaps.md`](../../ai-docs/engine_gaps.md) — itself marked
> Historical — for the original unmodelled-mechanic catalogue.
