import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

class CardModel {
  final String id;
  final String name;
  final int cost;
  final List<CardEffect> playEffects;

  // --- Shards of Infinity fields (all have defaults for backward compat) ---

  /// Which faction this card belongs to. Factionless cards use [Faction.none].
  final Faction faction;

  /// Whether this is a regular card, champion, or mercenary.
  final CardType cardType;

  /// Shield points (champions only). Damage must exceed this to destroy.
  final int shield;

  /// Whether this champion has Guard (opponents must destroy it before
  /// attacking the player directly).
  final bool hasGuard;

  /// Bonus effects that trigger when another card of the same faction is
  /// played or controlled this turn.
  final List<CardEffect> allyAbility;

  /// Mastery level required to unlock [masteryBonus] effects. Null means
  /// this card has no mastery threshold.
  final int? masteryThreshold;

  /// Bonus effects unlocked when the player's mastery reaches
  /// [masteryThreshold].
  final List<CardEffect> masteryBonus;

  /// When true, this card counts as every faction for ally ability purposes
  /// (e.g. Universal Soldier).
  final bool countsAsAllFactions;

  const CardModel({
    required this.id,
    required this.name,
    required this.cost,
    required this.playEffects,
    this.faction = Faction.none,
    this.cardType = CardType.regular,
    this.shield = 0,
    this.hasGuard = false,
    this.allyAbility = const <CardEffect>[],
    this.masteryThreshold,
    this.masteryBonus = const <CardEffect>[],
    this.countsAsAllFactions = false,
  });
}
