import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/services/token_storage.dart';
import 'package:simple_card_game/ui/screens/about_screen.dart';
import 'package:simple_card_game/ui/screens/card_list_screen.dart';
import 'package:simple_card_game/ui/screens/game_setup_screen.dart';
import 'package:simple_card_game/ui/screens/network_game_screen.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Reachability of the game server, surfaced on the login screen.
enum _ServerStatus { checking, online, offline }

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
  final _tokenController = TextEditingController();
  GameClient? _client;
  bool _navigatedToGame = false;

  /// True once a remembered token is on file — drives the "forget" affordance.
  bool _hasRememberedToken = false;

  /// Reachability of the game server, shown on the login screen so a player who
  /// can't connect sees WHY (server down) rather than thinking the app is broken.
  _ServerStatus _serverStatus = _ServerStatus.checking;
  WebSocketChannel? _probe;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.defaultUrl ?? 'ws://localhost:8080';
    // Prefill from localStorage so an invited player logs in ONCE.
    final store = TokenStorage.instance;
    _nameController.text = store.playerName ?? '';
    _tokenController.text = store.accessToken ?? '';
    _hasRememberedToken = (store.accessToken ?? '').isNotEmpty;
    _checkServer();
  }

  /// Probe the server's reachability by opening a short-lived WebSocket to the
  /// configured URL — the exact transport a real connection uses, so it reflects
  /// whether the game server is actually up (not just whether the web app loaded).
  /// We don't `identify` (so no token needed): a socket that OPENS = online; a
  /// connect error / timeout = offline.
  Future<void> _checkServer() async {
    setState(() => _serverStatus = _ServerStatus.checking);
    final url = _urlController.text.trim();
    _probe?.sink.close();
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _probe = ch;
      // ready resolves when the handshake completes; a closed/failed server
      // throws here (or the stream errors), which we treat as offline.
      await ch.ready.timeout(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() => _serverStatus = _ServerStatus.online);
      ch.sink.close(); // we only needed to confirm it opens
    } catch (_) {
      if (!mounted) return;
      setState(() => _serverStatus = _ServerStatus.offline);
    }
  }

  @override
  void dispose() {
    _client?.removeListener(_onClientChanged);
    _client?.dispose();
    _probe?.sink.close();
    _nameController.dispose();
    _urlController.dispose();
    _gameNameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _connect() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Enter a player name first');
      return;
    }
    final token = _tokenController.text.trim();
    // Remember name + token now; if the token is wrong the server rejects and
    // we forget it (in _onClientChanged) so the next attempt re-prompts.
    final store = TokenStorage.instance;
    store.playerName = name;
    store.accessToken = token;
    setState(() => _hasRememberedToken = token.isNotEmpty);

    final client = GameClient(playerId: name, accessToken: token);
    client.addListener(_onClientChanged);
    setState(() => _client = client);
    client.connect(_urlController.text.trim());
  }

  /// Paste the OS clipboard into the access-code field. Access codes are opaque
  /// tokens users copy from an invite, and summoning the OS paste menu via
  /// long-press is finicky on web/mobile — a one-tap Paste button is reliable.
  /// Pasted tokens often carry a trailing newline/space, so we trim.
  Future<void> _pasteToken() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      _toast('Clipboard is empty');
      return;
    }
    _tokenController.text = text;
    // Move the cursor to the end so the field looks natural after a paste.
    _tokenController.selection = TextSelection.collapsed(offset: text.length);
  }

  /// Forget the remembered token (e.g. on a shared computer).
  void _forgetToken() {
    TokenStorage.instance.forgetToken();
    _tokenController.clear();
    setState(() => _hasRememberedToken = false);
    _toast('Forgot the saved access token');
  }

  void _createGame(GameClient client) {
    client.createGame(seats: 2, name: _gameNameController.text);
    _gameNameController.clear();
  }

  void _onClientChanged() {
    final client = _client;
    if (client == null) return;
    // AUTH FAILURE: the server rejected our token — forget it so the next
    // attempt re-prompts, and drop the client back to the connect panel.
    if (client.authFailed) {
      TokenStorage.instance.forgetToken();
      if (mounted) {
        setState(() {
          _hasRememberedToken = false;
          _client = null;
        });
        _toast('Invalid access token — ask for the current invite code.');
      }
      client.removeListener(_onClientChanged);
      client.dispose();
      return;
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
              child: CustomPaint(painter: BoardBackdropPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child:
                      client == null || client.status != ClientStatus.connected
                          ? _connectPanel(client)
                          : _lobbyPanel(client),
                ),
              ),
            ),
          ),
          // Server-restart heads-up: an unexpected socket drop (server
          // restarting on redeploy) shows a dismissible banner suggesting a
          // refresh while auto-reconnect retries. Not shown for a normal
          // user-initiated leave. Pinned top-center, above the panel.
          if (client != null && client.serverRestarting)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(child: ServerRestartBanner()),
            ),
          // Persistent About link (fan-made / non-commercial credits), pinned
          // top-right so it's reachable from both the login and lobby states.
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: TextButton.icon(
                  key: const ValueKey('lobbyAboutButton'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFBFD8E8),
                  ),
                  icon: const Icon(Icons.favorite_border, size: 16),
                  label: const Text(
                    'ABOUT',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
          // Card List link, pinned top-left (mirrors ABOUT). Only shown once
          // CONNECTED/authenticated — the catalog is not exposed on the
          // pre-connect login screen.
          if (client != null && client.status == ClientStatus.connected)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8),
                  child: TextButton.icon(
                    key: const ValueKey('lobbyCardListButton'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CardListScreen()),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFBFD8E8),
                    ),
                    icon: const Icon(Icons.style, size: 16),
                    label: const Text(
                      'CARD LIST',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
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
            const SizedBox(height: 10),
            _ServerStatusChip(status: _serverStatus, onRetry: _checkServer),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Your name'),
            ),
            const SizedBox(height: 12),
            // Shared access token (the invite code). Remembered after the first
            // successful connect so invitees don't re-enter it.
            TextField(
              controller: _tokenController,
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              decoration: _dec(
                'Access code (from your invite)',
                // One-tap paste — access codes are copied from an invite and the
                // OS long-press paste menu is unreliable on web/mobile.
                suffixIcon: IconButton(
                  key: const ValueKey('pasteAccessCodeButton'),
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste,
                      color: Colors.white60, size: 20),
                  onPressed: _pasteToken,
                ),
              ),
              onSubmitted: (_) => _connect(),
            ),
            if (_hasRememberedToken)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgetToken,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Forget saved code',
                      style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
                ),
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
                child: Text(
                    'Error: ${client?.lastError ?? 'connection failed'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE57373))),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: status == ClientStatus.connecting ? null : _connect,
              child: const Text('Connect'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GameSetupScreen()),
              ),
              child: const Text('Play vs AI / hotseat (offline)',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lobbyPanel(GameClient client) {
    // Active games (waiting / in-progress) show in the main list; finished games
    // move to the scrollable "Past games" summary reachable via a link.
    final games = [
      for (final g in client.lobby)
        if (!g.isComplete) g
    ];
    final pastGames = [
      for (final g in client.lobby)
        if (g.isComplete) g
    ];
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
            // Link to the scrollable past-games summary (who won). Only shown
            // once at least one game has finished.
            if (pastGames.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('pastGamesButton'),
                  onPressed: () => _showPastGames(pastGames),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFBFD8E8),
                  ),
                  icon: const Icon(Icons.history, size: 16),
                  label: Text('Past games (${pastGames.length})',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A scrollable bottom-sheet summary of finished games and who won.
  void _showPastGames(List<LobbyGameSummary> past) {
    // Newest first (games are appended in creation order; reverse to surface the
    // most recently finished at the top).
    final games = past.reversed.toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E2236),
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Past games',
                  style: TextStyle(
                    color: Color(0xFFE8C45A),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.6,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final g in games) _pastGameTile(g)],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('CLOSE',
                        style: TextStyle(color: Color(0xFF5FD0E6))),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pastGameTile(LobbyGameSummary g) {
    final winner = g.winnerId;
    final forfeited = g.winType == 'forfeit';
    final String outcome;
    if (winner != null && winner.isNotEmpty) {
      final how = g.winType == 'mastery'
          ? ' (Infinity Shard)'
          : g.winType == 'elimination'
              ? ' (elimination)'
              : '';
      outcome = '$winner won$how';
    } else if (forfeited) {
      // A forfeited (operator-closed) game — distinct from a genuine draw.
      outcome = 'Forfeited (no winner)';
    } else {
      outcome = 'Draw / no winner';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF14304A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(
            winner != null
                ? Icons.emoji_events
                : forfeited
                    ? Icons.flag
                    : Icons.handshake,
            size: 18,
            color: const Color(0xFFE8C45A),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(g.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(outcome,
                    style: const TextStyle(
                        color: Color(0xFF9FE7C9), fontSize: 13)),
                Text('players: ${g.players.join(", ")}',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gameTile(GameClient client, LobbyGameSummary g) {
    final joined = g.players.contains(client.playerId);
    final canJoin = g.status == 'waiting' && !joined;
    // If you're a member of a game that has already started, you can re-enter
    // it (the server resyncs your state on request).
    final canRejoin = joined && g.status == 'started';
    // FULL / in-progress game you're NOT in: no seat to join, so offer to WATCH
    // it as a spectator (read-only live view). Only for started games (a full
    // waiting game auto-starts instantly, so started ≈ full-and-playing).
    final canWatch = !joined && g.status == 'started';
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
                : canWatch
                    ? FilledButton.icon(
                        key: ValueKey('watchGameButton_${g.id}'),
                        // Spectate THIS game: the server pushes a non-participant
                        // (opponent-level) redacted view and the game screen
                        // renders read-only.
                        onPressed: () => client.spectateGame(g.id),
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4A3B6E)),
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('Watch'),
                      )
                    : joined
                        ? const Text('joined',
                            style: TextStyle(color: Color(0xFF80CBC4)))
                        : null,
      ),
    );
  }

  InputDecoration _dec(String label, {Widget? suffixIcon}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        suffixIcon: suffixIcon,
        enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF5FD0E6))),
      );
}

/// A small "Server: online / offline / checking" pill on the login screen, so a
/// player who cannot connect immediately sees WHY (the server is down) instead of
/// assuming the app is broken. Tappable to re-check.
class _ServerStatusChip extends StatelessWidget {
  const _ServerStatusChip({required this.status, required this.onRetry});
  final _ServerStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (status) {
      _ServerStatus.checking => (
          const Color(0xFF9E9E9E),
          Icons.sync,
          "checking…"
        ),
      _ServerStatus.online => (
          const Color(0xFF4FC36A),
          Icons.check_circle,
          "online"
        ),
      _ServerStatus.offline => (
          const Color(0xFFE5443B),
          Icons.cancel,
          "offline — the game server is unreachable"
        ),
    };
    return InkWell(
      onTap: status == _ServerStatus.checking ? null : onRetry,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                "Server: $label",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            if (status == _ServerStatus.offline) ...[
              const SizedBox(width: 8),
              Icon(Icons.refresh,
                  size: 14, color: color.withValues(alpha: 0.8)),
            ],
          ],
        ),
      ),
    );
  }
}
