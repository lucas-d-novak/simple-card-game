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

    test('the cards dictionary defines every VISIBLE card by id, and NEVER an '
        'opponent hand card', () {
      final game = GameService(playerCount: 2);
      final view = redactFor(game, 'p0', stateVersion: 1);
      final cards = view['cards'] as Map;

      // Every center-row card is defined (so the client renders real content).
      for (final id in (view['centerRow'] as List)) {
        expect(cards.containsKey(id), isTrue,
            reason: 'center-row card $id must be in the dictionary');
        expect((cards[id] as Map)['name'], isA<String>());
      }

      // p0's OWN hand cards are defined.
      final players = (view['players'] as List).cast<Map>();
      final p0 = players.firstWhere((p) => p['id'] == 'p0');
      for (final id in (p0['hand'] as List)) {
        expect(cards.containsKey(id), isTrue,
            reason: 'own hand card $id must be in the dictionary');
      }

      // p1's hand card ids must NOT appear in the dictionary sent to p0 — the
      // dictionary is a new engine->wire path and must not leak hidden cards.
      final p1Hand = game.players[1].hand.map((c) => c.id).toSet();
      for (final id in p1Hand) {
        expect(cards.containsKey(id), isFalse,
            reason: "opponent hand card $id must NOT be in p0's dictionary");
      }
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

    test('undo restores the pre-action state (gems + hand revert)', () {
      final g = startedGame();
      final session = g.session!;
      final current = session.playerIds[session.game.currentPlayerIndex];
      final seat = session.game.currentPlayerIndex;

      final gemsBefore = session.game.players[seat].gemPool;
      final handBefore = session.game.players[seat].hand.length;

      // Play the whole hand: gems rise, hand empties.
      session.apply(current, {'type': 'playAllCards'});
      expect(session.game.players[seat].gemPool, greaterThan(gemsBefore));
      expect(session.game.players[seat].hand.length, lessThan(handBefore));

      // Undo: the snapshot taken BEFORE playAllCards is restored.
      final undo = session.apply(current, {'type': 'undo'});
      expect(undo.accepted, isTrue);
      expect(session.game.players[seat].gemPool, gemsBefore,
          reason: 'undo must revert the gem gain');
      expect(session.game.players[seat].hand.length, handBefore,
          reason: 'undo must return the played cards to hand');
    });

    test('undo is REJECTED for the off-turn player', () {
      final g = startedGame();
      final session = g.session!;
      final current = session.playerIds[session.game.currentPlayerIndex];
      final offTurn =
          session.playerIds[(session.game.currentPlayerIndex + 1) % 2];

      // Give the current player something to undo.
      session.apply(current, {'type': 'playAllCards'});

      final rejected = session.apply(offTurn, {'type': 'undo'});
      expect(rejected.accepted, isFalse);
      expect(rejected.error, contains('not your turn'));
    });

    test('undo is REJECTED at the start of a turn (empty stack)', () {
      final g = startedGame();
      final session = g.session!;
      final current = session.playerIds[session.game.currentPlayerIndex];

      final rejected = session.apply(current, {'type': 'undo'});
      expect(rejected.accepted, isFalse);
      expect(rejected.error, contains('nothing to undo'));
    });

    test('endTurn CLEARS the undo stack — you cannot undo after passing', () {
      final g = startedGame();
      final session = g.session!;
      final p0 = session.playerIds[session.game.currentPlayerIndex];

      // p0 acts, then ends their turn.
      session.apply(p0, {'type': 'playAllCards'});
      session.apply(p0, {'type': 'endTurn'});

      // Now it's p1's turn; p1 cannot undo into p0's finished turn.
      final p1 = session.playerIds[session.game.currentPlayerIndex];
      final rejected = session.apply(p1, {'type': 'undo'});
      expect(rejected.accepted, isFalse);
      expect(rejected.error, contains('nothing to undo'));
    });

    test('a successful undo bumps the state version', () {
      final g = startedGame();
      final session = g.session!;
      final current = session.playerIds[session.game.currentPlayerIndex];

      session.apply(current, {'type': 'playAllCards'});
      final vBefore = session.stateVersion;
      final undo = session.apply(current, {'type': 'undo'});
      expect(undo.accepted, isTrue);
      expect(session.stateVersion, greaterThan(vBefore));
    });

    test('canUndo flag is false at turn start, true after an action, and only '
        'on the actor\'s own view', () {
      final g = startedGame();
      final session = g.session!;
      final seat = session.game.currentPlayerIndex;
      final current = session.playerIds[seat];
      final offTurn = session.playerIds[(seat + 1) % 2];

      // Start of turn: nothing to undo.
      expect(session.viewFor(current)['canUndo'], isFalse);

      session.apply(current, {'type': 'playAllCards'});
      // The current player now sees canUndo; the off-turn player never does.
      expect(session.viewFor(current)['canUndo'], isTrue);
      expect(session.viewFor(offTurn)['canUndo'], isFalse);
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

    test('reconnect: activeGameForPlayer finds a seated player\'s live game and '
        'viewFor gives a complete resync', () {
      final lobby = Lobby();
      final g = lobby.createGame(hostId: 'alice', seats: 2);
      lobby.joinGame(g.id, 'bob');
      lobby.startGame(g.id);

      // Both seated players resolve to the live game (the reconnect lookup).
      expect(lobby.activeGameForPlayer('alice')?.id, g.id);
      expect(lobby.activeGameForPlayer('bob')?.id, g.id);
      // A non-player does not.
      expect(lobby.activeGameForPlayer('carol'), isNull);

      // The resync view a reconnecting client receives is a full redacted state
      // (own hand present, turn info, undo flag) — not an empty/stale shell.
      final view = g.session!.viewFor('alice');
      expect(view['you'], isNotNull);
      expect(view['players'], isA<List>());
      expect(view.containsKey('canUndo'), isTrue);
      expect(view['centerRow'], isA<List>());
    });

    test('reconnect: a completed game is NOT returned as active', () {
      final lobby = Lobby();
      final g = lobby.createGame(hostId: 'alice', seats: 2);
      lobby.joinGame(g.id, 'bob');
      lobby.startGame(g.id);
      g.status = GameStatus.complete;
      expect(lobby.activeGameForPlayer('alice'), isNull);
    });

    test('game name: custom name is used; blank falls back to default', () {
      final lobby = Lobby();
      final named = lobby.createGame(hostId: 'alice', seats: 2, name: 'Friday Night');
      expect(named.name, 'Friday Night');
      expect(named.toSummary()['name'], 'Friday Night');

      final unnamed = lobby.createGame(hostId: 'bob', seats: 2);
      expect(unnamed.name, "bob's game");

      final blank = lobby.createGame(hostId: 'carol', seats: 2, name: '   ');
      expect(blank.name, "carol's game", reason: 'whitespace falls back');
    });
  });
}
