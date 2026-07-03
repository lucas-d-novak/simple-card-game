import 'package:simple_card_game/data/character_relics.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/ingeminex_entity.dart';

/// One unique market-deck entry: a card template plus the number of [copies] of
/// it in the center deck (the printed "rarity pip" count).
///
/// The engine expands a `List<MarketCard>` into the concrete shuffled center
/// deck — one [CardModel] instance per copy (ids suffixed `_0`, `_1`, …). This
/// is PURE DART so the client and the authoritative server build the market
/// identically.
class MarketCard {
  const MarketCard({required this.template, required this.copies});

  final CardModel template;
  final int copies;
}

/// Starter-only cards (the 10-card starting deck) — never in any supply.
const _starterIds = {
  'crystal',
  'blaster',
  'shard_reactor',
  'infinity_shard',
  'infinity_engine_fragment',
};

/// Card-database `group` values that are SEPARATE subsystems with their own
/// supplies — they must NOT be shuffled into the central market deck:
///  - `Destiny` / `DestinyDeck`: the Into-the-Horizon Destiny supply (its own
///    face-up row; claimed at Mastery 5). Built by [buildDestinySupplyFromDatabase].
///  - `Aion` / `Prism`: other expansion subsystems the engine does not yet model
///    as a playable supply; excluded so they don't pollute the center deck.
///  - `Ingeminex`: neutral co-op boss cards — they spawn as shared ownerless
///    entities (`GameService.spawnIngeminex`), never bought/recruited, so they
///    are kept out of the center deck even though they are now in-scope.
const _nonMarketGroups = {'Destiny', 'DestinyDeck', 'Aion', 'Prism', 'Ingeminex'};

/// Relic card ids (Relics of the Future). Relics are set aside beside each
/// player and recruited ONE-of-two for free at Mastery 10 — they are a separate
/// per-character supply and must NEVER be shuffled into the shared center deck.
/// Derived from [characterRelicIds] so this stays in sync with the single
/// source of truth for relic pairings.
final Set<String> _relicIds = {
  for (final pair in characterRelicIds.values) ...pair,
};

/// True when [group] denotes a Destiny card (the Into-the-Horizon supply).
bool _isDestinyGroup(String? group) =>
    group == 'Destiny' || group == 'DestinyDeck';

/// Destiny ids that are INTENTIONALLY inert but still belong in the supply.
/// `power_struggle`'s Exhaust cost ("destroy a Champion you control") is
/// unmodellable, so it carries `outOfScope: true` and empty effects — yet the
/// product owner wants it present as the 30th Destiny (it appears face-up in the
/// row and can be claimed; its ability is a safe no-op — see
/// `GameService.claimDestiny`/`useDestinyAbility`, which tolerate empty effects
/// and a null `activatedAbility`). Included here despite `outOfScope`.
const _inertDestinyIds = {'power_struggle'};

/// Build the authoritative center/market deck from a loaded [CardDatabase].
///
/// Only cards that belong in the competitive CENTER deck are included:
///  - in scope (the engine models their mechanics — excludes co-op/boss cards),
///  - have at least one play effect / activated ability (filters reference rows),
///  - are not starter-only cards (Crystal/Blaster/Shard Reactor/Infinity Shard),
///  - are not part of a SEPARATE supply ([_nonMarketGroups] — Destinies live in
///    their own row, never the market).
///
/// Each card's [MarketCard.copies] comes from the database `copies` field — the
/// real printed pip count — so the deck has authentic per-card quantities rather
/// than a cost-bucket approximation.
List<MarketCard> buildMarketDeckFromDatabase(CardDatabase db) {
  final out = <MarketCard>[];
  for (final record in db.records) {
    if (record.outOfScope) continue;
    if (_starterIds.contains(record.id)) continue;
    if (_relicIds.contains(record.id)) continue; // recruited at Mastery 10, not bought
    if (_nonMarketGroups.contains(record.group)) continue; // separate supplies
    if (record.model.playEffects.isEmpty &&
        record.model.activatedAbility == null) {
      // No modellable effect — skip rather than ship a blank card to the market.
      continue;
    }
    final copies = record.copies <= 0 ? 1 : record.copies;
    out.add(MarketCard(template: record.model, copies: copies));
  }
  return out;
}

/// Build the RELIC card lookup (id → [CardModel]) from a loaded [CardDatabase] —
/// the Relics of the Future cards named in [characterRelicIds]. Injected into
/// `GameService(relicCards:)` so each player whose Character has a relic pair
/// gets those two set aside in `PlayerState.relicOptions` at setup (recruited
/// one-of-two for free at Mastery 10). Relics are NEVER in the market
/// (see [buildMarketDeckFromDatabase]).
Map<String, CardModel> buildRelicCardsFromDatabase(CardDatabase db) {
  final out = <String, CardModel>{};
  for (final record in db.records) {
    if (_relicIds.contains(record.id)) {
      out[record.id] = record.model;
    }
  }
  return out;
}

/// Build the INGEMINEX catalog from a loaded [CardDatabase] — the six neutral
/// co-op boss cards tagged with the `Ingeminex` group. Each is turned into a
/// TEMPLATE [IngeminexEntity] carrying its `appearanceEffects` ("Attack:") and
/// `rewardEffects` ("Reward:") decoded from the record, plus its art. These are
/// NEVER in the market or any player deck (they spawn as shared neutral entities
/// via `GameService.spawnIngeminex` / `spawnIngeminexById`); this builder just
/// makes them injectable + reachable. Damage always starts at 0 on a fresh
/// entity — callers spawn a copy per appearance.
List<IngeminexEntity> buildIngeminexCatalogFromDatabase(CardDatabase db) {
  final out = <IngeminexEntity>[];
  for (final record in db.records) {
    if (record.group != 'Ingeminex') continue;
    out.add(IngeminexEntity(
      id: record.id,
      name: record.name,
      art: record.art,
      appearanceEffects: record.appearanceEffects,
      rewardEffects: record.rewardEffects,
    ));
  }
  return out;
}

/// Build the DESTINY supply from a loaded [CardDatabase] — the cards tagged with
/// the `Destiny`/`DestinyDeck` group (Into the Horizon). These are ONE physical
/// copy each (Destinies are unique), returned as templates; the engine shuffles
/// them and deals six face-up into [GameService.destinyRow], the rest into the
/// cascade [GameService.destinyDeck]. Excluded from the center deck entirely
/// (see [buildMarketDeckFromDatabase]). Includes the intentionally-inert
/// [_inertDestinyIds] (e.g. `power_struggle`) even though they are out-of-scope,
/// so the supply is the full 30 Destinies.
List<CardModel> buildDestinySupplyFromDatabase(CardDatabase db) {
  final out = <CardModel>[];
  for (final record in db.records) {
    if (!_isDestinyGroup(record.group)) continue;
    if (record.outOfScope && !_inertDestinyIds.contains(record.id)) continue;
    out.add(record.model);
  }
  return out;
}
