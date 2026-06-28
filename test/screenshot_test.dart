import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/screens/game_screen.dart';
import 'package:simple_card_game/ui/screens/game_setup_screen.dart';

/// Screenshot golden tests for visual QA.
///
/// Run to generate/update screenshots:
///   flutter test test/screenshot_test.dart --update-goldens
///
/// Run to compare against saved screenshots:
///   flutter test test/screenshot_test.dart
///
/// Screenshots are saved to test/goldens/
void main() {
  group('Game screenshots', () {
    testWidgets('01 - Setup screen', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: GameSetupScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/01_setup_screen.png'),
      );
    });

    testWidgets('02 - Game start (initial hand)', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final game = GameService(playerCount: 2, random: Random(42));

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(gameService: game),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/02_game_start.png'),
      );
    });

    testWidgets('03 - After playing cards', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final game = GameService(playerCount: 2, random: Random(42));
      // Play all hand cards
      game.playAllCards();

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(gameService: game),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/03_after_play.png'),
      );
    });

    testWidgets('04 - Mid-game with champions and resources', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final game = GameService(playerCount: 2, random: Random(42));

      // Simulate a few turns to get an interesting game state
      for (int turn = 0; turn < 6; turn++) {
        game.playAllCards();
        // Buy cheapest affordable card if possible
        final affordable = game.centerRow
            .where((c) => c.cost <= game.currentPlayer.gemPool)
            .toList();
        if (affordable.isNotEmpty) {
          affordable.sort((a, b) => a.cost.compareTo(b.cost));
          game.buyCard(affordable.first.id);
        }
        game.endTurn();
      }

      // Play cards on current turn for visual interest
      game.playAllCards();

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(gameService: game),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/04_mid_game.png'),
      );
    });

    testWidgets('05 - Game over screen', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final game = GameService(playerCount: 2, random: Random(42));

      // Force a game over by eliminating opponent
      final opponent = game.players[1];
      opponent.takeDamage(opponent.health);

      // Play to trigger game over check
      game.playAllCards();
      if (game.currentPlayer.powerPool > 0) {
        game.attackPlayer(opponent.id, game.currentPlayer.powerPool);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(gameService: game),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/05_game_over.png'),
      );
    });

    testWidgets('06 - 3 player game', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final game = GameService(playerCount: 3, random: Random(42));
      game.playAllCards();

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(gameService: game),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/06_three_player.png'),
      );
    });
  });
}
