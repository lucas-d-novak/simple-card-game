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

/// Build the authoritative market deck from a loaded [CardDatabase].
///
/// Only cards that belong in the competitive center deck are included:
///  - in scope (the engine models their mechanics — excludes co-op/boss cards),
///  - have at least one play effect (filters out pure-reference/data rows),
///  - are not the starter-only cards (Crystal/Blaster/Shard Reactor/Infinity
///    Shard live in the starting deck, never the market).
///
/// Each card's [MarketCard.copies] comes from the database `copies` field — the
/// real printed pip count — so the deck has authentic per-card quantities rather
/// than a cost-bucket approximation.
List<MarketCard> buildMarketDeckFromDatabase(CardDatabase db) {
  const starterIds = {
    'crystal',
    'blaster',
    'shard_reactor',
    'infinity_shard',
    'infinity_engine_fragment',
  };
  final out = <MarketCard>[];
  for (final record in db.records) {
    if (record.outOfScope) continue;
    if (starterIds.contains(record.id)) continue;
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
