// CardModel ⇄ JSON, plus enum helpers, for game-state serialization
// (multiplayer state sync / snapshots). Reuses `effect_codec` for the effect
// trees and `decodeActivatedAbility`/`encodeActivatedAbility` for the optional
// Exhaust ability.
//
// A [CardModel] is serialized by VALUE here. In a full game snapshot the
// higher-level [GameStateCodec] serializes each distinct card once into a
// "card dictionary" and references it by id elsewhere, so this by-value form is
// only emitted once per unique card — keeping payloads small while remaining
// faithful to synthetic starter-deck cards (e.g. `p0_crystal_3`) that are NOT
// in the authoritative CardDatabase and cannot be rehydrated from id alone.

import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

Faction factionFromName(String? name) {
  for (final f in Faction.values) {
    if (f.name == name) return f;
  }
  return Faction.none;
}

CardType cardTypeFromName(String? name) {
  for (final t in CardType.values) {
    if (t.name == name) return t;
  }
  return CardType.regular;
}

Character? characterFromName(String? name) {
  if (name == null) return null;
  for (final c in Character.values) {
    if (c.name == name) return c;
  }
  return null;
}

/// Serialize a [CardModel] to JSON (by value). Inverse of [cardModelFromJson].
Map<String, dynamic> cardModelToJson(CardModel c) {
  return {
    'id': c.id,
    'name': c.name,
    'cost': c.cost,
    if (c.playEffects.isNotEmpty)
      'playEffects': [for (final e in c.playEffects) encodeEffect(e)],
    if (c.faction != Faction.none) 'faction': c.faction.name,
    if (c.cardType != CardType.regular) 'cardType': c.cardType.name,
    if (c.shield != 0) 'shield': c.shield,
    if (c.hasGuard) 'hasGuard': true,
    if (c.allyAbility.isNotEmpty)
      'allyAbility': [for (final e in c.allyAbility) encodeEffect(e)],
    if (c.masteryThreshold != null) 'masteryThreshold': c.masteryThreshold,
    if (c.masteryBonus.isNotEmpty)
      'masteryBonus': [for (final e in c.masteryBonus) encodeEffect(e)],
    if (c.masteryReplaces) 'masteryReplaces': true,
    if (c.countsAsAllFactions) 'countsAsAllFactions': true,
    if (c.activatedAbility != null)
      'activatedAbility': encodeActivatedAbility(c.activatedAbility!),
    if (c.art != null) 'art': c.art,
  };
}

/// Rehydrate a [CardModel] from JSON produced by [cardModelToJson].
CardModel cardModelFromJson(Map<String, dynamic> json) {
  return CardModel(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? (json['id'] as String),
    cost: (json['cost'] as int?) ?? 0,
    playEffects: decodeEffectList(json['playEffects']),
    faction: factionFromName(json['faction'] as String?),
    cardType: cardTypeFromName(json['cardType'] as String?),
    shield: (json['shield'] as int?) ?? 0,
    hasGuard: (json['hasGuard'] as bool?) ?? false,
    allyAbility: decodeEffectList(json['allyAbility']),
    masteryThreshold: json['masteryThreshold'] as int?,
    masteryBonus: decodeEffectList(json['masteryBonus']),
    masteryReplaces: (json['masteryReplaces'] as bool?) ?? false,
    countsAsAllFactions: (json['countsAsAllFactions'] as bool?) ?? false,
    activatedAbility: decodeActivatedAbility(json['activatedAbility']),
    art: json['art'] as String?,
  );
}
