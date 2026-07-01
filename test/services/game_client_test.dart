import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/services/game_client.dart';

/// Unit tests for the [GameClient] state flags added for spectate + the
/// server-restart heads-up. These exercise the observable public surface
/// without a live WebSocket (senders are no-ops when no socket is attached).
void main() {
  test('a fresh client is not spectating and shows no restart heads-up', () {
    final c = GameClient(playerId: 'alice');
    expect(c.spectating, isFalse);
    expect(c.serverRestarting, isFalse);
    expect(c.inGame, isFalse);
  });

  test('spectateGame marks the client as spectating', () {
    final c = GameClient(playerId: 'alice');
    c.spectateGame('game_0');
    expect(c.spectating, isTrue);
  });

  test('stopSpectate clears the spectator view so the lobby will not re-enter '
      'the game', () {
    final c = GameClient(playerId: 'alice')
      ..spectateGame('game_0')
      ..gameState = {'you': ''} // simulate a spectator state push
      ..currentGameId = 'game_0';
    expect(c.inGame, isTrue);

    var notified = false;
    c.addListener(() => notified = true);
    c.stopSpectate();

    expect(c.spectating, isFalse);
    expect(c.gameState, isNull);
    expect(c.currentGameId, isNull);
    expect(c.inGame, isFalse);
    expect(notified, isTrue, reason: 'the UI must be told to rebuild');
  });

  test('stopSpectate is a no-op when not spectating', () {
    final c = GameClient(playerId: 'alice')..gameState = {'you': 'p0'};
    c.stopSpectate();
    // The in-game (player) state is left untouched.
    expect(c.gameState, isNotNull);
  });

  test('a deliberate disconnect never raises the server-restart heads-up', () {
    final c = GameClient(playerId: 'alice');
    c.disconnect();
    expect(c.serverRestarting, isFalse);
  });
}
