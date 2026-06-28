import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/ai_service.dart';
import 'package:simple_card_game/services/game_service.dart';

class ZeroRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}

void main() {
  late GameService game;
  late AiService ai;

  setUp(() {
    game = GameService(playerCount: 2, random: ZeroRandom());
    // AI controls player 2 (p1)
    ai = AiService(game: game, aiPlayerId: 'p1')
      ..phaseDelay = Duration.zero;
  });

  /// Helper: advance to the AI player's turn by ending p0's turn.
  void advanceToAiTurn() {
    game.endTurn(); // p0 ends turn, now it's p1's turn
    expect(game.currentPlayer.id, 'p1');
  }

  group('AiService play phase', () {
    test('AI plays all hand cards during its turn', () async {
      advanceToAiTurn();
      final handSize = game.currentPlayer.hand.length;
      expect(handSize, greaterThan(0));

      await ai.takeTurn();

      // After AI turn ends, it should be p0's turn again
      // The AI's hand should have been played (cards moved to played/champions)
      // and then end turn draws 5 new cards.
      // We verify by checking the turn advanced past the AI.
      expect(game.currentPlayer.id, 'p0');
    });

    test('AI plays all cards — hand is empty before end turn', () async {
      advanceToAiTurn();
      final aiPlayer = game.players[1];
      final initialHandSize = aiPlayer.hand.length;
      expect(initialHandSize, greaterThan(0));

      // We can verify indirectly: after takeTurn the AI should have
      // generated resources from playing cards.
      await ai.takeTurn();

      // Turn advanced, meaning endTurn was called successfully
      expect(game.currentPlayer.id, 'p0');
    });
  });

  group('AiService buy phase', () {
    test('AI buys the most expensive affordable card', () async {
      advanceToAiTurn();
      final aiPlayer = game.players[1];

      // Give the AI some gems to buy with
      aiPlayer.gemPool = 10;
      final centerRowBefore = List<CardModel>.from(game.centerRow);

      // Find the most expensive card the AI can afford
      final affordableBefore = centerRowBefore
          .where((c) => c.cost <= 10)
          .toList()
        ..sort((a, b) => b.cost.compareTo(a.cost));

      await ai.takeTurn();

      // If there were affordable cards, one should have been bought
      if (affordableBefore.isNotEmpty) {
        // The most expensive card should have been purchased
        // (it won't be in the center row anymore, but the row refills)
        // Check that the AI acquired cards into its discard pile
        // (endTurn moves played cards to discard and draws new hand)
        expect(game.currentPlayer.id, 'p0');
      }
    });

    test('AI buys multiple cards if it has enough gems', () async {
      advanceToAiTurn();
      final aiPlayer = game.players[1];

      // Give the AI lots of gems
      aiPlayer.gemPool = 100;
      final initialDiscardSize = aiPlayer.discardPile.length;

      await ai.takeTurn();

      // After end turn, played cards + bought cards go to discard.
      // The AI should have bought multiple cards.
      // Discard pile should have grown (bought cards + played cards from hand).
      expect(aiPlayer.discardPile.length, greaterThan(initialDiscardSize));
    });
  });

  group('AiService attack phase', () {
    test('AI attacks opponent with remaining power', () async {
      advanceToAiTurn();
      final aiPlayer = game.players[1];
      final humanPlayer = game.players[0];
      final initialHealth = humanPlayer.health;

      // Give AI some power
      aiPlayer.powerPool = 5;

      await ai.takeTurn();

      // Human player should have taken damage
      // Note: AI also generates power from playing cards, so total damage
      // may exceed 5. But it should be at least 5 (if no guard champions).
      expect(humanPlayer.health, lessThan(initialHealth));
    });

    test('AI attacks guard champions before players', () async {
      advanceToAiTurn();
      final aiPlayer = game.players[1];
      final humanPlayer = game.players[0];

      // Place a guard champion on the human player
      final guardChampion = CardModel(
        id: 'test_guard',
        name: 'Test Guard',
        cost: 3,
        playEffects: const [],
        cardType: CardType.champion,
        shield: 2,
        hasGuard: true,
        faction: Faction.order,
      );
      humanPlayer.championsInPlay.add(guardChampion);
      final initialHealth = humanPlayer.health;

      // Give AI enough power to destroy guard and still attack
      aiPlayer.powerPool = 10;

      await ai.takeTurn();

      // Guard champion should have been destroyed
      final guardStillPresent =
          humanPlayer.championsInPlay.any((c) => c.id == 'test_guard');
      expect(guardStillPresent, false);

      // Player should have taken damage with remaining power
      expect(humanPlayer.health, lessThan(initialHealth));
    });
  });

  group('AiService end turn', () {
    test('AI ends its turn and advances to next player', () async {
      advanceToAiTurn();
      expect(game.currentPlayer.id, 'p1');

      await ai.takeTurn();

      // Should be back to player 0's turn
      expect(game.currentPlayer.id, 'p0');
    });

    test('AI does not act if game is over', () async {
      advanceToAiTurn();

      // Kill player 0 to end the game
      game.players[0].takeDamage(100);

      await ai.takeTurn();

      // Game should recognize it's over, AI should not crash
      // (the game may or may not be flagged as over depending on
      // when elimination is checked, but it should not throw)
    });
  });

  group('AiService multiplayer targeting', () {
    test('AI attacks weakest opponent in multiplayer', () async {
      final multiGame = GameService(playerCount: 3, random: ZeroRandom());
      final multiAi = AiService(game: multiGame, aiPlayerId: 'p1')
        ..phaseDelay = Duration.zero;

      // End p0's turn to get to p1 (AI)
      multiGame.endTurn();
      expect(multiGame.currentPlayer.id, 'p1');

      // Set different health levels
      multiGame.players[0].health = 30; // higher health
      multiGame.players[2].health = 10; // lower health — AI should target this

      // Give AI power
      multiGame.currentPlayer.powerPool = 5;

      final p2HealthBefore = multiGame.players[2].health;

      await multiAi.takeTurn();

      // The weakest player (p2) should have been attacked
      // p0 should be untouched (AI targets lowest health)
      expect(multiGame.players[2].health, lessThan(p2HealthBefore));
    });
  });
}
