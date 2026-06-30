import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';

/// Mutable per-player state for a Shards of Infinity game.
class PlayerState {
  PlayerState({required this.id, required this.name, this.character});

  final String id;
  final String name;

  /// The Character this player chose, if any. Character selection is wired up
  /// in a later Engine Phase 2 wave; until then this stays null and any
  /// `GameConditionKind.isCharacter` predicate evaluates false.
  Character? character;

  int health = 50;
  int mastery = 0;
  int gemPool = 0;
  int powerPool = 0;

  /// Total unblocked damage this player has dealt to opponents this turn (via
  /// [GameService.attackPlayer]). Read by `GameConditionKind.unblockedDamageAtLeast`
  /// (e.g. blood_for_blood). Reset each turn by [resetTurnResources].
  int unblockedDamageThisTurn = 0;

  /// Turn-scoped faction aliases set by [TreatFactionAsEffect] (e.g.
  /// project_yggdrasil "treat Wraethe cards as Undergrowth this turn"). Each
  /// entry maps a `from` faction to a `to` faction; when matching factions for
  /// ally abilities and faction-filtered scaling/conditions, the engine
  /// canonicalizes a faction through these aliases (`from` is treated as `to`).
  /// Bidirectional effects add both directions. Cleared each turn by
  /// [resetTurnResources] so the alias only lasts the controlling player's turn.
  final List<({Faction from, Faction to})> factionAliasesThisTurn = [];

  /// Turn-scoped flag set by [IgnoreShieldThisTurnEffect] (spirit_leech "you
  /// ignore shield this turn"). While true, this player's attacks treat enemy
  /// champion shield as 0 for the destroy threshold (any power destroys the
  /// champion). Cleared each turn by [resetTurnResources].
  bool ignoresShieldThisTurn = false;

  /// Persistent board-wide modifiers this player owns (Engine Phase 2 wave 5a —
  /// [StaticModifier]). Added by [AddStaticModifierEffect]. LIFETIME: these are
  /// NOT cleared by [resetTurnResources] — a static modifier stays for the rest
  /// of the game (the documented wave-5a semantics; no per-card removal yet).
  /// Consulted by `GameService.attackChampion` (shield buff), `attackPlayer`
  /// (cannot-be-attacked), `buyCard` / `recruitFromCenter` (cost reduction,
  /// recruit-to-top placement).
  final List<StaticModifier> staticModifiers = [];

  final List<CardModel> hand = [];
  final List<CardModel> drawPile = [];
  final List<CardModel> discardPile = [];
  final List<CardModel> playedThisTurn = [];
  final List<CardModel> championsInPlay = [];

  /// Cards tucked UNDER a champion (Engine Phase 2 wave 5b — Family 13), keyed
  /// by the champion's id. Populated by [TuckUnderChampionEffect] (carmine_eclipse
  /// fast-play-under, paradigm_the_archivist "put an Ally under this", gene_scavs
  /// ambush). The list per champion is in tuck order. Read by
  /// `GameService._effectiveShield` (carmine_eclipse "+shield per card under")
  /// and `GameService.copyUnderCards` (paradigm). NOT cleared by
  /// [resetTurnResources] — under-cards persist with their champion until it
  /// leaves play.
  final Map<String, List<CardModel>> cardsUnderChampion = {};

  /// The number of cards currently tucked under the champion with [championId]
  /// (0 if none / unknown). Convenience for shield-per-card scaling.
  int cardsUnderCount(String championId) =>
      cardsUnderChampion[championId]?.length ?? 0;

  /// Champion ids that have used their free once-per-turn [CardModel.playEffects]
  /// activation this turn (see GameService.activateChampion).
  final Set<String> activatedChampions = {};

  /// Champion ids that are currently **exhausted** (tapped) — they have used
  /// their Exhaust-gated [CardModel.activatedAbility] and cannot use it again
  /// until the start of the owner's next turn. Distinct from
  /// [activatedChampions]: a champion can have its free play-effect activation
  /// AND its activated ability available independently. Cleared each turn by
  /// [resetTurnResources], so it is fresh at the start of the owner's next turn.
  final Set<String> exhaustedChampions = {};

  /// Every card played this turn (regular, champion, and mercenary), recorded
  /// in play order before any end-of-turn cleanup. Unlike [playedThisTurn],
  /// this includes champions (which move to [championsInPlay]) and is used by
  /// per-turn scaling effects (ConditionalPowerEffect). Cleared each turn by
  /// [resetTurnResources].
  final List<CardModel> cardsPlayedThisTurn = [];

  /// True once the player has used their once-per-turn Character **Focus**
  /// ability this turn (pay 1 gem → gain 1 mastery — the universal base action,
  /// "exhaust your character card"). Cleared each turn by [resetTurnResources].
  bool focusedThisTurn = false;

  bool get isEliminated => health <= 0;

  void addMastery(int amount) {
    if (amount > 0) {
      mastery += amount;
    }
  }

  void takeDamage(int amount) {
    health -= amount;
  }

  void heal(int amount) {
    health += amount;
  }

  /// Resets per-turn resource pools. Does not touch mastery or health.
  void resetTurnResources() {
    gemPool = 0;
    powerPool = 0;
    unblockedDamageThisTurn = 0;
    factionAliasesThisTurn.clear();
    ignoresShieldThisTurn = false;
    activatedChampions.clear();
    exhaustedChampions.clear();
    cardsPlayedThisTurn.clear();
    focusedThisTurn = false;
  }

  /// Moves regular played cards to discard pile and returns mercenaries
  /// (for removal from the game). Clears [playedThisTurn].
  /// Does NOT move champions — they persist in [championsInPlay].
  List<CardModel> cleanupTurn() {
    final List<CardModel> mercenaries = [];

    for (final card in playedThisTurn) {
      if (card.cardType == CardType.mercenary) {
        mercenaries.add(card);
      } else {
        discardPile.add(card);
      }
    }
    playedThisTurn.clear();

    return mercenaries;
  }
}
