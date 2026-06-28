import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';

/// Mutable per-player state for a Shards of Infinity game.
class PlayerState {
  PlayerState({required this.id, required this.name});

  final String id;
  final String name;

  int health = 50;
  int mastery = 0;
  int gemPool = 0;
  int powerPool = 0;

  final List<CardModel> hand = [];
  final List<CardModel> drawPile = [];
  final List<CardModel> discardPile = [];
  final List<CardModel> playedThisTurn = [];
  final List<CardModel> championsInPlay = [];
  final Set<String> activatedChampions = {};

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
    activatedChampions.clear();
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
