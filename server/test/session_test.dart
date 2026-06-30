import 'package:shards_server/lobby.dart';
import 'package:shards_server/views.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:test/test.dart';

void main() {
  group('redactFor — hidden information (SECURITY)', () {
    test('a player sees their OWN hand but only opponent hand COUNTS', () {
      final game = GameService(playerCount: 2);
      // p0 is the current player after init; both have 5-card hands dealt.
      final viewForP0 = redactFor(game, 'p0', stateVersion: 1);
      final players = viewForP0['players'] as List;
      final p0 = players.firstWhere((p) => p['id'] == 'p0') as Map;
      final p1 = players.firstWhere((p) => p['id'] == 'p1') as Map;

      // p0 sees their own hand ids.
      expect(p0['hand'], isA<List>());
      expect(p0['handCount'], (p0['hand'] as List).length);
      // p0 does NOT see p1's hand ids — only a count.
      expect(p1.containsKey('hand'), isFalse,
          reason: "opponent hand ids must never be in another player's view");
      expect(p1['handCount'], isA<int>());
    });

    test('NOBODY sees any draw-pile order — only counts (incl. their own)', () {
      final game = GameService(playerCount: 2);
      final view = redactFor(game, 'p0', stateVersion: 1);
      for (final p in (view['players'] as List)) {
        final pm = p as Map;
        expect(pm.containsKey('drawPile'), isFalse,
            reason: 'draw-pile ORDER must never leak (scry/shuffle exploit)');
        expect(pm['drawPileCount'], isA<int>());
      }
    });

    test('infinity deck order is never sent — only a count', () {
      final game = GameService(playerCount: 2);
      final view = redactFor(game, 'p0', stateVersion: 1);
      expect(view.containsKey('infinityDeck'), isFalse);
      expect(view['infinityDeckCount'], isA<int>());
    });

    test('public zones (center row, discards) ARE visible', () {
      final game = GameService(playerCount: 2);
      final view = redactFor(game, 'p0', stateVersion: 1);
      expect(view['centerRow'], isA<List>());
      expect((view['centerRow'] as List), hasLength(6));
    });
  });

  group('GameSession — action authorization', () {
    LobbyGame startedGame() {
      final lobby = Lobby();
      final g = lobby.createGame(hostId: 'alice', seats: 2);
      lobby.joinGame(g.id, 'bob');
      lobby.startGame(g.id);
      return g;
    }

    test('the current player CAN act; an off-turn player CANNOT', () {
      final g = startedGame();
      final session = g.session!;
      // Seat 0 = alice is the current player at game start.
      final currentLobbyId = session.playerIds[session.game.currentPlayerIndex];
      final offTurnLobbyId =
          session.playerIds[(session.game.currentPlayerIndex + 1) % 2];

      final okResult = session.apply(currentLobbyId, {'type': 'playAllCards'});
      expect(okResult.accepted, isTrue);

      final rejected = session.apply(offTurnLobbyId, {'type': 'playAllCards'});
      expect(rejected.accepted, isFalse);
      expect(rejected.error, contains('not your turn'));
    });

    test('a non-player id is rejected', () {
      final g = startedGame();
      final rejected = g.session!.apply('eve', {'type': 'endTurn'});
      expect(rejected.accepted, isFalse);
    });

    test('accepted actions bump the state version', () {
      final g = startedGame();
      final session = g.session!;
      final v0 = session.stateVersion;
      final current = session.playerIds[session.game.currentPlayerIndex];
      session.apply(current, {'type': 'playAllCards'});
      expect(session.stateVersion, greaterThan(v0));
    });

    test('lobby flow: create -> join -> auto-start full game', () {
      final lobby = Lobby();
      final g = lobby.createGame(hostId: 'alice', seats: 2);
      expect(g.status, GameStatus.waiting);
      expect(g.isFull, isFalse);

      lobby.joinGame(g.id, 'bob');
      expect(g.isFull, isTrue);

      final session = lobby.startGame(g.id);
      expect(session, isNotNull);
      expect(g.status, GameStatus.started);
      expect(session!.playerIds, ['alice', 'bob']);

      // Joining a started game fails.
      expect(lobby.joinGame(g.id, 'carol'), isNull);
    });
  });
}
