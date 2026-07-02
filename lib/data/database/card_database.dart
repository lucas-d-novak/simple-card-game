import 'dart:convert';

import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

/// Which expansion / set a card belongs to.
enum CardSet { base, rotf, sos, ioh, ingeminex, promo, saga, starter, unknown }

CardSet _parseSet(String? raw) {
  switch (raw) {
    case 'base':
      return CardSet.base;
    case 'rotf':
      return CardSet.rotf;
    case 'sos':
      return CardSet.sos;
    case 'ioh':
      return CardSet.ioh;
    case 'ingeminex':
      return CardSet.ingeminex;
    case 'promo':
      return CardSet.promo;
    case 'saga':
      return CardSet.saga;
    case 'starter':
      return CardSet.starter;
    default:
      return CardSet.unknown;
  }
}

Faction _parseFaction(String? raw) {
  switch (raw) {
    case 'homodeus':
      return Faction.homodeus;
    case 'wraethe':
      return Faction.wraethe;
    case 'order':
      return Faction.order;
    case 'undergrowth':
      return Faction.undergrowth;
    default:
      return Faction.none;
  }
}

CardType _parseCardType(String? raw) {
  switch (raw) {
    case 'champion':
      return CardType.champion;
    case 'mercenary':
      return CardType.mercenary;
    default:
      return CardType.regular;
  }
}

/// One record from the authoritative card database (assets/card_db/cards.json).
///
/// Carries both the playable [CardModel] projection and the database-only
/// metadata (set, copy count, art path, verification status) used for the
/// catalog tooling and incremental data entry.
class CardRecord {
  CardRecord({
    required this.id,
    required this.name,
    required this.set,
    required this.copies,
    required this.art,
    required this.rawText,
    required this.verified,
    required this.notes,
    required this.group,
    required this.chapter,
    required this.ksOnly,
    required this.outOfScope,
    required this.model,
  });

  final String id;
  final String name;
  final CardSet set;
  final int copies;
  final String? art;
  final String? rawText;
  final bool verified;
  final String? notes;

  /// Saga chapter (1-5) from the BGG card-list ordering, or null if unknown.
  final int? chapter;

  /// True if the card is Kickstarter-edition exclusive. Print metadata only.
  final bool ksOnly;

  /// True for co-op/solo boss & Shadow-Champion cards whose mechanics the
  /// competitive-multiplayer engine does not model (boss mastery pools, Ambush
  /// timing, Fate decks, detonation, champion Attack stats). Kept for reference
  /// (rawText + art) but excluded from the verification/coverage denominator.
  final bool outOfScope;

  /// Optional source-list faction-like category for cards whose [model.faction]
  /// is [Faction.none] because they belong to a non-playable group (e.g. 'Aion',
  /// 'Destiny', 'Ingeminex'). null for ordinary cards. Catalog/reference only.
  final String? group;

  /// The playable card definition projected from this record.
  final CardModel model;

  factory CardRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final name = (json['name'] as String?) ?? id;

    return CardRecord(
      id: id,
      name: name,
      set: _parseSet(json['set'] as String?),
      copies: (json['copies'] as int?) ?? 1,
      art: json['art'] as String?,
      rawText: json['rawText'] as String?,
      verified: (json['verified'] as bool?) ?? false,
      notes: json['notes'] as String?,
      group: json['group'] as String?,
      chapter: json['chapter'] as int?,
      ksOnly: (json['ksOnly'] as bool?) ?? false,
      outOfScope: (json['outOfScope'] as bool?) ?? false,
      model: CardModel(
        id: id,
        name: name,
        cost: (json['cost'] as int?) ?? 0,
        playEffects: decodeEffectList(json['playEffects']),
        faction: _parseFaction(json['faction'] as String?),
        cardType: _parseCardType(json['cardType'] as String?),
        shield: (json['shield'] as int?) ?? 0,
        shieldEqualsMastery: (json['shieldEqualsMastery'] as bool?) ?? false,
        hasGuard: (json['hasGuard'] as bool?) ?? false,
        allyAbility: decodeEffectList(json['allyAbility']),
        masteryThreshold: json['masteryThreshold'] as int?,
        masteryBonus: decodeEffectList(json['masteryBonus']),
        masteryReplaces: (json['masteryReplaces'] as bool?) ?? false,
        countsAsAllFactions: (json['countsAsAllFactions'] as bool?) ?? false,
        activatedAbility: decodeActivatedAbility(json['activatedAbility']),
        art: json['art'] as String?,
      ),
    );
  }
}

/// Loads and holds the authoritative card database.
///
/// The database is the single source of truth for card identity. The game's
/// playable catalog is derived from it via [verifiedCards] / [allModels].
class CardDatabase {
  CardDatabase(this.records);

  final List<CardRecord> records;

  /// Default location of the card database asset.
  static const String assetPath = 'assets/card_db/cards.json';

  /// Parse a database from a raw JSON string (the file contents).
  factory CardDatabase.fromJsonString(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    final cards = (data['cards'] as List<dynamic>? ?? const [])
        .map((e) => CardRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return CardDatabase(cards);
  }

  // NOTE: the Flutter-asset loader `CardDatabase.load()` lives in
  // `card_database_asset.dart` (imports package:flutter). This core file is
  // intentionally PURE DART (dart:convert only) so the authoritative
  // multiplayer server can reuse the engine — see
  // ai-docs/multiplayer_architecture.md §1. Server code calls
  // `CardDatabase.fromJsonString(File(...).readAsStringSync())`.

  /// All card models, regardless of verification status.
  List<CardModel> get allModels => [for (final r in records) r.model];

  /// Only cards a human has confirmed against the physical card.
  List<CardRecord> get verifiedCards =>
      records.where((r) => r.verified).toList();

  CardRecord? byId(String id) {
    for (final r in records) {
      if (r.id == id) return r;
    }
    return null;
  }
}
