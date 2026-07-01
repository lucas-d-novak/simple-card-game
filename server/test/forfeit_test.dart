import 'dart:io';

import 'package:shards_server/lobby.dart';
import 'package:shards_server/persistence.dart';
import 'package:shards_server/stats_capture.dart' show winTypeOf;
import 'package:test/test.dart';

/// Build a started 2-player game inside a fresh lobby.
LobbyGame _startedGame(Lobby lobby) {
  final g = lobby.createGame(hostId: 'alice', seats: 2, name: 'Test Game');
  lobby.joinGame(g.id, 'bob');
  lobby.startGame(g.id);
  return g;
}

void main() {
  group('Admin forfeit — ends the game as a completed FORFEIT', () {
    test('forfeit marks the game over with winType forfeit and NO winner', () {
      final lobby = Lobby();
      final g = _startedGame(lobby);
      final session = g.session!;

      final result = session.apply('alice', {
        'type': 'forfeit',
        'gameId': g.id,
      });

      expect(result.accepted, isTrue);
      expect(session.game.isGameOver, isTrue);
      expect(session.game.winType, 'forfeit');
      expect(session.game.winnerId, isNull,
          reason: 'a forfeit has no winner');
      // winTypeOf must surface the forfeit condition (NOT "none"/"draw"), so
      // the lobby past-games summary and telemetry label it correctly.
      expect(winTypeOf(session.game), 'forfeit');
      expect(session.winnerLobbyId, isNull);
    });

    test('ANY seated player may forfeit — even off their turn', () {
      final lobby = Lobby();
      final g = _startedGame(lobby);
      final session = g.session!;
      // Seat 0 (alice) is current at start; forfeit as the OFF-turn player.
      final offTurn =
          session.playerIds[(session.game.currentPlayerIndex + 1) % 2];

      final result = session.apply(offTurn, {
        'type': 'forfeit',
        'gameId': g.id,
      });

      expect(result.accepted, isTrue,
          reason: 'forfeit intentionally bypasses the turn gate');
      expect(session.game.winType, 'forfeit');
    });

    test('a non-player id cannot forfeit', () {
      final lobby = Lobby();
      final g = _startedGame(lobby);
      final result = g.session!.apply('mallory', {
        'type': 'forfeit',
        'gameId': g.id,
      });
      expect(result.accepted, isFalse);
      expect(g.session!.game.isGameOver, isFalse);
    });

    test('forfeiting an already-finished game is rejected', () {
      final lobby = Lobby();
      final g = _startedGame(lobby);
      final session = g.session!;
      expect(
          session.apply('alice', {'type': 'forfeit', 'gameId': g.id}).accepted,
          isTrue);
      final again =
          session.apply('bob', {'type': 'forfeit', 'gameId': g.id});
      expect(again.accepted, isFalse);
      expect(again.error, contains('over'));
    });

    test('a forfeited game round-trips through persistence as a completed '
        'forfeit (NOT a bogus draw)', () {
      final tmp = Directory.systemTemp.createTempSync('shards_forfeit_test_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      // --- Original server: start, forfeit, then mirror the server's
      // complete-transition bookkeeping (bin/server.dart) before persisting. ---
      final store = GamePersistence.open(tmp.path);
      final lobby = Lobby();
      final g = _startedGame(lobby);
      final session = g.session!;

      expect(
          session.apply('alice', {'type': 'forfeit', 'gameId': g.id}).accepted,
          isTrue);
      // The server marks the lobby game complete + stamps the result here.
      g.status = GameStatus.complete;
      g.winnerId = session.winnerLobbyId; // null
      g.winType = winTypeOf(session.game); // 'forfeit'
      store.save(g);

      // --- Simulated restart: brand-new store + lobby. ---
      final freshLobby = Lobby();
      final restored = GamePersistence.open(tmp.path).loadInto(freshLobby);
      expect(restored, 1);

      final rg = freshLobby.game(g.id)!;
      expect(rg.status, GameStatus.complete);
      expect(rg.winType, 'forfeit',
          reason: 'the forfeit condition must survive a restart');
      expect(rg.winnerId, isNull);
      expect(rg.session!.game.isGameOver, isTrue);
      expect(rg.session!.game.winType, 'forfeit');
      // The lobby summary a client sees carries the forfeit condition.
      expect(rg.toSummary()['winType'], 'forfeit');
    });
  });
}
