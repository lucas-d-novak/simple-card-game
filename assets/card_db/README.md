# Card Database

The **authoritative source of card info** for the game. Everything about a card —
its mechanics, set, copy count, art, and verification status — lives here.

## Files

| File | What it is |
|------|-----------|
| `cards.json` | The database. One entry per unique card. Loaded by the app. |
| `schema.json` | JSON Schema documenting every field. The contract. |
| `README.md` | This file. |

## How a card flows into the game

```
cards.json  ──(CardDatabase.load)──►  CardRecord  ──.model──►  CardModel  ──►  GameService
                                          │
                                          └── set / copies / art / verified  (catalog tooling)
```

- `lib/data/database/card_database.dart` — loads & parses `cards.json`.
- `lib/data/database/effect_codec.dart` — JSON ⇄ `CardEffect`.
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
| `chooseOne` | `choices` (array of effect groups) | player picks one group |
| `conditionalPower` | `condition` (`perChampionControlled`) | scaling power |
| `infinityShard` | — | the Infinity Shard's mastery scaling |

> The current `cards.json` holds a few **example entries** to demonstrate the
> format. Replace them with real data as you photograph cards.
