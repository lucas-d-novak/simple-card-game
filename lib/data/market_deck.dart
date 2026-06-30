import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/models/card_model.dart';

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
const _nonMarketGroups = {'Destiny', 'DestinyDeck', 'Aion', 'Prism'};

/// True when [group] denotes a Destiny card (the Into-the-Horizon supply).
bool _isDestinyGroup(String? group) =>
    group == 'Destiny' || group == 'DestinyDeck';

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

/// Build the DESTINY supply from a loaded [CardDatabase] — the cards tagged with
/// the `Destiny`/`DestinyDeck` group (Into the Horizon). These are ONE physical
/// copy each (Destinies are unique), returned as templates; the engine shuffles
/// them and deals six face-up into [GameService.destinyRow], the rest into the
/// cascade [GameService.destinyDeck]. Excluded from the center deck entirely
/// (see [buildMarketDeckFromDatabase]).
List<CardModel> buildDestinySupplyFromDatabase(CardDatabase db) {
  final out = <CardModel>[];
  for (final record in db.records) {
    if (record.outOfScope) continue;
    if (!_isDestinyGroup(record.group)) continue;
    out.add(record.model);
  }
  return out;
}
