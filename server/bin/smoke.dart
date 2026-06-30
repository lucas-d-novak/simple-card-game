// Smoke test: prove the pure-Dart server can import and drive the shared engine
// (GameService + serialization) WITHOUT the Flutter SDK at runtime.
// Run: dart run bin/smoke.dart

import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/services/game_service.dart';

void main() {
  final game = GameService(playerCount: 2);
  game.playAllCards();

  final snapshot = GameStateCodec.encode(game);
  final restored = GameStateCodec.decode(snapshot);

  // ignore: avoid_print
  print('engine OK on the server runtime: '
      'players=${restored.players.length} '
      'turn=${restored.turnNumber} '
      'centerRow=${restored.centerRow.length} '
      'p0.hand=${restored.players[0].hand.length}');
}
