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

  /// SHIELD — the in-hand damage reduction this card offers its owner. While
  /// this card is in the owner's HAND, its [shield] is subtracted from every
  /// direct attack against that player (summed across the hand; passive, never
  /// consumed — see GameService._playerDamageReduction). It does NOT reduce
  /// damage dealt to champions, and it has NO effect once the card leaves the
  /// hand. This is INDEPENDENT of [health]: allies carry only a shield, most
  /// champions carry only health, and a few champions (e.g. Zetta, The
  /// Encryptor) carry BOTH — a shield that protects while Zetta is in hand and a
  /// health value that is its toughness once it is played out. Defaults to 0.
  final int shield;

  /// HEALTH — a champion's in-play toughness: the amount of power an attacker
  /// must spend to destroy this champion in a SINGLE attack (meet-or-exceed:
  /// power >= health destroys it; no partial/chip damage, no carry-over across
  /// turns — see GameService.attackChampion / _effectiveHealth). Champions only;
  /// 0 for non-champions. This is NOT a buff to the owner's life total and NOT a
  /// hand shield — it is INDEPENDENT of [shield] (a champion may have both).
  final int health;

  /// When true, this card's IN-HAND [shield] is DYNAMIC and equals the owner's
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

  /// Extra factions this card ALSO counts as (in ADDITION to its own
  /// [faction]) — a MULTI-faction card, distinct from the unconditional
  /// [countsAsAllFactions]. When [countsAsFactionsMasteryThreshold] is non-null
  /// the extra factions only apply while the owner's mastery is at/above that
  /// threshold (querry_monk Mastery-10: "also counts as Homodeus, Undergrowth
  /// and Wraethe"). Consulted by the engine's faction matching (ally-ability
  /// triggers, faction-filtered conditions/scaling). Empty for ordinary cards.
  final List<Faction> countsAsFactions;

  /// Optional mastery gate for [countsAsFactions]. When non-null, the extra
  /// factions apply only while the owner's mastery is at/above this value; when
  /// null, they always apply. Ignored when [countsAsFactions] is empty.
  final int? countsAsFactionsMasteryThreshold;

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

  /// When true (champions only), destroying this champion does NOT simply move
  /// the cards tucked under it to the owner's discard pile. Instead the owner
  /// may SALVAGE them: the under-cards move to
  /// [GameService.pendingUnderCardRecruit] where the owner can PAY each card's
  /// gem cost to recruit it (to discard) and the rest are banished
  /// (carmine_eclipse "when this is destroyed, you may recruit any of the cards
  /// under this and banish the rest"). Consulted by
  /// [GameService._disposeUnderCardsOnDeath]. Defaults to false (the ordinary
  /// paradigm_the_archivist disposition — all under-cards to discard).
  final bool recruitUnderCardsOnDeath;

  const CardModel({
    required this.id,
    required this.name,
    required this.cost,
    required this.playEffects,
    this.faction = Faction.none,
    this.cardType = CardType.regular,
    this.shield = 0,
    this.health = 0,
    this.shieldEqualsMastery = false,
    this.hasGuard = false,
    this.allyAbility = const <CardEffect>[],
    this.masteryThreshold,
    this.masteryBonus = const <CardEffect>[],
    this.masteryReplaces = false,
    this.countsAsAllFactions = false,
    this.countsAsFactions = const <Faction>[],
    this.countsAsFactionsMasteryThreshold,
    this.activatedAbility,
    this.art,
    this.recruitUnderCardsOnDeath = false,
  });

  /// Returns a copy with the given overrides; any field left null keeps the
  /// current value. The market-instance (`_instanceOf`) and relic-instance
  /// (`_relicInstanceFor`) builders use this so a newly-added CardModel field
  /// can never be silently dropped from a recruited/relic copy again.
  CardModel copyWith({
    String? id,
    String? name,
    int? cost,
    List<CardEffect>? playEffects,
    Faction? faction,
    CardType? cardType,
    int? shield,
    int? health,
    bool? shieldEqualsMastery,
    bool? hasGuard,
    List<CardEffect>? allyAbility,
    int? masteryThreshold,
    List<CardEffect>? masteryBonus,
    bool? masteryReplaces,
    bool? countsAsAllFactions,
    List<Faction>? countsAsFactions,
    int? countsAsFactionsMasteryThreshold,
    ActivatedAbility? activatedAbility,
    String? art,
    bool? recruitUnderCardsOnDeath,
  }) {
    return CardModel(
      id: id ?? this.id,
      name: name ?? this.name,
      cost: cost ?? this.cost,
      playEffects: playEffects ?? this.playEffects,
      faction: faction ?? this.faction,
      cardType: cardType ?? this.cardType,
      shield: shield ?? this.shield,
      health: health ?? this.health,
      shieldEqualsMastery: shieldEqualsMastery ?? this.shieldEqualsMastery,
      hasGuard: hasGuard ?? this.hasGuard,
      allyAbility: allyAbility ?? this.allyAbility,
      masteryThreshold: masteryThreshold ?? this.masteryThreshold,
      masteryBonus: masteryBonus ?? this.masteryBonus,
      masteryReplaces: masteryReplaces ?? this.masteryReplaces,
      countsAsAllFactions: countsAsAllFactions ?? this.countsAsAllFactions,
      countsAsFactions: countsAsFactions ?? this.countsAsFactions,
      countsAsFactionsMasteryThreshold: countsAsFactionsMasteryThreshold ??
          this.countsAsFactionsMasteryThreshold,
      activatedAbility: activatedAbility ?? this.activatedAbility,
      art: art ?? this.art,
      recruitUnderCardsOnDeath:
          recruitUnderCardsOnDeath ?? this.recruitUnderCardsOnDeath,
    );
  }
}
