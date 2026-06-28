import 'package:simple_card_game/models/card_effect.dart';

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
    default:
      throw FormatException('unknown power condition: $raw');
  }
}
