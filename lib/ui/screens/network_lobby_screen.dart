import 'package:flutter/material.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';

/// Live multiplayer lobby — wired to the authoritative server via [GameClient].
///
/// Flow: enter your name + the server URL → Connect → see the live lobby → Create
/// or Join a game. When a game starts (enough players joined), this pushes the
/// [NetworkGameScreen] driven by the same client.
///
/// For a LAN demo: run the server (`dart run bin/server.dart 8080`) on one
/// machine, serve the web build, and point each device's URL at that machine's
/// LAN IP, e.g. ws://192.168.1.50:8080.
class NetworkLobbyScreen extends StatefulWidget {
  const NetworkLobbyScreen({super.key, this.defaultUrl});

  /// Pre-filled server URL (e.g. derived from the page host on web).
  final String? defaultUrl;

  @override
  State<NetworkLobbyScreen> createState() => _NetworkLobbyScreenState();
}

class _NetworkLobbyScreenState extends State<NetworkLobbyScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _gameNameController = TextEditingController();
  GameClient? _client;
  bool _navigatedToGame = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.defaultUrl ?? 'ws://localhost:8080';
  }

  @override
  void dispose() {
    _client?.removeListener(_onClientChanged);
    _client?.dispose();
    _nameController.dispose();
    _urlController.dispose();
    _gameNameController.dispose();
    super.dispose();
  }

  void _connect() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Enter a player name first');
      return;
    }
    final client = GameClient(playerId: name);
    client.addListener(_onClientChanged);
    setState(() => _client = client);
    client.connect(_urlController.text.trim());
  }

  void _createGame(GameClient client) {
    client.createGame(seats: 2, name: _gameNameController.text);
    _gameNameController.clear();
  }

  void _onClientChanged() {
    final client = _client;
    if (client == null) return;
    // AUTO-ENTER: when game state arrives, jump into the networked game view
    // once. On connect the server resyncs the player's MOST-RECENT active game
    // (Lobby.activeGameForPlayer returns the highest-ordinal game id), so a
    // player in several games lands in the latest one. Re-entering a specific
    // game from the lobby (tile Rejoin → client.rejoinGame) pushes that game's
    // state and re-triggers this guard after the previous push popped.
    if (client.inGame && !_navigatedToGame && mounted) {
      _navigatedToGame = true;
      Navigator.of(context)
          .push(MaterialPageRoute(
            builder: (_) => NetworkGameScreen(client: client),
          ))
          .then((_) => _navigatedToGame = false);
    }
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: CustomPaint(painter: BoardBackdropPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: client == null || client.status != ClientStatus.connected
                      ? _connectPanel(client)
                      : _lobbyPanel(client),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectPanel(GameClient? client) {
    final status = client?.status;
    return Card(
      color: const Color(0xFF12283F),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('ONLINE',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFFE8C45A),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Your name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Server URL (ws://host:port)'),
            ),
            const SizedBox(height: 8),
            if (status == ClientStatus.connecting)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Connecting…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70)),
              ),
            if (status == ClientStatus.error || client?.lastError != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Error: ${client?.lastError ?? 'connection failed'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE57373))),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: status == ClientStatus.connecting ? null : _connect,
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lobbyPanel(GameClient client) {
    final games = client.lobby;
    return Card(
      color: const Color(0xFF12283F),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lobby — ${client.playerId}',
                style: const TextStyle(
                    color: Color(0xFFE8C45A),
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // Create row: optional game name + Create / Refresh.
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _gameNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _dec('Game name (optional)'),
                    onSubmitted: (_) => _createGame(client),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: client.listGames,
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                ),
                FilledButton.icon(
                  onPressed: () => _createGame(client),
                  icon: const Icon(Icons.add),
                  label: const Text('Create (2p)'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (client.lastError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(client.lastError!,
                    style: const TextStyle(color: Color(0xFFE57373))),
              ),
            const Divider(color: Colors.white24),
            Expanded(
              child: games.isEmpty
                  ? const Center(
                      child: Text('No games yet — Create one.',
                          style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: games.length,
                      itemBuilder: (_, i) => _gameTile(client, games[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gameTile(GameClient client, LobbyGameSummary g) {
    final joined = g.players.contains(client.playerId);
    final canJoin = g.status == 'waiting' && !joined;
    // If you're a member of a game that has already started, you can re-enter
    // it (the server resyncs your state on request).
    final canRejoin = joined && g.status == 'started';
    return Card(
      color: const Color(0xFF1B3A57),
      child: ListTile(
        title: Text(g.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
            '${g.status}  ·  ${g.players.length}/${g.seats}: '
            '${g.players.join(", ")}',
            style: const TextStyle(color: Colors.white70)),
        trailing: canJoin
            ? FilledButton(
                onPressed: () => client.joinGame(g.id),
                child: const Text('Join'),
              )
            : canRejoin
                ? FilledButton(
                    // Rejoin THIS tile's game specifically — a player can be in
                    // several active games, so we target this one by id.
                    onPressed: () => client.rejoinGame(g.id),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32)),
                    child: const Text('Rejoin'),
                  )
                : joined
                    ? const Text('joined',
                        style: TextStyle(color: Color(0xFF80CBC4)))
                    : null,
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF5FD0E6))),
      );
}
