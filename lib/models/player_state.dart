import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';

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

  final List<CardModel> hand = [];
  final List<CardModel> drawPile = [];
  final List<CardModel> discardPile = [];
  final List<CardModel> playedThisTurn = [];
  final List<CardModel> championsInPlay = [];

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
    activatedChampions.clear();
    exhaustedChampions.clear();
    cardsPlayedThisTurn.clear();
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
