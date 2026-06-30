import 'dart:math';

import 'package:flutter/material.dart';
import 'package:simple_card_game/services/deck_service.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/screens/game_screen.dart';
import 'package:simple_card_game/ui/screens/game_setup_screen.dart';
import 'package:simple_card_game/ui/screens/home_screen.dart';
import 'package:simple_card_game/ui/screens/about_screen.dart';
import 'package:simple_card_game/ui/screens/network_auto_screen.dart';
import 'package:simple_card_game/ui/screens/network_lobby_screen.dart';
import 'package:simple_card_game/ui/screens/online_lobby_screen.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';

/// Derive a default WebSocket server URL. An explicit `?server=` wins; otherwise
/// reuse the host the web build was loaded from, matching the page's SCHEME:
///   - https page → `wss://<host>/ws` (secure; required, since browsers block
///     ws:// from https). The `/ws` PATH lets a single-hostname tunnel/proxy
///     route the WebSocket upgrade to the game server while serving the static
///     app at `/` — the recommended topology in ai-docs/deploy_cloudflare.md
///     (the edge terminates TLS on 443, so no port is needed). A reverse proxy
///     that forwards `/ws*` → the Dart server on :8080 makes the bare domain
///     work with no `?server=` override.
///   - http page  → `ws://<host>:8080` (plain LAN/dev — direct to the server port).
/// localhost / empty host falls back to ws://localhost:8080.
String _defaultServerUrl(String? explicit) {
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final host = Uri.base.host;
  if (host.isEmpty || host == 'localhost') return 'ws://localhost:8080';
  final isHttps = Uri.base.scheme == 'https';
  // Over https, omit the port (edge serves wss on 443) and use the /ws path so a
  // single-host proxy can split the static app from the WebSocket upgrade.
  return isHttps ? 'wss://$host/ws' : 'ws://$host:8080';
}

void main() {
  runApp(const FragmentsOfBoundlessnessApp());
}

/// Root widget — launches the Fragments of Boundlessness game UI.
class FragmentsOfBoundlessnessApp extends StatelessWidget {
  const FragmentsOfBoundlessnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Visual-iteration hook: `?board=1` boots straight onto a deterministic
    // board (seeded RNG) so the live-capture pipeline can screenshot the board
    // without clicking through the setup screen. No effect on normal play.
    final params = Uri.base.queryParameters;
    final Widget home;
    if (params.containsKey('board')) {
      final seed = int.tryParse(params['seed'] ?? '') ?? 7;
      home = GameScreen(
        gameService: GameService(playerCount: 2, random: Random(seed)),
        debugOpenModal: params['modal'],
      );
    } else if (params.containsKey('lobby')) {
      home = const OnlineLobbyScreen();
    } else if (params.containsKey('online')) {
      // Live networked lobby (the real client net layer).
      home = NetworkLobbyScreen(defaultUrl: _defaultServerUrl(params['server']));
    } else if (params.containsKey('netgame')) {
      // Zero-click networked entry (demos / visual capture): connect + auto
      // create/join, then render the polished NetworkGameScreen.
      home = NetworkAutoScreen(
        name: params['name'] ?? 'guest',
        serverUrl: _defaultServerUrl(params['server']),
        host: params['host'] == '1',
        seats: int.tryParse(params['seats'] ?? '') ?? 2,
      );
    } else if (params.containsKey('about')) {
      home = const AboutScreen();
    } else if (params.containsKey('local') || params.containsKey('solo')) {
      // Single-player / vs-AI setup (hotseat & AI). Kept behind a flag now that
      // online multiplayer is the principal use case.
      home = const GameSetupScreen();
    } else {
      // DEFAULT: the live online lobby. Just opening the domain drops you
      // straight into multiplayer — the server URL auto-fills from the page
      // host (so visiting https://yourdomain targets that host's server).
      home = NetworkLobbyScreen(defaultUrl: _defaultServerUrl(params['server']));
    }

    return AnimationSettings(
      // Default to fast (snappy) for real play; tests/goldens fall back to
      // instant since they don't wrap the tree in AnimationSettings.
      initialSpeed: AnimationSpeed.fast,
      child: MaterialApp(
        title: 'Fragments of Boundlessness',
        debugShowCheckedModeBanner: false,
        theme: GameTheme.darkTheme,
        home: home,
      ),
    );
  }
}

/// Legacy demo app — kept for existing widget tests.
class DeckDrawApp extends StatelessWidget {
  const DeckDrawApp({super.key, this.deckService});

  final DeckService? deckService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deck Draw Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        splashFactory: InkRipple.splashFactory,
        useMaterial3: true,
      ),
      home: HomeScreen(deckService: deckService ?? DeckService()),
    );
  }
}
