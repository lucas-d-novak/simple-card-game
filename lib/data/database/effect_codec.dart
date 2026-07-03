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
///
/// Optional mastery scaling (all absent by default): `masteryThreshold` (int),
/// `masteryBonusEffects` (effect array) and `masteryReplaces` (bool). When
/// `masteryReplaces` is true and the threshold is met, the bonus effects
/// resolve INSTEAD OF `effects`; otherwise additively. `masteryBonusEffects`,
/// if present, must be a non-empty array.
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
  final masteryBonusEffects = decodeEffectList(raw['masteryBonusEffects']);
  if (raw.containsKey('masteryBonusEffects') && masteryBonusEffects.isEmpty) {
    throw const FormatException(
        'activatedAbility "masteryBonusEffects" must be a non-empty array');
  }
  return ActivatedAbility(
    effects: effects,
    cost: _activationCost(raw['cost']),
    masteryThreshold: _optNullInt(raw, 'masteryThreshold'),
    masteryBonusEffects: masteryBonusEffects,
    replaces: (raw['masteryReplaces'] as bool?) ?? false,
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

/// Encodes an [ActivatedAbility] back to its JSON map. Omits an all-zero cost
/// and omits the mastery fields when the ability has no mastery threshold.
Map<String, dynamic> encodeActivatedAbility(ActivatedAbility ability) {
  return {
    'effects': [for (final e in ability.effects) encodeEffect(e)],
    if (!ability.cost.isFree)
      'cost': {
        if (ability.cost.gems != 0) 'gems': ability.cost.gems,
        if (ability.cost.mastery != 0) 'mastery': ability.cost.mastery,
        if (ability.cost.health != 0) 'health': ability.cost.health,
      },
    if (ability.masteryThreshold != null)
      'masteryThreshold': ability.masteryThreshold,
    if (ability.masteryBonusEffects.isNotEmpty)
      'masteryBonusEffects': [
        for (final e in ability.masteryBonusEffects) encodeEffect(e),
      ],
    if (ability.replaces) 'masteryReplaces': ability.replaces,
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
    case 'opponentLosesMastery':
      return OpponentLosesMasteryEffect(_int(json, 'amount'));
    case 'allPlayersLoseHealth':
      return AllPlayersLoseHealthEffect(_int(json, 'amount'));
    case 'banishRandomFromEachHand':
      return const BanishRandomFromEachHandEffect();
    case 'allPlayersDiscard':
      return AllPlayersDiscardEffect(_int(json, 'count'));
    case 'allPlayersDestroyHighestChampion':
      return const AllPlayersDestroyHighestChampionEffect();
    case 'grantExtraDestinyClaim':
      return GrantExtraDestinyClaimEffect(
          json.containsKey('count') ? _int(json, 'count') : 1);
    case 'recruitRelicToHand':
      return const RecruitRelicToHandEffect();
    case 'banishUpToFromAnyZone':
      return BanishUpToFromAnyZoneEffect(_int(json, 'count'));
    case 'banishCard':
      return BanishCardEffect(_banishSource(json['source'] as String?));
    case 'scrapFromCenterRow':
      return const ScrapFromCenterRowEffect();
    case 'selfBanish':
      return const SelfBanishEffect();
    case 'resetChampion':
      return const ResetChampionEffect();
    case 'recruitFromCenter':
      return RecruitFromCenterEffect(
        maxCost: json.containsKey('maxCost') ? _int(json, 'maxCost') : null,
        free: (json['free'] as bool?) ?? false,
        toHand: (json['toHand'] as bool?) ?? false,
        toTopOfDeck: (json['toTopOfDeck'] as bool?) ?? false,
      );
    case 'fastPlayFromCenter':
      return FastPlayFromCenterEffect(
        maxCost: json.containsKey('maxCost') ? _int(json, 'maxCost') : null,
        alliesOnly: (json['alliesOnly'] as bool?) ?? false,
      );
    case 'redirectNextRecruit':
      return RedirectNextRecruitEffect(
        destination: _recruitRedirect(json['destination'] as String?),
        faction: json['faction'] != null
            ? _faction(json['faction'] as String?)
            : null,
        cardType: _cardType(json['cardType'] as String?),
      );
    case 'scry':
      return ScryEffect(
        count: json.containsKey('count') ? _int(json, 'count') : 1,
        disposition: _scryDisposition(json['disposition'] as String?),
      );
    case 'destroyChampion':
      return DestroyChampionEffect(all: (json['all'] as bool?) ?? false);
    case 'returnFromDiscard':
      final filter = _returnFilter(json['filter'] as String?);
      return ReturnFromDiscardEffect(
        filter: filter,
        faction: filter == ReturnFilter.faction
            ? _faction(json['faction'] as String?)
            : null,
        self: (json['self'] as bool?) ?? false,
        all: (json['all'] as bool?) ?? false,
      );
    case 'returnFromDiscardToDeckTop':
      final filter = _returnFilter(json['filter'] as String?);
      return ReturnFromDiscardToDeckTopEffect(
        filter: filter,
        faction: filter == ReturnFilter.faction
            ? _faction(json['faction'] as String?)
            : null,
      );
    case 'mill':
      return MillEffect(_int(json, 'count'));
    case 'recruitToHand':
      return RecruitToHandEffect(
        character: _character(json['character'] as String?),
      );
    case 'returnSelfWhenChampionPlayed':
      return const ReturnSelfWhenChampionPlayedEffect();
    case 'acquireCostReductionPerChampion':
      return AcquireCostReductionPerChampionEffect(
        faction: _faction(json['faction'] as String?),
        amountPer:
            json.containsKey('amountPer') ? _int(json, 'amountPer') : 1,
      );
    case 'bonusDrawNextTurnOnUnblockedDamage':
      return BonusDrawNextTurnOnUnblockedDamageEffect(
        threshold:
            json.containsKey('threshold') ? _int(json, 'threshold') : 10,
        count: json.containsKey('count') ? _int(json, 'count') : 3,
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
    case 'treatFactionAs':
      return TreatFactionAsEffect(
        from: _faction(json['from'] as String?),
        to: _faction(json['to'] as String?),
        bidirectional: (json['bidirectional'] as bool?) ?? false,
      );
    case 'ignoreShieldThisTurn':
      return const IgnoreShieldThisTurnEffect();
    case 'ignoreGuardThisTurn':
      return const IgnoreGuardThisTurnEffect();
    case 'doublePower':
      return const DoublePowerEffect();
    case 'copyAllPlayedCards':
      return CopyAllPlayedCardsEffect(
        filter: _copyFilter(json['filter'] as String?),
        faction: json['faction'] != null
            ? _faction(json['faction'] as String?)
            : null,
      );
    case 'addStaticModifier':
      return AddStaticModifierEffect(StaticModifier(
        kind: _staticModifierKind(json['kind'] as String?),
        amount: json.containsKey('amount') ? _int(json, 'amount') : 0,
        faction: json['faction'] != null
            ? _faction(json['faction'] as String?)
            : null,
        cardType: _cardType(json['cardType'] as String?),
        sourceChampionId: json['sourceChampionId'] as String?,
        masteryThreshold: json['masteryThreshold'] as int?,
        masteryAmount:
            json.containsKey('masteryAmount') ? _int(json, 'masteryAmount') : 0,
        cannotBeAttackedScope:
            _cannotBeAttackedScope(json['cannotBeAttackedScope'] as String?),
        cannotBeAttackedCondition: _cannotBeAttackedCondition(
            json['cannotBeAttackedCondition'] as String?),
        conditionCardName: json['conditionCardName'] as String?,
      ));
    case 'opponentDraws':
      return OpponentDrawsEffect(
        count: json.containsKey('count') ? _int(json, 'count') : 1,
      );
    case 'opponentDiscards':
      return OpponentDiscardsEffect(
        count: json.containsKey('count') ? _int(json, 'count') : 1,
      );
    case 'copyPlayedCard':
      return CopyPlayedCardEffect(
        filter: _copyFilter(json['filter'] as String?),
        faction: json['faction'] != null
            ? _faction(json['faction'] as String?)
            : null,
      );
    case 'revealAndCopyTopOfDecks':
      return const RevealAndCopyTopOfDecksEffect();
    case 'centerDeckScry':
      return CenterDeckScryEffect(
        disposition: _centerScryDisposition(json['disposition'] as String?),
      );
    case 'tuckUnderChampion':
      return TuckUnderChampionEffect(
        source: _tuckSource(json['source'] as String?),
        alliesOnly: (json['alliesOnly'] as bool?) ?? false,
      );
    case 'copyUnderCards':
      return const CopyUnderCardsEffect();
    case 'infinityShard':
      return const InfinityShardEffect();
    case 'chooseOne':
      final choices = json['choices'];
      if (choices is! List) {
        throw const FormatException('chooseOne requires a "choices" array');
      }
      return ChooseOneEffect(
        [
          for (final group in choices) decodeEffectList(group),
        ],
        pick: json.containsKey('pick') ? _int(json, 'pick') : 1,
      );
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
    case OpponentLosesMasteryEffect():
      return {'type': 'opponentLosesMastery', 'amount': effect.amount};
    case AllPlayersLoseHealthEffect():
      return {'type': 'allPlayersLoseHealth', 'amount': effect.amount};
    case BanishRandomFromEachHandEffect():
      return {'type': 'banishRandomFromEachHand'};
    case AllPlayersDiscardEffect():
      return {'type': 'allPlayersDiscard', 'count': effect.count};
    case AllPlayersDestroyHighestChampionEffect():
      return {'type': 'allPlayersDestroyHighestChampion'};
    case GrantExtraDestinyClaimEffect():
      return {'type': 'grantExtraDestinyClaim', 'count': effect.count};
    case RecruitRelicToHandEffect():
      return {'type': 'recruitRelicToHand'};
    case BanishUpToFromAnyZoneEffect():
      return {'type': 'banishUpToFromAnyZone', 'count': effect.count};
    case BanishCardEffect():
      return {'type': 'banishCard', 'source': effect.source.name};
    case ScrapFromCenterRowEffect():
      return {'type': 'scrapFromCenterRow'};
    case SelfBanishEffect():
      return {'type': 'selfBanish'};
    case ResetChampionEffect():
      return {'type': 'resetChampion'};
    case RecruitFromCenterEffect():
      return {
        'type': 'recruitFromCenter',
        if (effect.maxCost != null) 'maxCost': effect.maxCost,
        if (effect.free) 'free': true,
        if (effect.toHand) 'toHand': true,
        if (effect.toTopOfDeck) 'toTopOfDeck': true,
      };
    case FastPlayFromCenterEffect():
      return {
        'type': 'fastPlayFromCenter',
        if (effect.maxCost != null) 'maxCost': effect.maxCost,
        if (effect.alliesOnly) 'alliesOnly': true,
      };
    case RedirectNextRecruitEffect():
      return {
        'type': 'redirectNextRecruit',
        'destination': effect.destination.name,
        if (effect.faction != null) 'faction': effect.faction!.name,
        if (effect.cardType != null) 'cardType': effect.cardType!.name,
      };
    case ScryEffect():
      return {
        'type': 'scry',
        if (effect.count != 1) 'count': effect.count,
        if (effect.disposition != ScryDisposition.drawOrDiscard)
          'disposition': effect.disposition.name,
      };
    case DestroyChampionEffect():
      return {'type': 'destroyChampion', 'all': effect.all};
    case ReturnFromDiscardEffect():
      return {
        'type': 'returnFromDiscard',
        'filter': effect.filter.name,
        if (effect.faction != null) 'faction': effect.faction!.name,
        if (effect.self) 'self': true,
        if (effect.all) 'all': true,
      };
    case ReturnFromDiscardToDeckTopEffect():
      return {
        'type': 'returnFromDiscardToDeckTop',
        'filter': effect.filter.name,
        if (effect.faction != null) 'faction': effect.faction!.name,
      };
    case MillEffect():
      return {'type': 'mill', 'count': effect.count};
    case RecruitToHandEffect():
      return {
        'type': 'recruitToHand',
        if (effect.character != null) 'character': effect.character!.name,
      };
    case ReturnSelfWhenChampionPlayedEffect():
      return {'type': 'returnSelfWhenChampionPlayed'};
    case AcquireCostReductionPerChampionEffect():
      return {
        'type': 'acquireCostReductionPerChampion',
        'faction': effect.faction.name,
        if (effect.amountPer != 1) 'amountPer': effect.amountPer,
      };
    case BonusDrawNextTurnOnUnblockedDamageEffect():
      return {
        'type': 'bonusDrawNextTurnOnUnblockedDamage',
        if (effect.threshold != 10) 'threshold': effect.threshold,
        if (effect.count != 3) 'count': effect.count,
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
    case TreatFactionAsEffect():
      return {
        'type': 'treatFactionAs',
        'from': effect.from.name,
        'to': effect.to.name,
        if (effect.bidirectional) 'bidirectional': true,
      };
    case IgnoreShieldThisTurnEffect():
      return {'type': 'ignoreShieldThisTurn'};
    case IgnoreGuardThisTurnEffect():
      return {'type': 'ignoreGuardThisTurn'};
    case DoublePowerEffect():
      return {'type': 'doublePower'};
    case CopyAllPlayedCardsEffect():
      return {
        'type': 'copyAllPlayedCards',
        'filter': effect.filter.name,
        if (effect.faction != null) 'faction': effect.faction!.name,
      };
    case AddStaticModifierEffect():
      final m = effect.modifier;
      return {
        'type': 'addStaticModifier',
        'kind': m.kind.name,
        if (m.amount != 0) 'amount': m.amount,
        if (m.faction != null) 'faction': m.faction!.name,
        if (m.cardType != null) 'cardType': m.cardType!.name,
        if (m.sourceChampionId != null)
          'sourceChampionId': m.sourceChampionId,
        if (m.masteryThreshold != null)
          'masteryThreshold': m.masteryThreshold,
        if (m.masteryAmount != 0) 'masteryAmount': m.masteryAmount,
        if (m.cannotBeAttackedScope !=
            CannotBeAttackedScope.playerAndOtherChampions)
          'cannotBeAttackedScope': m.cannotBeAttackedScope.name,
        if (m.cannotBeAttackedCondition != CannotBeAttackedCondition.always)
          'cannotBeAttackedCondition': m.cannotBeAttackedCondition.name,
        if (m.conditionCardName != null)
          'conditionCardName': m.conditionCardName,
      };
    case OpponentDrawsEffect():
      return {
        'type': 'opponentDraws',
        if (effect.count != 1) 'count': effect.count,
      };
    case OpponentDiscardsEffect():
      return {
        'type': 'opponentDiscards',
        if (effect.count != 1) 'count': effect.count,
      };
    case CopyPlayedCardEffect():
      return {
        'type': 'copyPlayedCard',
        'filter': effect.filter.name,
        if (effect.faction != null) 'faction': effect.faction!.name,
      };
    case RevealAndCopyTopOfDecksEffect():
      return {'type': 'revealAndCopyTopOfDecks'};
    case CenterDeckScryEffect():
      return {
        'type': 'centerDeckScry',
        'disposition': effect.disposition.name,
      };
    case TuckUnderChampionEffect():
      return {
        'type': 'tuckUnderChampion',
        if (effect.source != TuckSource.hand) 'source': effect.source.name,
        if (effect.alliesOnly) 'alliesOnly': true,
      };
    case CopyUnderCardsEffect():
      return {'type': 'copyUnderCards'};
    case InfinityShardEffect():
      return {'type': 'infinityShard'};
    case ChooseOneEffect():
      return {
        'type': 'chooseOne',
        if (effect.pick != 1) 'pick': effect.pick,
        'choices': [
          for (final group in effect.choices)
            [for (final e in group) encodeEffect(e)],
        ],
      };
    case GainMoneyEffect():
      // Legacy effect — not part of the Fragments of Boundlessness database.
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

/// Reads an optional integer key, returning null when absent. Throws if present
/// but not an integer. Used for the optional `masteryThreshold` of an
/// [ActivatedAbility].
int? _optNullInt(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v == null) return null;
  if (v is int) return v;
  throw FormatException('"$key" must be an integer');
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
    case 'playedThisTurn':
      return BanishSource.playedThisTurn;
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
    maxCost: raw.containsKey('maxCost') ? _int(raw, 'maxCost') : null,
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

StaticModifierKind _staticModifierKind(String? raw) {
  for (final v in StaticModifierKind.values) {
    if (v.name == raw) return v;
  }
  throw FormatException('unknown static modifier kind: $raw');
}

CannotBeAttackedScope _cannotBeAttackedScope(String? raw) {
  if (raw == null) return CannotBeAttackedScope.playerAndOtherChampions;
  for (final v in CannotBeAttackedScope.values) {
    if (v.name == raw) return v;
  }
  throw FormatException('unknown cannotBeAttacked scope: $raw');
}

CannotBeAttackedCondition _cannotBeAttackedCondition(String? raw) {
  if (raw == null) return CannotBeAttackedCondition.always;
  for (final v in CannotBeAttackedCondition.values) {
    if (v.name == raw) return v;
  }
  throw FormatException('unknown cannotBeAttacked condition: $raw');
}

CopyFilter _copyFilter(String? raw) {
  switch (raw) {
    case 'nonChampion':
    case null:
      return CopyFilter.nonChampion;
    case 'any':
      return CopyFilter.any;
    default:
      throw FormatException('unknown copy filter: $raw');
  }
}

TuckSource _tuckSource(String? raw) {
  switch (raw) {
    case 'hand':
    case null:
      return TuckSource.hand;
    case 'centerDeck':
      return TuckSource.centerDeck;
    default:
      throw FormatException('unknown tuck source: $raw');
  }
}

CenterScryDisposition _centerScryDisposition(String? raw) {
  switch (raw) {
    case 'acquire':
    case null:
      return CenterScryDisposition.acquire;
    case 'toHandLosePowerEqualToCost':
      return CenterScryDisposition.toHandLosePowerEqualToCost;
    default:
      throw FormatException('unknown center scry disposition: $raw');
  }
}

RecruitRedirect _recruitRedirect(String? raw) {
  switch (raw) {
    case 'intoPlay':
      return RecruitRedirect.intoPlay;
    case 'toHand':
      return RecruitRedirect.toHand;
    default:
      throw FormatException('unknown recruit redirect destination: $raw');
  }
}

ScryDisposition _scryDisposition(String? raw) {
  switch (raw) {
    case 'drawOrDiscard':
    case null:
      return ScryDisposition.drawOrDiscard;
    case 'drawOrBanish':
      return ScryDisposition.drawOrBanish;
    case 'toHand':
      return ScryDisposition.toHand;
    case 'toHandLosePowerEqualToCost':
      return ScryDisposition.toHandLosePowerEqualToCost;
    case 'toHandLoseHealthEqualToCost':
      return ScryDisposition.toHandLoseHealthEqualToCost;
    case 'toHandOpponentsLoseHealthEqualToCost':
      return ScryDisposition.toHandOpponentsLoseHealthEqualToCost;
    default:
      throw FormatException('unknown scry disposition: $raw');
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
