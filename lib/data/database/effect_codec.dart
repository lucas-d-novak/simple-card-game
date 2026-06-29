import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/faction.dart';

/// Decodes the `playEffects` / `allyAbility` / `masteryBonus` JSON arrays from
/// the card database into [CardEffect] instances. Mirrors the effect types in
/// lib/models/card_effect.dart and the `type` enum in assets/card_db/schema.json.
///
/// Unknown or malformed effects throw [FormatException] so the validator can
/// surface bad data rather than silently dropping it.
List<CardEffect> decodeEffectList(dynamic raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('effect list must be a JSON array');
  }
  return [for (final e in raw) decodeEffect(e as Map<String, dynamic>)];
}

CardEffect decodeEffect(Map<String, dynamic> json) {
  final type = json['type'] as String?;
  switch (type) {
    case 'gainGems':
      return GainGemsEffect(_int(json, 'amount'));
    case 'gainPower':
      return GainPowerEffect(_int(json, 'amount'));
    case 'gainMastery':
      return GainMasteryEffect(_int(json, 'amount'));
    case 'gainHealth':
      return GainHealthEffect(_int(json, 'amount'));
    case 'drawCards':
      return DrawCardsEffect(_int(json, 'count'));
    case 'opponentLosesHealth':
      return OpponentLosesHealthEffect(_int(json, 'amount'));
    case 'banishCard':
      return BanishCardEffect(_banishSource(json['source'] as String?));
    case 'scrapFromCenterRow':
      return const ScrapFromCenterRowEffect();
    case 'destroyChampion':
      return DestroyChampionEffect(all: (json['all'] as bool?) ?? false);
    case 'returnFromDiscard':
      final filter = _returnFilter(json['filter'] as String?);
      return ReturnFromDiscardEffect(
        filter: filter,
        faction: filter == ReturnFilter.faction
            ? _faction(json['faction'] as String?)
            : null,
      );
    case 'conditionalPower':
      return ConditionalPowerEffect(_powerCondition(json['condition'] as String?));
    case 'infinityShard':
      return const InfinityShardEffect();
    case 'chooseOne':
      final choices = json['choices'];
      if (choices is! List) {
        throw const FormatException('chooseOne requires a "choices" array');
      }
      return ChooseOneEffect([
        for (final group in choices) decodeEffectList(group),
      ]);
    default:
      throw FormatException('unknown effect type: $type');
  }
}

/// Encodes a [CardEffect] back to its JSON map (for tooling / round-tripping).
Map<String, dynamic> encodeEffect(CardEffect effect) {
  switch (effect) {
    case GainGemsEffect():
      return {'type': 'gainGems', 'amount': effect.amount};
    case GainPowerEffect():
      return {'type': 'gainPower', 'amount': effect.amount};
    case GainMasteryEffect():
      return {'type': 'gainMastery', 'amount': effect.amount};
    case GainHealthEffect():
      return {'type': 'gainHealth', 'amount': effect.amount};
    case DrawCardsEffect():
      return {'type': 'drawCards', 'count': effect.count};
    case OpponentLosesHealthEffect():
      return {'type': 'opponentLosesHealth', 'amount': effect.amount};
    case BanishCardEffect():
      return {'type': 'banishCard', 'source': effect.source.name};
    case ScrapFromCenterRowEffect():
      return {'type': 'scrapFromCenterRow'};
    case DestroyChampionEffect():
      return {'type': 'destroyChampion', 'all': effect.all};
    case ReturnFromDiscardEffect():
      return {
        'type': 'returnFromDiscard',
        'filter': effect.filter.name,
        if (effect.faction != null) 'faction': effect.faction!.name,
      };
    case ConditionalPowerEffect():
      return {'type': 'conditionalPower', 'condition': effect.condition.name};
    case InfinityShardEffect():
      return {'type': 'infinityShard'};
    case ChooseOneEffect():
      return {
        'type': 'chooseOne',
        'choices': [
          for (final group in effect.choices)
            [for (final e in group) encodeEffect(e)],
        ],
      };
    case GainMoneyEffect():
      // Legacy effect — not part of the Shards of Infinity database.
      return {'type': 'gainMoney', 'amount': effect.amount};
  }
}

int _int(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is int) return v;
  throw FormatException('effect "${json['type']}" requires integer "$key"');
}

BanishSource _banishSource(String? raw) {
  switch (raw) {
    case 'hand':
      return BanishSource.hand;
    case 'discard':
      return BanishSource.discard;
    case 'handOrDiscard':
    case null:
      return BanishSource.handOrDiscard;
    default:
      throw FormatException('unknown banish source: $raw');
  }
}

PowerCondition _powerCondition(String? raw) {
  switch (raw) {
    case 'perChampionControlled':
    case null:
      return PowerCondition.perChampionControlled;
    case 'perAllyPlayedThisTurn':
      return PowerCondition.perAllyPlayedThisTurn;
    case 'perFactionPlayedThisTurn':
      return PowerCondition.perFactionPlayedThisTurn;
    case 'perCardInDiscard':
      return PowerCondition.perCardInDiscard;
    default:
      throw FormatException('unknown power condition: $raw');
  }
}

ReturnFilter _returnFilter(String? raw) {
  switch (raw) {
    case 'any':
    case null:
      return ReturnFilter.any;
    case 'champion':
      return ReturnFilter.champion;
    case 'mercenary':
      return ReturnFilter.mercenary;
    case 'faction':
      return ReturnFilter.faction;
    default:
      throw FormatException('unknown return filter: $raw');
  }
}

Faction _faction(String? raw) {
  switch (raw) {
    case 'homodeus':
      return Faction.homodeus;
    case 'wraethe':
      return Faction.wraethe;
    case 'order':
      return Faction.order;
    case 'undergrowth':
      return Faction.undergrowth;
    case 'none':
      return Faction.none;
    default:
      throw FormatException('unknown faction: $raw');
  }
}
