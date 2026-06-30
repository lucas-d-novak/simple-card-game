// Seed a live networked game on a running server so the polished
// NetworkGameScreen can be screenshotted mid-game.
//
// Connects "bob" over WebSocket, creates a 2-seat game, and waits. A browser
// then connects as "alice" (?online=1, Join) to fill the second seat — the game
// auto-starts and both get a mid-game board. bob then plays/ends a turn on a
// short delay so the board has champions/played cards to show.
//
// Run: dart run bin/seed_demo.dart [ws://host:8080] [hostName] [seats]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'ws://localhost:8080';
  final name = args.length > 1 ? args[1] : 'bob';
  final seats = args.length > 2 ? int.parse(args[2]) : 2;

  final ws = await WebSocket.connect(url);
  String? gameId;
  // ignore: avoid_print
  print('[$name] connected to $url');

  void send(Map<String, dynamic> m) => ws.add(jsonEncode(m));

  send({'type': 'identify', 'playerId': name});

  ws.listen((data) {
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'welcome':
        send({'type': 'createGame', 'seats': seats});
      case 'created':
        gameId = msg['gameId'] as String?;
        // ignore: avoid_print
        print('[$name] created game $gameId — waiting for a player to join…');
      case 'state':
        final state = msg['state'] as Map<String, dynamic>;
        final cpi = state['currentPlayerIndex'] as int;
        final players = (state['players'] as List).cast<Map>();
        // The redacted state identifies us via `you` (engine seat id), NOT the
        // lobby name. Match on that.
        final myId = state['you'] as String?;
        final me = players.firstWhere((p) => p['id'] == myId,
            orElse: () => players.first);
        final myTurn = players[cpi]['id'] == myId;
        // ignore: avoid_print
        print('[$name] state turn=${state['turnNumber']} '
            'myTurn=$myTurn hp=${me['health']} gems=${me['gemPool']}');
        if (myTurn && gameId != null) {
          // Play everything and end the turn after a beat so the board shows
          // played cards, then hand the turn back.
          Timer(const Duration(milliseconds: 600), () {
            send({'type': 'playAllCards', 'gameId': gameId});
            Timer(const Duration(milliseconds: 600), () {
              send({'type': 'endTurn', 'gameId': gameId});
            });
          });
        }
      case 'error':
        // ignore: avoid_print
        print('[$name] error: ${msg['error']}');
    }
  });

  // Keep alive so the game persists for the browser/screenshot.
  await Future<void>.delayed(const Duration(minutes: 10));
  await ws.close();
}
