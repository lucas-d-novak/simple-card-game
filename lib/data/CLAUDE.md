# lib/data

Card content and the catalog/database layer. This is where card *identity* comes
from — the legacy hardcoded catalog plus the new JSON-backed authoritative
database.

## Files

```
data/
├── card_definitions.dart   # Legacy hardcoded catalog (55 unique cards)
├── card_art_map.dart       # Card name → asset image path mapping (fallback art)
├── starter_deck.dart       # 10-card starter deck builder
├── market_deck.dart        # Build the live market + Destiny supply from the DB
├── character_relics.dart   # Character → set-aside relic options mapping
└── database/
    ├── card_database.dart        # CardDatabase + CardRecord (PURE DART — server-reusable)
    ├── card_database_asset.dart  # CardDatabaseAsset — Flutter-only rootBundle loader
    ├── card_serialization.dart   # CardModel ⇄ JSON (used by GameStateCodec)
    ├── game_state_codec.dart     # GameStateCodec — full GameService/PlayerState snapshot ⇄ JSON
    └── effect_codec.dart         # JSON ⇄ CardEffect codec (+ activated-ability codec)
```

`card_database.dart` is now **pure Dart** (no Flutter import) so the multiplayer
server can reuse it; the Flutter asset loader was split out into
`card_database_asset.dart`. `card_serialization.dart` and `game_state_codec.dart`
support the [multiplayer server](../../ai-docs/multiplayer_architecture.md):
they serialize a `CardModel` and a full `GameService` snapshot to/from JSON so
game state can be sent over the wire.

## Card database (authoritative source)

The JSON database in [`assets/card_db/`](../../assets/card_db/README.md) is the
single source of truth for card identity going forward. See its
[`README.md`](../../assets/card_db/README.md) for the data-entry workflow and
[`schema.json`](../../assets/card_db/schema.json) for the per-field contract.

### How a card flows into the game

```
cards.json ──(CardDatabase.load)──► CardRecord ──.model──► CardModel ──► GameService
                                       │
                                       └── set / copies / art / verified / group  (catalog metadata)
```

### card_database.dart

- `CardSet` — enum of expansions: `base`, `rotf`, `sos`, `ioh`, `ingeminex`,
  `promo`, `saga`, `starter`, `unknown`.
- `CardRecord` — one entry from `cards.json`. Holds the playable
  [`CardModel`](../models/CLAUDE.md) projection (`record.model`) plus
  database-only metadata: `set`, `copies`, `art`, `rawText`, `verified`, `notes`,
  the optional `group` (a non-playable, faction-like category such as `Aion`
  / `Destiny` for cards whose `model.faction` is `Faction.none`), `chapter`
  (Saga chapter 1-5, or null), and `ksOnly` (Kickstarter-exclusive flag; print
  metadata, no gameplay effect). Built from JSON via `CardRecord.fromJson`.
- `CardDatabase` — holds the parsed `List<CardRecord>`.
  - `CardDatabase.assetPath` → `'assets/card_db/cards.json'`.
  - `CardDatabase.fromJsonString(source)` — parse from a raw string (use in
    tooling / tests / the server). The core `card_database.dart` is **pure Dart**
    (no Flutter import) so the multiplayer server can reuse it.
  - `CardDatabaseAsset.load({path})` (in `card_database_asset.dart`) — async,
    loads the bundled asset via `rootBundle`; this is the Flutter-only loader,
    split out so the core stays server-reusable. Use inside the running app.
  - Accessors: `allModels` (every `CardModel`), `verifiedCards` (records where
    `verified == true`), `byId(id)`.

### market_deck.dart

Builds the game's live supplies **from the authoritative database**, not the
cost-bucket formula and not the legacy hardcoded catalog:

- `buildMarketDeckFromDatabase(db)` → `List<MarketCard>` — the center-deck
  (market) supply. **96 unique in-scope cards** (163 total copies), each carrying
  its REAL printed `copies` count from `cards.json`. Excludes starters,
  out-of-scope cards, cards with no modellable effect, and the separate Destiny /
  Aion-group supplies. Injected into `GameService` (constructor `marketDeck:`),
  which expands one card instance per copy in `_buildInfinityDeck()`.
- `buildDestinySupplyFromDatabase(db)` → `List<CardModel>` — the SEPARATE Destiny
  supply (29 cards, the `Destiny` / `DestinyDeck` groups). One copy each (unique).
  Injected via `GameService` constructor `destinySupply:`; the engine deals six
  face-up into `destinyRow` and the rest into the cascade `destinyDeck`. Never
  part of the market.

### character_relics.dart

Pure-Dart `Character → [offensive, defensive] relic ids` map
(`characterRelicIds`, `relicIdsFor(character)`) for the Relics-of-the-Future
mechanic. At Mastery 10 a player recruits ONE of their Character's two relics for
free (the other is banished); the chosen relic is shuffled into the draw pile.
Drives `PlayerState.relicOptions` / `GameService.recruitRelic`. `decima`, `tetra`,
`volos`, `koSynWu` are mapped; `rez` / `chroma` are intentionally unmapped
(no confirmed pair) and recruit to a no-op.

### effect_codec.dart

Translates the `playEffects` / `allyAbility` / `masteryBonus` JSON arrays into
[`CardEffect`](../models/CLAUDE.md) instances and back. It mirrors the effect
types in [`lib/models/card_effect.dart`](../models/card_effect.dart) and the
`type` enum documented in `schema.json`.

- `decodeEffectList(raw)` / `decodeEffect(json)` — JSON → `CardEffect`. Unknown
  or malformed effects throw `FormatException` so the validator surfaces bad data
  rather than silently dropping it.
- `encodeEffect(effect)` — `CardEffect` → JSON (round-tripping / tooling).
- `decodeActivatedAbility(raw)` / `encodeActivatedAbility(ability)` — JSON ⇄
  `ActivatedAbility` for a card's optional Exhaust-gated `activatedAbility`
  object. Returns null for an absent ability. The codec reuses the ordinary
  effect vocabulary (an activated ability is a *container* of effects, NOT a new
  effect `type`). Both `card_database.dart` (projecting `CardModel`) and
  `tool/validate_card_db.dart` call the decoder so bad data surfaces.

Supported `type` values: `gainGems`, `gainPower`, `gainMastery`, `gainHealth`,
`drawCards`, `opponentLosesHealth`, `allPlayersLoseHealth` (`amount` — every
player INCLUDING the current one loses health, bypassing shield/guard),
`banishCard` (`source`:
`hand`/`discard`/`handOrDiscard`), `scrapFromCenterRow`, `selfBanish` ("then,
banish this" — the source card removes itself; list LAST in the effect array),
`resetChampion` (deferred-selection: un-exhaust a champion you control via
`GameService.resetChampion`), `destroyChampion`
(`all`: bool — single target vs. all enemy champions), `returnFromDiscard`
(`filter`: `any`/`champion`/`mercenary`/`faction`, plus `faction` when
filtering by faction), `conditionalPower` (`condition`:
`perChampionControlled`/`perAllyPlayedThisTurn`/`perFactionPlayedThisTurn`/`perCardInDiscard`),
`scalingResource` (`resource`: `power`/`gems`/`health`/`mastery`; `condition`:
the four `conditionalPower` conditions plus `perFactionCardInDiscard`/
`perFactionChampionControlled`/`perFactionCardPlayedThisTurn`/
`perAllyWithShieldPlayedThisTurn`; optional `perN` (default 1) and `faction`),
`conditional` (`condition`: a `GameCondition` object with a `kind` (incl.
`unblockedDamageAtLeast` — `threshold` = unblocked damage dealt this turn) +
optional `threshold`/`faction`/`factions`/`parity`/`cardType`/`maxCost`/`character`;
`then`: effects resolved only when the condition holds),
`addStaticModifier` (`kind`: `shieldBuff`/`cardCostReduction`/`cannotBeAttacked`/
`recruitToTopOfDeck`; optional `amount`/`faction`/`cardType`; adds a persistent
board-wide [StaticModifier] to the player — rest-of-game lifetime),
`opponentDraws`/`opponentDiscards` (`count`: each OTHER player draws/discards N),
`copyPlayedCard` (deferred-selection: `filter` `any`/`nonChampion`; re-resolves a
played card's effects via `GameService.copyPlayedCard`; copy-cards and
`infinityShard` are excluded), `centerDeckScry` (deferred-selection: `disposition`
`acquire`/`toHandLosePowerEqualToCost`; reveals the top of the CENTER deck via
`GameService.centerDeckScryReveal`/`centerDeckScryResolve`),
`infinityShard`, `chooseOne` (`choices`: array of effect groups). `gainMoney`
is legacy and not part of the Shards of Infinity database.

`scalingResource` generalises `conditionalPower` to any resource pool;
`conditionalPower` is kept for back-compat (it still decodes to
`ConditionalPowerEffect`). `conditional` wraps any effect list behind a
board-state predicate and works in `playEffects`, `allyAbility`, `masteryBonus`,
and inside an `activatedAbility`.

### Encoding Exhaust / activated abilities

An Exhaust-gated champion ability is a top-level `activatedAbility` object on the
card (NOT an entry in the effect `type` enum). Shape:

```json
"activatedAbility": {
  "effects": [ { "type": "gainPower", "amount": 2 } ],
  "cost": { "gems": 0, "mastery": 1, "health": 0 }
}
```

- `effects` (required, non-empty) — the ordinary effect array resolved when the
  ability is used.
- `cost` (optional) — extra resources paid on top of Exhaust. Keys `gems` /
  `mastery` / `health` each default to 0; omit `cost` entirely for an
  Exhaust-only ability. Health cost may not be lethal to oneself.
- `masteryThreshold` / `masteryBonusEffects` / `masteryReplaces` (all optional,
  default null/empty/false) — optional mastery tier for the ability. When
  `masteryReplaces` is true and the owner's mastery is at/above
  `masteryThreshold`, `masteryBonusEffects` resolve INSTEAD OF `effects` (e.g.
  gian_shard_wyrm gives 2/2 normally, 5/5 at mastery 15); otherwise additively
  on top. `masteryBonusEffects`, if present, must be non-empty.

The card-level `masteryReplaces` (bool, default false) on the record controls
whether a card's `masteryBonus` replaces `playEffects` (true) or stacks on top
(false, the legacy default) at/above `masteryThreshold`.

Only champions should carry `activatedAbility`. The 24 DB cards whose `rawText`
mentions "exhaust" are the encoding targets.

## Tooling

- [`tool/validate_card_db.dart`](../../tool/validate_card_db.dart) — completeness
  + correctness checker. Run from the project root:

  ```bash
  dart run tool/validate_card_db.dart
  ```

  Reports per-card missing fields, effect-decoding errors, and verification
  status, plus a per-set completeness summary against the known physical
  composition. Exits 1 on a hard error (bad JSON, duplicate id, undecodable
  effect); soft gaps (unverified / missing optional fields) exit 0.

- [`tool/fetch_card_art.py`](../../tool/fetch_card_art.py) — fetches and crops
  card art from Tabletop Simulator spritesheet URLs, cropping each card by its
  grid position and saving to `assets/cards/<id>.jpg`. Requires Python + Pillow.
  Used to populate the `art` field; see card-list provenance in
  [`ai-docs/card_list_source_bgg.md`](../../ai-docs/card_list_source_bgg.md).

## Legacy catalog

The live `GameService` market is now built from the authoritative database via
`market_deck.dart` (`buildMarketDeckFromDatabase`). `card_definitions.dart` still
backs the legacy `DeckService` demo (`home_screen.dart`) and provides the
cost-bucket fallback deck `GameService` uses when no `marketDeck` is injected (the
legacy/test path). `starter_deck.dart` still builds every player's 10-card starting
deck. The JSON database continues to be populated incrementally.
