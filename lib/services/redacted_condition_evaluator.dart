import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/faction.dart';

/// The slice of a recipient's REDACTED game view that a [GameCondition] can be
/// evaluated against client-side (no engine). The networked board builds one of
/// these from the server's redacted player view + the `cards` dictionary, so the
/// "conditions satisfied" glow can be computed without the engine.
///
/// Only fields expressible from redacted data are carried. Conditions that need
/// data the server never ships (e.g. the controlling player's Character, or
/// turn-scoped faction aliases) are NOT evaluable and the evaluator returns
/// false for them (no glow — never guess).
class RedactedConditionContext {
  RedactedConditionContext({
    required this.cards,
    required this.handIds,
    required this.playedThisTurnIds,
    required this.discardIds,
    required this.championIds,
    required this.mastery,
    required this.unblockedDamageThisTurn,
  });

  /// id → CardModel for every visible card (from the redacted `cards` dict).
  final Map<String, CardModel> cards;

  /// The recipient's own hand card ids.
  final List<String> handIds;

  /// Card ids the recipient has played THIS turn (regular + champions +
  /// mercenaries), in play order. Mirrors `PlayerState.cardsPlayedThisTurn`.
  final List<String> playedThisTurnIds;

  /// The recipient's discard-pile card ids.
  final List<String> discardIds;

  /// The recipient's champions-in-play card ids.
  final List<String> championIds;

  /// The recipient's current mastery.
  final int mastery;

  /// Unblocked damage the recipient dealt this turn.
  final int unblockedDamageThisTurn;

  CardModel? _card(String id) => cards[id];

  List<CardModel> get _played => [
        for (final id in playedThisTurnIds)
          if (_card(id) != null) _card(id)!,
      ];

  List<CardModel> get _hand => [
        for (final id in handIds)
          if (_card(id) != null) _card(id)!,
      ];

  List<CardModel> get _discard => [
        for (final id in discardIds)
          if (_card(id) != null) _card(id)!,
      ];

  List<CardModel> get _champions => [
        for (final id in championIds)
          if (_card(id) != null) _card(id)!,
      ];
}

/// Whether [card] has at least one [ConditionalEffect] whose [GameCondition]
/// currently holds, evaluated against the redacted [ctx]. Client-side mirror of
/// `GameService.conditionsSatisfied`. Faction-less conditions resolve against
/// [card]'s own faction (the source-card rule).
bool redactedConditionsSatisfied(CardModel card, RedactedConditionContext ctx) {
  for (final effect in card.playEffects) {
    if (effect is ConditionalEffect &&
        _evaluate(effect.condition, card, ctx)) {
      return true;
    }
  }
  return false;
}

/// Evaluate a SINGLE [GameCondition] against the redacted [ctx], with [source]
/// as the condition's source card (faction-less conditions resolve against its
/// faction). Public so callers can gate a conditional effect's deferred
/// follow-up (e.g. only prompt Limiter Drones' banish when "you control a
/// Champion" actually holds). Not-evaluable-from-redacted-data conditions return
/// false — never guess.
bool redactedConditionHolds(
  GameCondition condition,
  CardModel source,
  RedactedConditionContext ctx,
) =>
    _evaluate(condition, source, ctx);

/// Base faction match honouring `countsAsAllFactions` on either side. Turn-scoped
/// aliases (TreatFactionAs) are not in redacted data, so they are not applied —
/// this matches the engine for the common (no-alias) case.
bool _factionsMatch(Faction want, CardModel card) {
  if (want == Faction.none) return false;
  if (card.countsAsAllFactions) return true;
  return card.faction == want;
}

/// Count cards played this turn matching [test], EXCLUDING one instance of the
/// source card (mirrors the engine's `_countPlayedThisTurn` self-skip).
int _countPlayed(
  CardModel source,
  RedactedConditionContext ctx,
  bool Function(CardModel) test,
) {
  var count = 0;
  var skippedSelf = false;
  for (final c in ctx._played) {
    if (!skippedSelf && identical(c, source)) {
      skippedSelf = true;
      continue;
    }
    // The redacted view holds shared CardModel instances by id, so `identical`
    // may not match the source even when it is the same card. Fall back to an
    // id-based self-skip when the instance check didn't fire.
    if (!skippedSelf && c.id == source.id) {
      skippedSelf = true;
      continue;
    }
    if (test(c)) count++;
  }
  return count;
}

bool _evaluate(
  GameCondition c,
  CardModel source,
  RedactedConditionContext ctx,
) {
  switch (c.kind) {
    case GameConditionKind.alliesOfFactionPlayed:
      final f = c.faction ?? source.faction;
      if (f == Faction.none) return false;
      return _countPlayed(source, ctx, (card) => _factionsMatch(f, card)) >=
          c.threshold;

    case GameConditionKind.factionsPlayedAll:
      if (c.factions.isEmpty) return false;
      final played = <Faction>{
        for (final card in ctx._played)
          if (card.faction != Faction.none) card.faction,
      };
      return c.factions.every(played.contains);

    case GameConditionKind.distinctFactionsPlayed:
      final factions = <Faction>{
        for (final card in ctx._played)
          if (card.faction != Faction.none) card.faction,
      };
      return factions.length >= c.threshold;

    case GameConditionKind.cardTypePlayed:
      final type = c.cardType;
      if (type == null) return false;
      return _countPlayed(source, ctx, (card) => card.cardType == type) >=
          c.threshold;

    case GameConditionKind.championsControlled:
      return ctx.championIds.length >= c.threshold;

    case GameConditionKind.championsOfFactionControlled:
      final f = c.faction ?? source.faction;
      if (f == Faction.none) return false;
      final count =
          ctx._champions.where((card) => _factionsMatch(f, card)).length;
      return count >= c.threshold;

    case GameConditionKind.masteryAtLeast:
      return ctx.mastery >= c.threshold;

    case GameConditionKind.sameFactionCountPlayed:
      final f = c.faction ?? source.faction;
      if (f == Faction.none) return false;
      // Count ALL same-faction cards played this turn INCLUDING the source.
      final count =
          ctx._played.where((card) => _factionsMatch(f, card)).length;
      return count >= c.threshold;

    case GameConditionKind.unblockedDamageAtLeast:
      return ctx.unblockedDamageThisTurn >= c.threshold;

    case GameConditionKind.factionAllyPlayedOrInHand:
      final f = c.faction ?? source.faction;
      if (f == Faction.none) return false;
      bool matches(CardModel card) => _factionsMatch(f, card);
      if (_countPlayed(source, ctx, matches) >= c.threshold) return true;
      return ctx._hand.any(matches);

    case GameConditionKind.factionCardInDiscard:
      final f = c.faction ?? source.faction;
      if (f == Faction.none) return false;
      return ctx._discard.any((card) => _factionsMatch(f, card));

    case GameConditionKind.oddCostCardsPlayed:
      return _countPlayed(source, ctx, (card) => card.cost.isOdd) >=
          c.threshold;

    case GameConditionKind.evenCostCardsPlayed:
      return _countPlayed(source, ctx, (card) => card.cost.isEven) >=
          c.threshold;

    // --- Not evaluable from redacted data → no glow (never guess). ---
    // gemParityCardsPlayed and filteredCardsPlayed COULD be derived, but the
    // engine excludes the source for parity in a way that needs the unfiltered
    // play list; we conservatively skip the parity/filtered kinds and the
    // Character gate, which the redacted view never carries reliably.
    case GameConditionKind.gemParityCardsPlayed:
    case GameConditionKind.filteredCardsPlayed:
    case GameConditionKind.isCharacter:
      return false;
  }
}
