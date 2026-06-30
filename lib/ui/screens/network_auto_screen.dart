import 'package:flutter/material.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';

/// Zero-click networked entry for demos / visual capture.
///
/// Driven entirely from query params (no canvas taps): connects a [GameClient]
/// as [name] to [serverUrl], then either creates a game (`host: true`) or joins
/// the first waiting game it sees. When a game state arrives it renders the
/// polished [NetworkGameScreen]. This is the `?netgame=1` debug route — it uses
/// the exact same client + screen as the real ONLINE lobby flow, just without
/// the manual connect/create/join clicks.
class NetworkAutoScreen extends StatefulWidget {
  const NetworkAutoScreen({
    super.key,
    required this.name,
    required this.serverUrl,
    required this.host,
    this.seats = 2,
  });

  final String name;
  final String serverUrl;

  /// When true, create a game; otherwise join the first waiting game.
  final bool host;
  final int seats;

  @override
  State<NetworkAutoScreen> createState() => _NetworkAutoScreenState();
}

class _NetworkAutoScreenState extends State<NetworkAutoScreen> {
  late final GameClient _client;
  bool _acted = false;

  @override
  void initState() {
    super.initState();
    _client = GameClient(playerId: widget.name);
    _client.addListener(_onChanged);
    _client.connect(widget.serverUrl);
  }

  @override
  void dispose() {
    _client.removeListener(_onChanged);
    _client.dispose();
    super.dispose();
  }

  void _onChanged() {
    // Once connected, take our one action: host creates, joiner joins the first
    // waiting game (refreshing the lobby until one appears).
    if (_client.status == ClientStatus.connected && !_acted && !_client.inGame) {
      if (widget.host) {
        _acted = true;
        _client.createGame(seats: widget.seats);
      } else {
        final waiting = _client.lobby
            .where((g) => g.status == 'waiting' && !g.players.contains(widget.name))
            .toList();
        if (waiting.isNotEmpty) {
          _acted = true;
          _client.joinGame(waiting.first.id);
        } else {
          _client.listGames();
        }
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_client.inGame) {
      return NetworkGameScreen(client: _client);
    }
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: CustomPaint(painter: BoardBackdropPainter())),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF5FD0E6)),
                const SizedBox(height: 16),
                Text(
                  _statusLine(),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLine() {
    switch (_client.status) {
      case ClientStatus.connecting:
        return 'Connecting to ${widget.serverUrl}…';
      case ClientStatus.connected:
        return widget.host
            ? 'Hosting — waiting for a player…'
            : 'Joining a game…';
      case ClientStatus.error:
        return 'Error: ${_client.lastError ?? 'connection failed'}';
      case ClientStatus.disconnected:
        return 'Disconnected.';
    }
  }
}
