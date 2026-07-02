// Full game-state serialization for multiplayer: GameService + PlayerState ⇄
// JSON. This is the AUTHORITATIVE (full-fidelity) snapshot used for
// persistence, reconnect-resync, and as the basis for per-player redacted views
// (the redaction itself lives in the server, not here).
//
// Design:
// - Cards are serialized into a single "card dictionary" (id → full CardModel
//   JSON), each distinct card emitted ONCE. Every zone (hands, piles, center
//   row, under-card map, …) then references cards by id. This keeps the payload
//   small (no repeated effect trees) while remaining faithful to synthetic
//   starter-deck cards (e.g. `p0_crystal_3`) that are not in CardDatabase.
// - RNG is NOT serialized. In the authoritative-server model the server is the
//   sole engine; restoring from the concrete (already-shuffled) pile orders with
//   a fresh Random is correct. See GameService.restore.

import 'package:simple_card_game/data/database/card_serialization.dart';
import 'package:simple_card_game/data/database/effect_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/ingeminex_entity.dart';
import 'package:simple_card_game/models/player_state.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Accumulates distinct cards by id so each is serialized by value only once.
class _CardDict {
  final Map<String, Map<String, dynamic>> _byId = {};

  /// Record [card] (if new) and return its id (the reference written into zones).
  String ref(CardModel card) {
    _byId.putIfAbsent(card.id, () => cardModelToJson(card));
    return card.id;
  }

  Map<String, dynamic> toJson() => _byId;
}

List<String> _refs(_CardDict dict, List<CardModel> cards) =>
    [for (final c in cards) dict.ref(c)];

class GameStateCodec {
  /// Serialize a full [GameService] to a JSON-safe map.
  static Map<String, dynamic> encode(GameService game) {
    final dict = _CardDict();

    final players = [
      for (final p in game.players) _encodePlayer(p, dict),
    ];

    return {
      'version': 1,
      'cards': dict.toJson(),
      'players': players,
      'centerRow': _refs(dict, game.centerRow),
      'infinityDeck': _refs(dict, game.infinityDeck),
      'removedFromGame': _refs(dict, game.removedFromGame),
      // carmine_eclipse on-death salvage buckets (ownerId → salvageable
      // under-cards). Only emitted when a salvage is pending.
      if (game.pendingUnderCardRecruit.isNotEmpty)
        'pendingUnderCardRecruit': {
          for (final entry in game.pendingUnderCardRecruit.entries)
            entry.key: _refs(dict, entry.value),
        },
      // Neutral Ingeminex entities in the shared champion row (ownerless, so
      // serialized inline rather than via the card dict). Only emitted when any
      // are in play; accumulated damage is preserved.
      if (game.ingeminexRow.isNotEmpty)
        'ingeminex': [for (final e in game.ingeminexRow) _encodeIngeminex(e)],
      // Destiny system (Into the Horizon) — only emitted when a supply exists.
      if (game.destinyRow.isNotEmpty)
        'destinyRow': _refs(dict, game.destinyRow),
      if (game.destinyDeck.isNotEmpty)
        'destinyDeck': _refs(dict, game.destinyDeck),
      'currentPlayerIndex': game.currentPlayerIndex,
      'turnNumber': game.turnNumber,
      'gameOver': game.isGameOver,
      if (game.winnerId != null) 'winnerId': game.winnerId,
      if (game.winType != null) 'winType': game.winType,
      if (game.lastDamage != null) 'lastDamage': game.lastDamage!.toJson(),
      if (game.actionLog.isNotEmpty)
        'actionLog': [for (final e in game.actionLog) e.toJson()],
    };
  }

  /// Rehydrate a full [GameService] from [encode]'s output.
  static GameService decode(Map<String, dynamic> json) {
    final rawCards = (json['cards'] as Map).cast<String, dynamic>();
    // Rehydrate every distinct card once; zones look up by id.
    final cards = <String, CardModel>{
      for (final entry in rawCards.entries)
        entry.key:
            cardModelFromJson((entry.value as Map).cast<String, dynamic>()),
    };
    CardModel lookup(String id) {
      final c = cards[id];
      if (c == null) {
        throw FormatException('game state references unknown card id "$id"');
      }
      return c;
    }

    List<CardModel> zone(dynamic ids) =>
        [for (final id in (ids as List? ?? const [])) lookup(id as String)];

    final game = GameService.restore();

    for (final raw in (json['players'] as List)) {
      game.players.add(_decodePlayer((raw as Map).cast<String, dynamic>(), zone));
    }
    game.centerRow.addAll(zone(json['centerRow']));
    game.infinityDeck.addAll(zone(json['infinityDeck']));
    game.removedFromGame.addAll(zone(json['removedFromGame']));
    final pendingSalvage = (json['pendingUnderCardRecruit'] as Map? ?? const {})
        .cast<String, dynamic>();
    for (final entry in pendingSalvage.entries) {
      game.pendingUnderCardRecruit[entry.key] = zone(entry.value);
    }
    for (final raw in (json['ingeminex'] as List? ?? const [])) {
      game.ingeminexRow
          .add(_decodeIngeminex((raw as Map).cast<String, dynamic>()));
    }
    game.destinyRow.addAll(zone(json['destinyRow']));
    game.destinyDeck.addAll(zone(json['destinyDeck']));
    game.currentPlayerIndex = (json['currentPlayerIndex'] as int?) ?? 0;
    game.turnNumber = (json['turnNumber'] as int?) ?? 1;
    game.restoreGameOver((json['gameOver'] as bool?) ?? false);
    game.winnerId = json['winnerId'] as String?;
    game.winType = json['winType'] as String?;
    if (json['lastDamage'] != null) {
      game.restoreLastDamage(LastDamageEvent.fromJson(
          (json['lastDamage'] as Map).cast<String, dynamic>()));
    }
    for (final e in (json['actionLog'] as List? ?? const [])) {
      game.actionLog.add(GameLogEntry.fromJson((e as Map).cast<String, dynamic>()));
    }

    return game;
  }

  // ---- PlayerState ----

  static Map<String, dynamic> _encodePlayer(PlayerState p, _CardDict dict) {
    return {
      'id': p.id,
      'name': p.name,
      if (p.character != null) 'character': p.character!.name,
      'health': p.health,
      'mastery': p.mastery,
      'gemPool': p.gemPool,
      'powerPool': p.powerPool,
      'unblockedDamageThisTurn': p.unblockedDamageThisTurn,
      if (p.healthGainedThisTurn != 0)
        'healthGainedThisTurn': p.healthGainedThisTurn,
      if (p.nextTurnDrawBonus != 0) 'nextTurnDrawBonus': p.nextTurnDrawBonus,
      'ignoresShieldThisTurn': p.ignoresShieldThisTurn,
      'ignoresGuardThisTurn': p.ignoresGuardThisTurn,
      'focusedThisTurn': p.focusedThisTurn,
      if (p.pendingRecruitRedirect != null)
        'pendingRecruitRedirect': encodeEffect(p.pendingRecruitRedirect!),
      'factionAliasesThisTurn': [
        for (final a in p.factionAliasesThisTurn)
          {'from': a.from.name, 'to': a.to.name},
      ],
      'staticModifiers': [
        for (final m in p.staticModifiers) _encodeStaticModifier(m),
      ],
      'relicOptions': _refs(dict, p.relicOptions),
      'relicRecruited': p.relicRecruited,
      'hand': _refs(dict, p.hand),
      'drawPile': _refs(dict, p.drawPile),
      'discardPile': _refs(dict, p.discardPile),
      'playedThisTurn': _refs(dict, p.playedThisTurn),
      if (p.fastPlayedThisTurn.isNotEmpty)
        'fastPlayedThisTurn': _refs(dict, p.fastPlayedThisTurn),
      'championsInPlay': _refs(dict, p.championsInPlay),
      'cardsUnderChampion': {
        for (final entry in p.cardsUnderChampion.entries)
          entry.key: _refs(dict, entry.value),
      },
      'activatedChampions': p.activatedChampions.toList(),
      'exhaustedChampions': p.exhaustedChampions.toList(),
      'cardsPlayedThisTurn': _refs(dict, p.cardsPlayedThisTurn),
      // Destiny system (Into the Horizon) — persistent claimed zone + counters.
      if (p.claimedDestinies.isNotEmpty)
        'claimedDestinies': _refs(dict, p.claimedDestinies),
      if (p.exhaustedDestinies.isNotEmpty)
        'exhaustedDestinies': p.exhaustedDestinies.toList(),
      if (p.destinyClaimCount != 0) 'destinyClaimCount': p.destinyClaimCount,
      if (p.destinyClaimGrants != 0) 'destinyClaimGrants': p.destinyClaimGrants,
    };
  }

  static PlayerState _decodePlayer(
    Map<String, dynamic> json,
    List<CardModel> Function(dynamic) zone,
  ) {
    final p = PlayerState(
      id: json['id'] as String,
      name: json['name'] as String,
      character: characterFromName(json['character'] as String?),
    );
    p.health = (json['health'] as int?) ?? 50;
    p.mastery = (json['mastery'] as int?) ?? 0;
    p.gemPool = (json['gemPool'] as int?) ?? 0;
    p.powerPool = (json['powerPool'] as int?) ?? 0;
    p.unblockedDamageThisTurn = (json['unblockedDamageThisTurn'] as int?) ?? 0;
    p.healthGainedThisTurn = (json['healthGainedThisTurn'] as int?) ?? 0;
    p.nextTurnDrawBonus = (json['nextTurnDrawBonus'] as int?) ?? 0;
    p.ignoresShieldThisTurn = (json['ignoresShieldThisTurn'] as bool?) ?? false;
    p.ignoresGuardThisTurn = (json['ignoresGuardThisTurn'] as bool?) ?? false;
    p.focusedThisTurn = (json['focusedThisTurn'] as bool?) ?? false;
    final pendingRedirect = json['pendingRecruitRedirect'];
    if (pendingRedirect != null) {
      final decoded =
          decodeEffect((pendingRedirect as Map).cast<String, dynamic>());
      if (decoded is RedirectNextRecruitEffect) {
        p.pendingRecruitRedirect = decoded;
      }
    }

    for (final a in (json['factionAliasesThisTurn'] as List? ?? const [])) {
      final m = (a as Map).cast<String, dynamic>();
      p.factionAliasesThisTurn.add((
        from: factionFromName(m['from'] as String?),
        to: factionFromName(m['to'] as String?),
      ));
    }
    for (final m in (json['staticModifiers'] as List? ?? const [])) {
      p.staticModifiers
          .add(_decodeStaticModifier((m as Map).cast<String, dynamic>()));
    }

    p.relicOptions.addAll(zone(json['relicOptions']));
    p.relicRecruited = (json['relicRecruited'] as bool?) ?? false;
    p.hand.addAll(zone(json['hand']));
    p.drawPile.addAll(zone(json['drawPile']));
    p.discardPile.addAll(zone(json['discardPile']));
    p.playedThisTurn.addAll(zone(json['playedThisTurn']));
    p.fastPlayedThisTurn.addAll(zone(json['fastPlayedThisTurn']));
    p.championsInPlay.addAll(zone(json['championsInPlay']));
    final under = (json['cardsUnderChampion'] as Map? ?? const {})
        .cast<String, dynamic>();
    for (final entry in under.entries) {
      p.cardsUnderChampion[entry.key] = zone(entry.value);
    }
    p.activatedChampions
        .addAll([for (final id in (json['activatedChampions'] as List? ?? const [])) id as String]);
    p.exhaustedChampions
        .addAll([for (final id in (json['exhaustedChampions'] as List? ?? const [])) id as String]);
    p.cardsPlayedThisTurn.addAll(zone(json['cardsPlayedThisTurn']));
    p.claimedDestinies.addAll(zone(json['claimedDestinies']));
    p.exhaustedDestinies.addAll([
      for (final id in (json['exhaustedDestinies'] as List? ?? const []))
        id as String
    ]);
    p.destinyClaimCount = (json['destinyClaimCount'] as int?) ?? 0;
    p.destinyClaimGrants = (json['destinyClaimGrants'] as int?) ?? 0;
    return p;
  }

  // ---- IngeminexEntity (neutral, ownerless — serialized inline) ----

  static Map<String, dynamic> _encodeIngeminex(IngeminexEntity e) {
    return {
      'id': e.id,
      'name': e.name,
      if (e.art != null) 'art': e.art,
      'maxHealth': e.maxHealth,
      'damageTaken': e.damageTaken,
      'appearanceEffects': [
        for (final f in e.appearanceEffects) encodeEffect(f),
      ],
      'rewardEffects': [
        for (final f in e.rewardEffects) encodeEffect(f),
      ],
    };
  }

  static IngeminexEntity _decodeIngeminex(Map<String, dynamic> json) {
    List<CardEffect> effects(dynamic raw) => [
          for (final f in (raw as List? ?? const []))
            decodeEffect((f as Map).cast<String, dynamic>()),
        ];
    return IngeminexEntity(
      id: json['id'] as String,
      name: json['name'] as String,
      art: json['art'] as String?,
      maxHealth:
          (json['maxHealth'] as int?) ?? IngeminexEntity.defaultMaxHealth,
      damageTaken: (json['damageTaken'] as int?) ?? 0,
      appearanceEffects: effects(json['appearanceEffects']),
      rewardEffects: effects(json['rewardEffects']),
    );
  }

  // ---- StaticModifier ----

  static Map<String, dynamic> _encodeStaticModifier(StaticModifier m) {
    return {
      'kind': m.kind.name,
      if (m.amount != 0) 'amount': m.amount,
      if (m.faction != null) 'faction': m.faction!.name,
      if (m.cardType != null) 'cardType': m.cardType!.name,
      if (m.sourceChampionId != null) 'sourceChampionId': m.sourceChampionId,
      if (m.masteryThreshold != null) 'masteryThreshold': m.masteryThreshold,
      if (m.masteryAmount != 0) 'masteryAmount': m.masteryAmount,
      if (m.cannotBeAttackedScope !=
          CannotBeAttackedScope.playerAndOtherChampions)
        'cannotBeAttackedScope': m.cannotBeAttackedScope.name,
      if (m.cannotBeAttackedCondition != CannotBeAttackedCondition.always)
        'cannotBeAttackedCondition': m.cannotBeAttackedCondition.name,
      if (m.conditionCardName != null) 'conditionCardName': m.conditionCardName,
    };
  }

  static StaticModifier _decodeStaticModifier(Map<String, dynamic> json) {
    StaticModifierKind kind = StaticModifierKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => throw FormatException(
          'unknown static modifier kind "${json['kind']}"'),
    );
    return StaticModifier(
      kind: kind,
      amount: (json['amount'] as int?) ?? 0,
      faction: json['faction'] != null
          ? factionFromName(json['faction'] as String?)
          : null,
      cardType: json['cardType'] != null
          ? cardTypeFromName(json['cardType'] as String?)
          : null,
      sourceChampionId: json['sourceChampionId'] as String?,
      masteryThreshold: json['masteryThreshold'] as int?,
      masteryAmount: (json['masteryAmount'] as int?) ?? 0,
      cannotBeAttackedScope: _cannotBeAttackedScope(
          json['cannotBeAttackedScope'] as String?),
      cannotBeAttackedCondition: _cannotBeAttackedCondition(
          json['cannotBeAttackedCondition'] as String?),
      conditionCardName: json['conditionCardName'] as String?,
    );
  }

  static CannotBeAttackedScope _cannotBeAttackedScope(String? raw) {
    if (raw == null) return CannotBeAttackedScope.playerAndOtherChampions;
    return CannotBeAttackedScope.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => throw FormatException(
          'unknown cannotBeAttacked scope "$raw"'),
    );
  }

  static CannotBeAttackedCondition _cannotBeAttackedCondition(String? raw) {
    if (raw == null) return CannotBeAttackedCondition.always;
    return CannotBeAttackedCondition.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => throw FormatException(
          'unknown cannotBeAttacked condition "$raw"'),
    );
  }
}
