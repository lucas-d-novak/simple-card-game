import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

class CardModel {
  final String id;
  final String name;
  final int cost;
  final List<CardEffect> playEffects;

  // --- Fragments of Boundlessness fields (all have defaults for backward compat) ---

  /// Which faction this card belongs to. Factionless cards use [Faction.none].
  final Faction faction;

  /// Whether this is a regular card, champion, or mercenary.
  final CardType cardType;

  /// Champion HEALTH (champions only): the amount of power an attacker must
  /// spend to destroy this champion. The destroy threshold is MEET-OR-EXCEED —
  /// power >= shield destroys it (see GameService.attackChampion). This number
  /// is NOT a buff to the owner's life total; it is purely the cost to remove
  /// the champion. (Named `shield` for historical reasons.)
  final int shield;

  /// When true, this card's IN-HAND shield is DYNAMIC and equals the owner's
  /// CURRENT mastery, rather than the static [shield] value (datic_robes: "this
  /// has shield equal to your mastery"). Consulted only by the player
  /// damage-reduction path (GameService._playerDamageReduction) — it has no
  /// effect on a champion's kill threshold. Defaults to false.
  final bool shieldEqualsMastery;

  /// Whether this champion has Guard. While a player controls ANY guard
  /// champion, opponents cannot attack that player directly — every guard
  /// champion must be destroyed first. A champion is an OPTIONAL attack target
  /// otherwise (an attacker may ignore non-guard champions and hit the player).
  /// Champions cannot be protected by cards in the owner's hand.
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

  /// How the mastery threshold resolves. When false (the default and the
  /// behavior of every legacy card), [masteryBonus] is resolved ADDITIVELY on
  /// top of [playEffects] once mastery reaches [masteryThreshold]. When true,
  /// [masteryBonus] REPLACES [playEffects] at/above the threshold (e.g. "gain
  /// 5/5 INSTEAD OF 2/2 at mastery 15") — [playEffects] are skipped and only
  /// [masteryBonus] resolves. Below the threshold, [playEffects] resolve
  /// normally either way. Defaults to false for backward compatibility.
  final bool masteryReplaces;

  /// When true, this card counts as every faction for ally ability purposes
  /// (e.g. Universal Soldier).
  final bool countsAsAllFactions;

  /// An optional Exhaust-gated activated ability (champions only). Null for
  /// cards without one. This is DISTINCT from [playEffects]: [playEffects] are
  /// the card's normal effects (resolved on play, and re-resolvable each turn
  /// for champions via the free `activateChampion`). The activated ability is a
  /// separate, additional action that exhausts (taps) the champion until the
  /// start of the owner's next turn. See [ActivatedAbility].
  final ActivatedAbility? activatedAbility;

  /// Optional art asset filename (e.g. `furrowing_elemental.jpg`) from the card
  /// database. When set, the UI loads `assets/cards/<art>` directly instead of
  /// guessing an asset from the card name. Null for cards without DB art.
  final String? art;

  const CardModel({
    required this.id,
    required this.name,
    required this.cost,
    required this.playEffects,
    this.faction = Faction.none,
    this.cardType = CardType.regular,
    this.shield = 0,
    this.shieldEqualsMastery = false,
    this.hasGuard = false,
    this.allyAbility = const <CardEffect>[],
    this.masteryThreshold,
    this.masteryBonus = const <CardEffect>[],
    this.masteryReplaces = false,
    this.countsAsAllFactions = false,
    this.activatedAbility,
    this.art,
  });
}
