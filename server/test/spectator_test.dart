import 'package:shards_server/lobby.dart';
import 'package:shards_server/views.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:test/test.dart';

/// Build a started 2-player game inside a fresh lobby.
LobbyGame _startedGame(Lobby lobby) {
  final g = lobby.createGame(hostId: 'alice', seats: 2, name: 'Watch Me');
  lobby.joinGame(g.id, 'bob');
  lobby.startGame(g.id);
  return g;
}

void main() {
  group('Spectator view — NON-PARTICIPANT redaction (no hidden-info leak)', () {
    test('a spectator sees NOBODY\'s hand ids — only counts (opponent-level)',
        () {
      // Redact for a recipient id that matches no seat: the spectator view.
      final game = GameService(playerCount: 2);
      final view = redactFor(game, 'a-watcher-not-a-seat', stateVersion: 1);

      for (final p in (view['players'] as List).cast<Map>()) {
        expect(p.containsKey('hand'), isFalse,
            reason: 'a spectator must never receive any player\'s hand ids');
        expect(p['handCount'], isA<int>());
        // No draw-pile order OR contents for anyone (anti-scry).
        expect(p.containsKey('drawPile'), isFalse);
        expect(p.containsKey('drawPileContents'), isFalse,
            reason: 'own-draw-pile contents are recipient-only; a spectator '
                'is not the recipient of any seat');
        expect(p['drawPileCount'], isA<int>());
        // Relic options are a private choice — never in a spectator view.
        expect(p.containsKey('relicOptions'), isFalse);
      }
      // Deck order is never sent.
      expect(view.containsKey('infinityDeck'), isFalse);
      expect(view['infinityDeckCount'], isA<int>());
      // The spectator can't act: no undo affordance.
      expect(view['canUndo'], isFalse);
    });

    test('GameSession.spectatorView matches the non-participant redaction and '
        'leaks no more than a seated opponent already sees', () {
      final lobby = Lobby();
      final g = _startedGame(lobby);
      final session = g.session!;

      final spec = session.spectatorView();
      final players = (spec['players'] as List).cast<Map>();
      expect(players, hasLength(2));

      for (final p in players) {
        expect(p.containsKey('hand'), isFalse);
        expect(p.containsKey('drawPileContents'), isFalse);
        expect(p['handCount'], isA<int>());
        // Public board info a seated opponent also sees IS present.
        expect(p['discardPile'], isA<List>());
        expect(p['health'], isA<int>());
        expect(p['mastery'], isA<int>());
        // Usernames are resolved (spectators see real names, like anyone else).
        expect(p['name'], anyOf('alice', 'bob'));
      }
      // Public board state is present.
      expect(spec['centerRow'], isA<List>());
      expect(spec['canUndo'], isFalse);
      // The recipient marker is empty (matches no seat), so the client frames
      // this as a non-participant view.
      expect(spec['you'], '');
    });

    test('the spectator view is IDENTICAL in shape to what a real opponent '
        'gets for the other player\'s hidden zones', () {
      final lobby = Lobby();
      final g = _startedGame(lobby);
      final session = g.session!;

      final aliceView = session.viewFor('alice');
      final spec = session.spectatorView();

      Map bobIn(Map<String, dynamic> v) => (v['players'] as List)
          .cast<Map>()
          .firstWhere((p) => p['name'] == 'bob');

      final bobPerAlice = bobIn(aliceView); // opponent's slice
      final bobPerSpec = bobIn(spec); // spectator's slice

      // Neither exposes bob's hand ids; both expose the same count.
      expect(bobPerAlice.containsKey('hand'), isFalse);
      expect(bobPerSpec.containsKey('hand'), isFalse);
      expect(bobPerSpec['handCount'], bobPerAlice['handCount']);
      expect(bobPerSpec.containsKey('drawPileContents'), isFalse);
    });
  });
}
