// Tests for the player-stats + ML-training telemetry subsystem.
//
// Drives a short session through GameSession.apply (recruit, play, win) over an
// in-memory StatsStore and asserts:
//   * an `events` row for the recruit with the right cardId/cost,
//   * a `decisions` row for the recruit whose options include the center row and
//     whose selfState carries the actor's gems/health,
//   * recordGameEnd backfills `playerWon` on that player's decisions,
//   * the flat `decision_export` view returns rows,
//   * an OPPONENT's hand card ids NEVER appear in any recorded decision (the
//     hidden-info safety guarantee).

import 'dart:convert';
import 'dart:math';

import 'package:shards_server/game_session.dart';
import 'package:shards_server/stats_store.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:test/test.dart';

void main() {
  group('StatsStore — schema + graceful degradation', () {
    test('disabled store no-ops every call and never throws', () {
      final s = StatsStore.disabled();
      expect(s.enabled, isFalse);
      // None of these should throw or record anything.
      s.recordGameStart(gameId: 'g', players: ['a', 'b']);
      s.recordEvent(
          gameId: 'g', turn: 1, seat: 0, playerId: 'a', type: 'playCard');
      s.recordDecision(
        gameId: 'g',
        turn: 1,
        seat: 0,
        playerId: 'a',
        decisionType: 'recruit',
        chosenIndex: 0,
        options: const [],
        selfState: const {},
        oppState: const [],
        board: const {},
      );
      s.recordGameEnd(gameId: 'g', winnerId: 'a', winType: 'elimination', turns: 3);
      expect(s.query('SELECT * FROM events'), isEmpty);
      s.close();
    });

    test('open creates the three tables + the decision_export view', () {
      final s = StatsStore.inMemory();
      expect(s.enabled, isTrue);
      // sqlite_master lists every table + view we created.
      final names = s
          .query("SELECT name FROM sqlite_master WHERE type IN ('table','view')")
          .map((r) => r['name'])
          .toSet();
      expect(names, containsAll(['events', 'decisions', 'games', 'decision_export']));
      s.close();
    });
  });

  group('StatsStore — direct record + label join', () {
    test('recordGameEnd backfills playerWon (winner=1, loser=0) and the export '
        'view flattens self state', () {
      final s = StatsStore.inMemory();
      s.recordGameStart(gameId: 'g', players: ['alice', 'bob']);
      // Two decisions: one by the eventual winner, one by the loser.
      s.recordDecision(
        gameId: 'g', turn: 1, seat: 0, playerId: 'alice',
        decisionType: 'recruit', chosenIndex: 0,
        options: const [{'id': 'x'}],
        selfState: const {'health': 50, 'mastery': 0, 'gems': 3, 'power': 0,
          'handSize': 5, 'deckSize': 5, 'discardSize': 0},
        oppState: const [{'id': 'p1', 'health': 50, 'mastery': 0}],
        board: const {'infinityDeckCount': 90, 'turn': 1},
      );
      s.recordDecision(
        gameId: 'g', turn: 2, seat: 1, playerId: 'bob',
        decisionType: 'play', chosenIndex: 1,
        options: const [{'id': 'y'}],
        selfState: const {'health': 40, 'mastery': 1, 'gems': 0, 'power': 2,
          'handSize': 4, 'deckSize': 6, 'discardSize': 1},
        oppState: const [{'id': 'p0', 'health': 50, 'mastery': 0}],
        board: const {'infinityDeckCount': 89, 'turn': 2},
      );

      // Before end: playerWon is NULL.
      final before = s.query('SELECT playerWon FROM decisions');
      expect(before.every((r) => r['playerWon'] == null), isTrue);

      s.recordGameEnd(
          gameId: 'g', winnerId: 'alice', winType: 'elimination', turns: 5);

      // The supervised label join: alice's decision -> 1, bob's -> 0.
      final alice = s.query(
          "SELECT playerWon FROM decisions WHERE playerId = 'alice'");
      final bob = s.query(
          "SELECT playerWon FROM decisions WHERE playerId = 'bob'");
      expect(alice.single['playerWon'], 1);
      expect(bob.single['playerWon'], 0);

      // The games row is stamped.
      final game = s.query("SELECT * FROM games WHERE gameId = 'g'").single;
      expect(game['winnerId'], 'alice');
      expect(game['winType'], 'elimination');
      expect(game['turns'], 5);
      expect(game['startedTs'], isA<int>());
      expect(game['endedTs'], isA<int>());

      // The flat export view exposes the self_* columns + the label.
      final exp = s.query(
          "SELECT * FROM decision_export WHERE playerId = 'alice'").single;
      expect(exp['self_health'], 50);
      expect(exp['self_gems'], 3);
      expect(exp['opp_health'], 50);
      expect(exp['playerWon'], 1);
      s.close();
    });
  });

  group('emission via GameSession.apply', () {
    GameSession freshSession(StatsStore stats) {
      // Deterministic engine; 2 players. Build the session directly with the
      // store injected (the lobby path is exercised by the server, but a direct
      // session keeps this hermetic).
      final game = GameService(playerCount: 2, random: Random(7));
      final session = GameSession(
        id: 'g',
        game: game,
        playerIds: const ['alice', 'bob'],
        stats: stats,
      );
      // alice (seat 0) is current. Give her gems to recruit + power to attack.
      game.players[0].gemPool = 20;
      game.players[0].powerPool = 100;
      return session;
    }

    test('a recruit records BOTH an event (cardId/cost) and a decision (options '
        'include the center row; selfState has gems/health)', () {
      final stats = StatsStore.inMemory();
      final session = freshSession(stats);
      final game = session.game;

      final bought = game.centerRow.first; // a concrete center-row card
      final price = bought.cost;
      final gemsBefore = game.players[0].gemPool;

      final res = session.apply('alice', {'type': 'buyCard', 'cardId': bought.id});
      expect(res.accepted, isTrue);

      // --- the compact OUTCOME event ---
      final ev = stats
          .query("SELECT * FROM events WHERE type = 'buyCard'")
          .single;
      expect(ev['cardId'], bought.id);
      expect(ev['cardName'], bought.name);
      expect(ev['cost'], price);
      expect(ev['playerId'], 'alice');
      expect(ev['seat'], 0);

      // --- the rich DECISION record ---
      final dec = stats
          .query("SELECT * FROM decisions WHERE decisionType = 'recruit'")
          .single;
      final options = (jsonDecode(dec['options'] as String) as List);
      // Every center-row card (captured BEFORE the buy, so the bought card is in
      // the option set) is present, plus the implicit "pass".
      final optionIds = options.map((o) => (o as Map)['id']).toSet();
      expect(optionIds, contains(bought.id));
      expect(optionIds, contains('__pass__'));
      // The recruit options carry affordability + conditionsMet features.
      final boughtOpt = options
          .cast<Map>()
          .firstWhere((o) => o['id'] == bought.id);
      expect(boughtOpt.containsKey('affordable'), isTrue);
      expect(boughtOpt.containsKey('conditionsMet'), isTrue);
      // chosenIndex points at the bought card.
      expect(options[dec['chosenIndex'] as int], isA<Map>());
      expect((options[dec['chosenIndex'] as int] as Map)['id'], bought.id);

      // selfState carries the actor's pre-action resources.
      final self = jsonDecode(dec['selfState'] as String) as Map;
      expect(self['gems'], gemsBefore);
      expect(self['health'], game.players[0].health);
      stats.close();
    });

    test('a play records a decision whose options are the actor OWN hand', () {
      final stats = StatsStore.inMemory();
      final session = freshSession(stats);
      final game = session.game;
      final card = game.players[0].hand.first;

      final res = session.apply('alice', {'type': 'playCard', 'cardId': card.id});
      expect(res.accepted, isTrue);

      final dec = stats
          .query("SELECT * FROM decisions WHERE decisionType = 'play'")
          .single;
      final options = (jsonDecode(dec['options'] as String) as List).cast<Map>();
      expect(options.map((o) => o['id']), contains(card.id));
      stats.close();
    });

    test('HIDDEN-INFO: an opponent\'s hand card ids NEVER appear in any recorded '
        'decision (options/self/opp/board JSON)', () {
      final stats = StatsStore.inMemory();
      final session = freshSession(stats);
      final game = session.game;

      // The opponent's (bob, seat 1) hand card ids — these must never be captured.
      final oppHandIds = game.players[1].hand.map((c) => c.id).toSet();
      expect(oppHandIds, isNotEmpty);

      // Drive several decisions by the actor: recruit, play, attack.
      final centerCard = game.centerRow.first;
      session.apply('alice', {'type': 'buyCard', 'cardId': centerCard.id});
      session.apply(
          'alice', {'type': 'playCard', 'cardId': game.players[0].hand.first.id});
      session.apply(
          'alice', {'type': 'attackPlayer', 'targetId': 'p1', 'amount': 1});

      // Concatenate ALL JSON columns of every decision row and assert no opponent
      // hand id is present anywhere.
      final rows = stats.query(
          'SELECT options, selfState, oppState, board FROM decisions');
      expect(rows, isNotEmpty);
      final blob = rows
          .map((r) =>
              '${r['options']}${r['selfState']}${r['oppState']}${r['board']}')
          .join('|');
      for (final id in oppHandIds) {
        expect(blob.contains(id), isFalse,
            reason: "opponent hand card '$id' must never be recorded");
      }

      // Sanity: oppState DOES carry the opponent as a hand COUNT (not cards).
      final dec = stats
          .query("SELECT oppState FROM decisions WHERE decisionType = 'recruit'")
          .first;
      final opp = (jsonDecode(dec['oppState'] as String) as List).cast<Map>();
      final bob = opp.firstWhere((o) => o['id'] == 'p1');
      expect(bob['handCount'], game.players[1].hand.length);
      expect(bob.containsKey('hand'), isFalse,
          reason: 'opponent hand ids must never be a feature');
      stats.close();
    });

    test('a full game: recruit + attack-to-win backfills playerWon on the '
        'actor\'s decisions and the export view returns flattened rows', () {
      final stats = StatsStore.inMemory();
      final session = freshSession(stats);
      final game = session.game;
      stats.recordGameStart(gameId: 'g', players: const ['alice', 'bob']);

      // A recruit decision (so there is a labelable decision row).
      session.apply('alice', {'type': 'buyCard', 'cardId': game.centerRow.first.id});

      // alice attacks bob to 0 — elimination win (no guard champions at start).
      final bobHealth = game.players[1].health;
      final win = session.apply(
          'alice', {'type': 'attackPlayer', 'targetId': 'p1', 'amount': bobHealth});
      expect(win.accepted, isTrue);
      expect(game.isGameOver, isTrue);
      expect(game.winnerId, 'p0'); // engine seat id of alice

      // The server records game-end with the WINNER'S LOBBY id (the join key on
      // decisions is the lobby id, not the seat id). Simulate that step.
      stats.recordGameEnd(
          gameId: 'g', winnerId: 'alice', winType: 'elimination',
          turns: game.turnNumber);

      // alice's recruit decision is now labelled a win.
      final labelled = stats.query(
          "SELECT playerWon FROM decisions WHERE playerId = 'alice'");
      expect(labelled, isNotEmpty);
      expect(labelled.every((r) => r['playerWon'] == 1), isTrue);

      // The flat export view returns rows with the label populated.
      final exp = stats.query('SELECT * FROM decision_export');
      expect(exp, isNotEmpty);
      expect(exp.first.containsKey('self_gems'), isTrue);
      expect(exp.every((r) => r['playerWon'] == 1), isTrue);
      stats.close();
    });
  });
}
