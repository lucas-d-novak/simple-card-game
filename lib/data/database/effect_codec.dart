import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_type.dart';
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

/// Decodes a card's optional `activatedAbility` object into an
/// [ActivatedAbility]. Returns null when [raw] is null (the common case — most
/// cards have no activated ability).
///
/// Shape:
/// ```json
/// "activatedAbility": {
///   "effects": [ { "type": "gainPower", "amount": 2 } ],
///   "cost": { "gems": 0, "mastery": 1, "health": 0 }   // optional
/// }
/// ```
/// `effects` is required and reuses the ordinary effect vocabulary. `cost` is
/// optional; any of its `gems` / `mastery` / `health` keys default to 0
/// (an absent `cost` means Exhaust-only).
ActivatedAbility? decodeActivatedAbility(dynamic raw) {
  if (raw == null) return null;
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('activatedAbility must be a JSON object');
  }
  final effects = decodeEffectList(raw['effects']);
  if (effects.isEmpty) {
    throw const FormatException(
        'activatedAbility requires a non-empty "effects" array');
  }
  return ActivatedAbility(
    effects: effects,
    cost: _activationCost(raw['cost']),
  );
}

ActivationCost _activationCost(dynamic raw) {
  if (raw == null) return ActivationCost.none;
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('activatedAbility "cost" must be a JSON object');
  }
  return ActivationCost(
    gems: _optInt(raw, 'gems'),
    mastery: _optInt(raw, 'mastery'),
    health: _optInt(raw, 'health'),
  );
}

/// Encodes an [ActivatedAbility] back to its JSON map. Omits an all-zero cost.
Map<String, dynamic> encodeActivatedAbility(ActivatedAbility ability) {
  return {
    'effects': [for (final e in ability.effects) encodeEffect(e)],
    if (!ability.cost.isFree)
      'cost': {
        if (ability.cost.gems != 0) 'gems': ability.cost.gems,
        if (ability.cost.mastery != 0) 'mastery': ability.cost.mastery,
        if (ability.cost.health != 0) 'health': ability.cost.health,
      },
  };
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
    case 'scalingResource':
      return ScalingResourceEffect(
        resource: _scalingResource(json['resource'] as String?),
        condition: _scalingCondition(json['condition'] as String?),
        perN: json.containsKey('perN') ? _int(json, 'perN') : 1,
        faction: json['faction'] != null
            ? _faction(json['faction'] as String?)
            : null,
      );
    case 'conditional':
      final then = json['then'];
      if (then is! List) {
        throw const FormatException('conditional requires a "then" array');
      }
      return ConditionalEffect(
        condition: _gameCondition(json['condition']),
        then: decodeEffectList(then),
      );
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
    case ScalingResourceEffect():
      return {
        'type': 'scalingResource',
        'resource': effect.resource.name,
        'condition': effect.condition.name,
        if (effect.perN != 1) 'perN': effect.perN,
        if (effect.faction != null) 'faction': effect.faction!.name,
      };
    case ConditionalEffect():
      return {
        'type': 'conditional',
        'condition': _encodeGameCondition(effect.condition),
        'then': [for (final e in effect.then) encodeEffect(e)],
      };
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

/// Reads an optional integer key, defaulting to 0 when absent. Throws if present
/// but not an integer. Used for the optional fields of an [ActivationCost].
int _optInt(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v == null) return 0;
  if (v is int) return v;
  throw FormatException('activation cost "$key" must be an integer');
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

ScalingResource _scalingResource(String? raw) {
  switch (raw) {
    case 'power':
    case null:
      return ScalingResource.power;
    case 'gems':
      return ScalingResource.gems;
    case 'health':
      return ScalingResource.health;
    case 'mastery':
      return ScalingResource.mastery;
    default:
      throw FormatException('unknown scaling resource: $raw');
  }
}

ScalingCondition _scalingCondition(String? raw) {
  for (final v in ScalingCondition.values) {
    if (v.name == raw) return v;
  }
  if (raw == null) return ScalingCondition.perChampionControlled;
  throw FormatException('unknown scaling condition: $raw');
}

/// Decodes a [GameCondition] from its JSON object. The `kind` string selects the
/// predicate; remaining keys parameterise it. Unknown kind -> FormatException.
GameCondition _gameCondition(dynamic raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('conditional requires a "condition" object');
  }
  final kindStr = raw['kind'] as String?;
  GameConditionKind? kind;
  for (final v in GameConditionKind.values) {
    if (v.name == kindStr) {
      kind = v;
      break;
    }
  }
  if (kind == null) {
    throw FormatException('unknown game condition kind: $kindStr');
  }
  return GameCondition(
    kind: kind,
    threshold: raw.containsKey('threshold') ? _int(raw, 'threshold') : 1,
    faction: raw['faction'] != null ? _faction(raw['faction'] as String?) : null,
    factions: raw['factions'] is List
        ? [for (final f in raw['factions'] as List) _faction(f as String?)]
        : const [],
    parity: _gemParity(raw['parity'] as String?),
    cardType: _cardType(raw['cardType'] as String?),
    maxCost: raw['maxCost'] is int ? raw['maxCost'] as int : null,
    character: _character(raw['character'] as String?),
  );
}

Map<String, dynamic> _encodeGameCondition(GameCondition c) {
  return {
    'kind': c.kind.name,
    if (c.threshold != 1) 'threshold': c.threshold,
    if (c.faction != null) 'faction': c.faction!.name,
    if (c.factions.isNotEmpty)
      'factions': [for (final f in c.factions) f.name],
    if (c.parity != null) 'parity': c.parity!.name,
    if (c.cardType != null) 'cardType': c.cardType!.name,
    if (c.maxCost != null) 'maxCost': c.maxCost,
    if (c.character != null) 'character': c.character!.name,
  };
}

GemParity? _gemParity(String? raw) {
  switch (raw) {
    case null:
      return null;
    case 'even':
      return GemParity.even;
    case 'odd':
      return GemParity.odd;
    default:
      throw FormatException('unknown gem parity: $raw');
  }
}

CardType? _cardType(String? raw) {
  switch (raw) {
    case null:
      return null;
    case 'regular':
      return CardType.regular;
    case 'champion':
      return CardType.champion;
    case 'mercenary':
      return CardType.mercenary;
    default:
      throw FormatException('unknown card type: $raw');
  }
}

Character? _character(String? raw) {
  if (raw == null) return null;
  for (final v in Character.values) {
    if (v.name == raw) return v;
  }
  throw FormatException('unknown character: $raw');
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
