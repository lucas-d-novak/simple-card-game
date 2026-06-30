import 'dart:io';

import 'package:shards_server/lobby.dart';
import 'package:shards_server/persistence.dart';
import 'package:test/test.dart';

/// Build a started 2-player game inside a fresh lobby.
LobbyGame _startedGame(Lobby lobby) {
  final g = lobby.createGame(hostId: 'alice', seats: 2, name: 'Friday Night');
  lobby.joinGame(g.id, 'bob');
  lobby.startGame(g.id);
  return g;
}

void main() {
  group('GamePersistence — round-trip (survive restart)', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('shards_persist_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('create + start + mutate, persist, then load into a FRESH lobby '
        'restores stateVersion, hands, and turn', () {
      // --- Original server: build a game and mutate it. ---
      final store = GamePersistence.open(tmp.path);
      expect(store.enabled, isTrue);

      final lobby = Lobby();
      final g = _startedGame(lobby);
      final session = g.session!;
      store.save(g); // persist on start

      final currentLobbyId =
          session.playerIds[session.game.currentPlayerIndex];
      final seat = session.game.currentPlayerIndex;

      // Mutate: play the whole hand (gems rise, hand shrinks), then persist.
      final handBefore = session.game.players[seat].hand.length;
      session.apply(currentLobbyId, {'type': 'playAllCards'});
      store.save(g);

      final versionBefore = session.stateVersion;
      final gemsBefore = session.game.players[seat].gemPool;
      final handAfter = session.game.players[seat].hand.length;
      final turnBefore = session.game.currentPlayerIndex;
      final hands = [
        for (final p in session.game.players)
          p.hand.map((c) => c.id).toList(),
      ];

      expect(handAfter, lessThan(handBefore),
          reason: 'sanity: playing the hand should shrink it');

      // --- Simulated restart: brand-new store + brand-new lobby. ---
      final freshStore = GamePersistence.open(tmp.path);
      final freshLobby = Lobby();
      final restored = freshStore.loadInto(freshLobby);
      expect(restored, 1);

      final rg = freshLobby.game(g.id);
      expect(rg, isNotNull);
      final rsession = rg!.session;
      expect(rsession, isNotNull);

      // Metadata survived.
      expect(rg.name, 'Friday Night');
      expect(rg.hostId, 'alice');
      expect(rg.seats, 2);
      expect(rg.status, GameStatus.started);
      expect(rsession!.playerIds, ['alice', 'bob']);

      // Authoritative state survived.
      expect(rsession.stateVersion, versionBefore,
          reason: 'stateVersion must survive a restart');
      expect(rsession.game.currentPlayerIndex, turnBefore,
          reason: 'whose turn it is must survive');
      expect(rsession.game.players[seat].gemPool, gemsBefore,
          reason: 'resource pools must survive');
      for (var i = 0; i < hands.length; i++) {
        expect(
          rsession.game.players[i].hand.map((c) => c.id).toList(),
          hands[i],
          reason: 'each player hand must survive intact',
        );
      }

      // The restored game is reconnectable (the existing resync path works).
      expect(freshLobby.activeGameForPlayer('alice')?.id, g.id);
      final view = rsession.viewFor('alice');
      expect(view['you'], isNotNull);
      expect(view['centerRow'], isA<List>());
    });

    test('id counter advances past restored ids so new games never collide', () {
      final store = GamePersistence.open(tmp.path);
      final lobby = Lobby();
      // Force a non-zero ordinal: create + discard two games so the persisted
      // one is game_2.
      lobby.createGame(hostId: 'x', seats: 2);
      lobby.createGame(hostId: 'y', seats: 2);
      final g = _startedGame(lobby); // game_2
      store.save(g);

      final freshStore = GamePersistence.open(tmp.path);
      final freshLobby = Lobby();
      freshStore.loadInto(freshLobby);

      // A newly created game must NOT reuse the restored id.
      final created = freshLobby.createGame(hostId: 'z', seats: 2);
      expect(created.id, isNot(g.id));
      expect(freshLobby.game(g.id), isNotNull,
          reason: 'restored game still present after creating a new one');
    });

    test('a corrupt snapshot file is skipped, not fatal', () {
      final store = GamePersistence.open(tmp.path);
      final lobby = Lobby();
      final g = _startedGame(lobby);
      store.save(g);

      // Drop a garbage .json next to the valid one.
      File('${tmp.path}/garbage.json').writeAsStringSync('{ not valid');

      final freshStore = GamePersistence.open(tmp.path);
      final freshLobby = Lobby();
      final restored = freshStore.loadInto(freshLobby);
      expect(restored, 1, reason: 'the valid game still loads; garbage skipped');
      expect(freshLobby.game(g.id), isNotNull);
    });

    test('a waiting (not-yet-started) game persists metadata without a session',
        () {
      final store = GamePersistence.open(tmp.path);
      final lobby = Lobby();
      final g = lobby.createGame(hostId: 'alice', seats: 2, name: 'Lobby Only');
      store.save(g);

      final freshLobby = Lobby();
      GamePersistence.open(tmp.path).loadInto(freshLobby);
      final rg = freshLobby.game(g.id);
      expect(rg, isNotNull);
      expect(rg!.status, GameStatus.waiting);
      expect(rg.name, 'Lobby Only');
      expect(rg.players, ['alice']);
      expect(rg.session, isNull);
    });

    test('disabled store no-ops: save/load do nothing, never throw', () {
      final store = GamePersistence.disabled();
      expect(store.enabled, isFalse);
      final lobby = Lobby();
      final g = _startedGame(lobby);
      // Should not throw and should write nothing.
      store.save(g);
      final freshLobby = Lobby();
      expect(store.loadInto(freshLobby), 0);
      expect(freshLobby.game(g.id), isNull);
    });

    test('completed games are persisted with complete status', () {
      final store = GamePersistence.open(tmp.path);
      final lobby = Lobby();
      final g = _startedGame(lobby);
      g.status = GameStatus.complete;
      store.save(g);

      final freshLobby = Lobby();
      GamePersistence.open(tmp.path).loadInto(freshLobby);
      expect(freshLobby.game(g.id)?.status, GameStatus.complete);
    });
  });
}
