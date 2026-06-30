import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/player_state.dart';
import 'package:simple_card_game/services/game_service.dart';

/// Undo mechanism coverage (LOCAL / solo game).
///
/// The local game has no rewindable engine — GameService mutates in place — so
/// the undo button in `game_screen.dart` is implemented as a stack of full
/// `GameStateCodec` snapshots: capture BEFORE a mutating action, then on undo
/// `decode` the snapshot back into a fresh GameService and swap it in.
///
/// These tests pin that exact mechanism at the engine level: for each
/// representative user action, snapshot -> mutate -> (snapshot != current) ->
/// decode -> (decoded signature == pre-action signature).

/// Structural signature of a player's observable state.
Map<String, dynamic> _playerSig(PlayerState p) => {
      'id': p.id,
      'health': p.health,
      'mastery': p.mastery,
      'gemPool': p.gemPool,
      'powerPool': p.powerPool,
      'hand': p.hand.map((c) => c.id).toList(),
      'drawPile': p.drawPile.map((c) => c.id).toList(),
      'discardPile': p.discardPile.map((c) => c.id).toList(),
      'playedThisTurn': p.playedThisTurn.map((c) => c.id).toList(),
      'championsInPlay': p.championsInPlay.map((c) => c.id).toList(),
      'activatedChampions': p.activatedChampions.toList()..sort(),
      'cardsPlayedThisTurn': p.cardsPlayedThisTurn.map((c) => c.id).toList(),
    };

Map<String, dynamic> _gameSig(GameService g) => {
      'players': g.players.map(_playerSig).toList(),
      'centerRow': g.centerRow.map((c) => c.id).toList(),
      'infinityDeck': g.infinityDeck.map((c) => c.id).toList(),
      'removedFromGame': g.removedFromGame.map((c) => c.id).toList(),
      'currentPlayerIndex': g.currentPlayerIndex,
      'turnNumber': g.turnNumber,
      'isGameOver': g.isGameOver,
      'winnerId': g.winnerId,
    };

/// Decode a snapshot the same way `_GameScreenState._undo` does.
GameService _undo(Map<String, dynamic> snapshot) =>
    GameStateCodec.decode(snapshot);

void main() {
  group('Undo via GameStateCodec snapshots', () {
    test('playCard: encode -> mutate -> decode restores prior state', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final before = _gameSig(game);
      final snapshot = GameStateCodec.encode(game);

      // Mutate: play the first hand card.
      final cardId = game.currentPlayer.hand.first.id;
      expect(game.playCard(cardId), isTrue);
      expect(_gameSig(game), isNot(before),
          reason: 'playing a card must change observable state');

      // Undo restores the captured state exactly.
      final restored = _undo(snapshot);
      expect(_gameSig(restored), before);
    });

    test('focus: snapshot/decode restores gems + mastery', () {
      final game = GameService(playerCount: 2, random: Random(7));
      // Give the player a gem to focus with.
      game.currentPlayer.gemPool = 3;
      final before = _gameSig(game);
      final snapshot = GameStateCodec.encode(game);

      expect(game.focus(), isTrue);
      expect(game.currentPlayer.gemPool, 2);
      expect(game.currentPlayer.mastery, greaterThan(before['players'][0]
          ['mastery'] as int));

      final restored = _undo(snapshot);
      expect(_gameSig(restored), before);
      expect(restored.currentPlayer.gemPool, 3);
    });

    test('buyCard: snapshot/decode restores center row + discard', () {
      final game = GameService(playerCount: 2, random: Random(7));
      // Ensure the player can afford the cheapest center-row card.
      final target = game.centerRow
          .reduce((a, b) => a.cost <= b.cost ? a : b);
      game.currentPlayer.gemPool = target.cost + 5;
      final before = _gameSig(game);
      final snapshot = GameStateCodec.encode(game);

      expect(game.buyCard(target.id), isTrue);
      expect(_gameSig(game), isNot(before));

      final restored = _undo(snapshot);
      expect(_gameSig(restored), before);
    });

    test('attackPlayer: snapshot/decode restores opponent health + power', () {
      final game = GameService(playerCount: 2, random: Random(7));
      game.currentPlayer.powerPool = 5;
      final opponent = game.players.firstWhere((p) => p != game.currentPlayer);
      final before = _gameSig(game);
      final snapshot = GameStateCodec.encode(game);

      expect(game.attackPlayer(opponent.id, 5), isTrue);
      expect(opponent.health, lessThan(before['players'][1]['health'] as int));

      final restored = _undo(snapshot);
      expect(_gameSig(restored), before);
      final restoredOpp =
          restored.players.firstWhere((p) => p.id == opponent.id);
      expect(restoredOpp.health, before['players'][1]['health']);
    });

    test('activateChampion: snapshot/decode restores activation set', () {
      final game = GameService(playerCount: 2, random: Random(7));
      // Put a champion into play that has not been activated yet.
      final champ = game.infinityDeck.firstWhere(
        (c) => c.cardType == CardType.champion,
        orElse: () => game.centerRow.firstWhere(
            (c) => c.cardType == CardType.champion,
            orElse: () => game.centerRow.first),
      );
      game.currentPlayer.championsInPlay.add(champ);
      final before = _gameSig(game);
      final snapshot = GameStateCodec.encode(game);

      final activated = game.activateChampion(champ.id);
      // Whether or not the champion had an effect, the activation set changes.
      if (activated) {
        expect(game.currentPlayer.activatedChampions, contains(champ.id));
        expect(_gameSig(game), isNot(before));
      }

      final restored = _undo(snapshot);
      expect(_gameSig(restored), before);
      expect(restored.currentPlayer.activatedChampions, isNot(contains(champ.id)));
    });

    test('multi-step undo: stack of snapshots steps back one action at a time',
        () {
      final game = GameService(playerCount: 2, random: Random(7));
      final stack = <Map<String, dynamic>>[];

      final sig0 = _gameSig(game);

      // Action 1: play a card.
      stack.add(GameStateCodec.encode(game));
      game.playCard(game.currentPlayer.hand.first.id);
      final sig1 = _gameSig(game);

      // Action 2: play another card.
      stack.add(GameStateCodec.encode(game));
      if (game.currentPlayer.hand.isNotEmpty) {
        game.playCard(game.currentPlayer.hand.first.id);
      }

      // Undo action 2 -> back to sig1.
      var restored = _undo(stack.removeLast());
      expect(_gameSig(restored), sig1);

      // Undo action 1 -> back to sig0.
      restored = _undo(stack.removeLast());
      expect(_gameSig(restored), sig0);
      expect(stack, isEmpty);
    });

    test('undo does not desync a fresh GameService used by an AiService '
        '(decoded engine is independent)', () {
      final game = GameService(playerCount: 2, random: Random(7));
      final snapshot = GameStateCodec.encode(game);
      game.playCard(game.currentPlayer.hand.first.id);

      final restored = _undo(snapshot);
      // The restored engine is a distinct instance from the mutated one, so an
      // AiService rebuilt against `restored` cannot observe the discarded
      // mutation (the desync the swap-and-rebuild logic guards against).
      expect(identical(restored, game), isFalse);
      expect(_gameSig(restored), isNot(_gameSig(game)));
    });
  });
}
