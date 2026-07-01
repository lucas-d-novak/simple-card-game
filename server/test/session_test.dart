import 'dart:math';

import 'package:shards_server/game_session.dart';
import 'package:shards_server/lobby.dart';
import 'package:shards_server/views.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
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

    test('recipient gets their OWN draw-pile CONTENTS sorted (no order leak), '
        'opponents do not', () {
      final game = GameService(playerCount: 2);
      final view = redactFor(game, 'p0', stateVersion: 1);
      final players = (view['players'] as List).cast<Map>();
      final p0 = players.firstWhere((p) => p['id'] == 'p0');
      final p1 = players.firstWhere((p) => p['id'] == 'p1');

      // p0 sees its own draw-pile contents, and they are SORTED (so the real
      // shuffle ORDER is not recoverable).
      final contents = (p0['drawPileContents'] as List).cast<String>();
      expect(contents.length, game.players[0].drawPile.length);
      final sorted = [...contents]..sort();
      expect(contents, sorted, reason: 'contents must be sorted, hiding order');

      // p0 does NOT receive p1's draw-pile contents.
      expect(p1.containsKey('drawPileContents'), isFalse,
          reason: "opponent draw-pile contents must never be in p0's view");
    });

    test('the action log is shipped (public) and ordered oldest-first', () {
      final game = GameService(playerCount: 2);
      game.playAllCards();
      game.endTurn();
      final view = redactFor(game, 'p0', stateVersion: 1);
      final log = (view['actionLog'] as List).cast<Map>();
      expect(log, isNotEmpty);
      expect(log.first['turn'], isA<int>());
      expect(log.last['message'], isA<String>());
    });

    test('a played-card log entry carries a cardId that is in the dictionary '
        '(so the playback overlay can show a mini card)', () {
      final game = GameService(playerCount: 2);
      game.playAllCards();
      final view = redactFor(game, 'p0', stateVersion: 1);
      final log = (view['actionLog'] as List).cast<Map>();
      final cards = view['cards'] as Map;

      final played = log.where((e) => e['cardId'] != null).toList();
      expect(played, isNotEmpty,
          reason: 'playing cards should log entries with a cardId');
      for (final e in played) {
        final id = e['cardId'] as String;
        expect(cards.containsKey(id), isTrue,
            reason: 'a public log-entry cardId ($id) must be resolvable '
                'in the recipient dictionary');
      }
    });

    test('no action-log entry cardId leaks a HIDDEN card id (opponent hand or '
        'any draw pile) — hidden-info safety', () {
      // Drive a couple of turns so the log spans plays by both players and
      // cards move between zones (drawing shuffles discards into draw piles).
      final game = GameService(playerCount: 2, random: Random(7));
      game.playAllCards();
      game.endTurn(); // p1's turn
      game.playAllCards();
      game.endTurn(); // back to p0

      final view = redactFor(game, 'p0', stateVersion: 1);
      final log = (view['actionLog'] as List).cast<Map>();
      final loggedCardIds = {
        for (final e in log)
          if (e['cardId'] != null) e['cardId'] as String,
      };

      // Hidden from p0: p1's hand, AND every player's draw pile (order-secret,
      // contents count-only for opponents). No log cardId may name any of them.
      final hiddenIds = <String>{
        ...game.players[1].hand.map((c) => c.id),
        for (final p in game.players) ...p.drawPile.map((c) => c.id),
      };

      final leaked = loggedCardIds.intersection(hiddenIds);
      expect(leaked, isEmpty,
          reason: 'an action-log cardId leaked a hidden card: $leaked');

      // And every logged cardId that IS shipped must be a public, dictionaried
      // card (never a bare id with no backing definition the recipient can see).
      final cards = view['cards'] as Map;
      for (final id in loggedCardIds) {
        expect(cards.containsKey(id), isTrue,
            reason: 'logged cardId $id must be a public dictionaried card');
      }
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

    test('fastPlayMercenary pays + plays + removes a center-row mercenary', () {
      final g = startedGame();
      final session = g.session!;
      final seat = session.game.currentPlayerIndex;
      final current = session.playerIds[seat];

      // Seed an affordable mercenary into the center row and give gems.
      session.game.centerRow
        ..clear()
        ..add(const CardModel(
          id: 'merc_x',
          name: 'Merc X',
          cost: 3,
          cardType: CardType.mercenary,
          playEffects: [GainPowerEffect(5)],
        ));
      session.game.players[seat].gemPool = 5;

      final res =
          session.apply(current, {'type': 'fastPlayMercenary', 'cardId': 'merc_x'});
      expect(res.accepted, isTrue);
      expect(session.game.players[seat].powerPool, 5,
          reason: 'effect resolved');
      expect(session.game.removedFromGame.any((c) => c.id == 'merc_x'), isTrue,
          reason: 'mercenary removed from game, not to discard');
      expect(session.game.players[seat].discardPile.any((c) => c.id == 'merc_x'),
          isFalse);
    });

    test('fastPlayMercenary is rejected off-turn', () {
      final g = startedGame();
      final session = g.session!;
      final offTurn =
          session.playerIds[(session.game.currentPlayerIndex + 1) % 2];
      final rejected =
          session.apply(offTurn, {'type': 'fastPlayMercenary', 'cardId': 'x'});
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

    test('multi-game: activeGameForPlayer returns the MOST-RECENT game; '
        'activeGamesForPlayer lists all in id order', () {
      final lobby = Lobby();
      // alice hosts game_0 with bob, then game_1 with carol — both start.
      final g0 = lobby.createGame(hostId: 'alice', seats: 2);
      lobby.joinGame(g0.id, 'bob');
      lobby.startGame(g0.id);
      final g1 = lobby.createGame(hostId: 'alice', seats: 2);
      lobby.joinGame(g1.id, 'carol');
      lobby.startGame(g1.id);

      // alice is in BOTH; the auto-resync picks the most recent (g1).
      expect(lobby.activeGameForPlayer('alice')?.id, g1.id);
      expect(
        lobby.activeGamesForPlayer('alice').map((g) => g.id).toList(),
        [g0.id, g1.id],
      );
      // bob is only in g0; carol only in g1.
      expect(lobby.activeGameForPlayer('bob')?.id, g0.id);
      expect(lobby.activeGameForPlayer('carol')?.id, g1.id);
    });

    test('resyncGame: a MEMBER can resync a specific game; a NON-MEMBER cannot',
        () {
      final lobby = Lobby();
      final g0 = lobby.createGame(hostId: 'alice', seats: 2);
      lobby.joinGame(g0.id, 'bob');
      lobby.startGame(g0.id);
      final g1 = lobby.createGame(hostId: 'alice', seats: 2);
      lobby.joinGame(g1.id, 'carol');
      lobby.startGame(g1.id);

      // alice (a member) can resync EITHER specific game by id.
      expect(lobby.resyncableGameForPlayer(g0.id, 'alice')?.id, g0.id);
      expect(lobby.resyncableGameForPlayer(g1.id, 'alice')?.id, g1.id);

      // bob is NOT a member of g1 → cannot resync it (hidden-info safe).
      expect(lobby.resyncableGameForPlayer(g1.id, 'bob'), isNull);
      // carol is NOT a member of g0.
      expect(lobby.resyncableGameForPlayer(g0.id, 'carol'), isNull);
      // A stranger can resync nothing.
      expect(lobby.resyncableGameForPlayer(g0.id, 'eve'), isNull);
      // Unknown game id → null.
      expect(lobby.resyncableGameForPlayer('game_999', 'alice'), isNull);
    });

    test('resyncGame: a NON-STARTED (waiting) game is not resyncable', () {
      final lobby = Lobby();
      final g = lobby.createGame(hostId: 'alice', seats: 2);
      // Still waiting (no second player) — not resyncable even for a member.
      expect(lobby.resyncableGameForPlayer(g.id, 'alice'), isNull);
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

  group('GameSession — Destiny / Relic + deferred selection (PART A/B)', () {
    // Build a 2-player session directly over a GameService injected with a
    // single-card Destiny supply, so the row deterministically holds that card.
    GameSession sessionWithDestiny(CardModel destiny) {
      final game = GameService(
        playerCount: 2,
        random: Random(7),
        destinySupply: [destiny],
      );
      return GameSession(
        id: 'g',
        game: game,
        playerIds: const ['alice', 'bob'],
      );
    }

    // A Destiny with no play effects (an activated-only style card) — claiming
    // it never routes through deferred-selection effect resolution.
    CardModel passiveDestiny() => const CardModel(
          id: 'destiny_test',
          name: 'Test Destiny',
          cost: 0,
          playEffects: [],
        );

    test('claimDestiny is ACCEPTED on your turn at Mastery 5 with a row card',
        () {
      final destiny = passiveDestiny();
      final session = sessionWithDestiny(destiny);
      // alice (seat 0) is the current player; raise her mastery to the threshold.
      session.game.players[0].mastery = GameService.destinyClaimMastery;
      expect(session.game.destinyRow.any((c) => c.id == destiny.id), isTrue);

      final result =
          session.apply('alice', {'type': 'claimDestiny', 'cardId': destiny.id});
      expect(result.accepted, isTrue);
      expect(session.game.players[0].claimedDestinies.map((c) => c.id),
          contains(destiny.id));
      // The row no longer offers it.
      expect(session.game.destinyRow.any((c) => c.id == destiny.id), isFalse);
    });

    test('claimDestiny is REJECTED below the mastery threshold', () {
      final destiny = passiveDestiny();
      final session = sessionWithDestiny(destiny);
      // alice is at Mastery 0 — under the threshold.
      final result =
          session.apply('alice', {'type': 'claimDestiny', 'cardId': destiny.id});
      expect(result.accepted, isFalse);
      expect(result.error, contains('illegal'));
      expect(session.game.players[0].claimedDestinies, isEmpty);
    });

    test('claimDestiny is REJECTED for the off-turn player', () {
      final destiny = passiveDestiny();
      final session = sessionWithDestiny(destiny);
      // bob (seat 1) is NOT the current player; even at mastery he is gated.
      session.game.players[1].mastery = GameService.destinyClaimMastery;
      final result =
          session.apply('bob', {'type': 'claimDestiny', 'cardId': destiny.id});
      expect(result.accepted, isFalse);
      expect(result.error, contains('not your turn'));
    });

    test('redactFor exposes the face-up destinyRow (public) with its card '
        'definition, and claim eligibility', () {
      final destiny = passiveDestiny();
      final session = sessionWithDestiny(destiny);
      session.game.players[0].mastery = GameService.destinyClaimMastery;

      final view = session.viewFor('alice');
      expect((view['destinyRow'] as List), contains(destiny.id));
      expect((view['cards'] as Map).containsKey(destiny.id), isTrue,
          reason: 'a face-up Destiny must be dictionaried for rendering');
      final me = (view['players'] as List)
          .cast<Map>()
          .firstWhere((p) => p['id'] == 'p0');
      expect(me['canClaimAnotherDestiny'], isTrue);
    });

    test('redactFor ships exhaustedDestinies so the tray can grey used '
        'abilities', () {
      // A claimed Destiny carrying an activated ability.
      const activated = CardModel(
        id: 'destiny_active',
        name: 'Active Destiny',
        cost: 0,
        playEffects: [],
        activatedAbility:
            ActivatedAbility(effects: [GainGemsEffect(1)]),
      );
      final session = sessionWithDestiny(activated);
      final alice = session.game.players[0];
      alice.mastery = GameService.destinyClaimMastery;
      expect(
          session.apply('alice',
              {'type': 'claimDestiny', 'cardId': activated.id}).accepted,
          isTrue);

      // Before use: the id is NOT in exhaustedDestinies.
      var me = (session.viewFor('alice')['players'] as List)
          .cast<Map>()
          .firstWhere((p) => p['id'] == 'p0');
      expect((me['exhaustedDestinies'] as List), isNot(contains(activated.id)));

      // Use the Destiny ability, then it IS reported exhausted this turn.
      expect(
          session.apply('alice',
              {'type': 'useDestinyAbility', 'cardId': activated.id}).accepted,
          isTrue);
      me = (session.viewFor('alice')['players'] as List)
          .cast<Map>()
          .firstWhere((p) => p['id'] == 'p0');
      expect((me['exhaustedDestinies'] as List), contains(activated.id));
    });

    test('recruitRelic is ACCEPTED at Mastery 10 with relic options; the chosen '
        'relic is kept and the other banished', () {
      final session = sessionWithDestiny(passiveDestiny());
      final alice = session.game.players[0];
      alice.mastery = 10;
      // Set aside two relic options directly (the engine normally seeds these
      // from the player's Character).
      const relicA = CardModel(
          id: 'relic_a', name: 'Relic A', cost: 0, playEffects: []);
      const relicB = CardModel(
          id: 'relic_b', name: 'Relic B', cost: 0, playEffects: []);
      alice.relicOptions.addAll([relicA, relicB]);

      final result =
          session.apply('alice', {'type': 'recruitRelic', 'cardId': 'relic_a'});
      expect(result.accepted, isTrue);
      expect(alice.relicRecruited, isTrue);
      expect(alice.relicOptions, isEmpty);
      // The unchosen relic is banished.
      expect(session.game.removedFromGame.map((c) => c.id), contains('relic_b'));
    });

    test('recruitRelic is REJECTED below Mastery 10', () {
      final session = sessionWithDestiny(passiveDestiny());
      final alice = session.game.players[0];
      alice.mastery = 9;
      alice.relicOptions.add(const CardModel(
          id: 'relic_a', name: 'Relic A', cost: 0, playEffects: []));
      final result =
          session.apply('alice', {'type': 'recruitRelic', 'cardId': 'relic_a'});
      expect(result.accepted, isFalse);
      expect(alice.relicRecruited, isFalse);
    });

    test("relicOptions appear ONLY in the owner's redacted view (private)", () {
      final session = sessionWithDestiny(passiveDestiny());
      session.game.players[0].relicOptions.add(const CardModel(
          id: 'relic_a', name: 'Relic A', cost: 0, playEffects: []));

      // alice (seat p0) sees her own relic options + the card definition.
      final mine = session.viewFor('alice');
      final aliceView = (mine['players'] as List)
          .cast<Map>()
          .firstWhere((p) => p['id'] == 'p0');
      expect((aliceView['relicOptions'] as List), contains('relic_a'));
      expect((mine['cards'] as Map).containsKey('relic_a'), isTrue);

      // bob must NOT see alice's relic options, nor a dictionary entry for them.
      final theirs = session.viewFor('bob');
      final aliceFromBob = (theirs['players'] as List)
          .cast<Map>()
          .firstWhere((p) => p['id'] == 'p0');
      expect(aliceFromBob.containsKey('relicOptions'), isFalse,
          reason: "an opponent's relic CHOICE is hidden info");
      expect((theirs['cards'] as Map).containsKey('relic_a'), isFalse);
    });

    test('a deferred-selection action (banishCard) flows through apply()', () {
      final session = sessionWithDestiny(passiveDestiny());
      final alice = session.game.players[0];
      // Target a card actually in alice's hand so the engine accepts the banish.
      final target = alice.hand.first;
      final result = session.apply('alice', {
        'type': 'banishCard',
        'cardId': target.id,
        'source': BanishSource.handOrDiscard.name,
      });
      expect(result.accepted, isTrue);
      expect(session.game.removedFromGame.map((c) => c.id), contains(target.id));
      expect(alice.hand.map((c) => c.id), isNot(contains(target.id)));
    });

    test('banishCard with an unknown card id is rejected (illegal)', () {
      final session = sessionWithDestiny(passiveDestiny());
      final result = session.apply('alice', {
        'type': 'banishCard',
        'cardId': 'no_such_card',
        'source': BanishSource.handOrDiscard.name,
      });
      expect(result.accepted, isFalse);
      expect(result.error, contains('illegal'));
    });
  });
}
