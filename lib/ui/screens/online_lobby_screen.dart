import 'package:flutter/material.dart';
import 'package:simple_card_game/ui/screens/game_setup_screen.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';

/// A single online game shown in the lobby. Static sample data for now — the
/// real networking layer is being built in parallel.
class LobbyGame {
  const LobbyGame({
    required this.status,
    required this.players,
    this.owned = false,
  });

  /// Status label shown on the tile ("Game Started", "Complete",
  /// "Invitation Expired", ...).
  final String status;

  /// The players in the game, with their ready state.
  final List<LobbyPlayer> players;

  /// Whether this is one of "Your Games" (shows a delete affordance).
  final bool owned;
}

/// A player row inside a [LobbyGame] tile: a colored ready-dot + name.
class LobbyPlayer {
  const LobbyPlayer(this.name, {this.ready = false});
  final String name;

  /// Green dot when ready, red dot when not.
  final bool ready;
}

/// The "Online" lobby panel — a static mockup matching reference 05: a heavy
/// brushed-metal chamfered frame with an "ONLINE" title plate, a teal X close,
/// "Your Games" / "More Games" sections of game tiles, and a bottom
/// "Create Game" bar that routes to the existing game setup.
///
/// No real networking yet; the tiles render placeholder/sample data.
class OnlineLobbyScreen extends StatelessWidget {
  const OnlineLobbyScreen({super.key});

  static const List<LobbyGame> _yourGames = [
    LobbyGame(
      owned: true,
      status: 'Invitation Expired',
      players: [
        LobbyPlayer('tri', ready: false),
        LobbyPlayer('fooby', ready: true),
      ],
    ),
  ];

  static const List<LobbyGame> _moreGames = [
    LobbyGame(
      status: 'Complete',
      players: [
        LobbyPlayer('Piniwini', ready: true),
        LobbyPlayer('Laura', ready: false),
      ],
    ),
    LobbyGame(
      status: 'Game Started',
      players: [
        LobbyPlayer('korvus', ready: false),
        LobbyPlayer('shanks', ready: false),
      ],
    ),
    LobbyGame(
      status: 'Game Started',
      players: [
        LobbyPlayer('korvus', ready: false),
        LobbyPlayer('Piniwini', ready: false),
      ],
    ),
    LobbyGame(
      status: 'Game Started',
      players: [
        LobbyPlayer('korvus', ready: false),
        LobbyPlayer('Pandapapst', ready: false),
      ],
    ),
  ];

  void _createGame(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GameSetupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: CustomPaint(painter: BoardBackdropPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980, maxHeight: 560),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _MetalPanel(
                    onClose: () => Navigator.of(context).maybePop(),
                    child: _LobbyBody(
                      yourGames: _yourGames,
                      moreGames: _moreGames,
                      onCreate: () => _createGame(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metallic chamfered panel frame + title plate + close button
// ---------------------------------------------------------------------------

class _MetalPanel extends StatelessWidget {
  const _MetalPanel({required this.child, required this.onClose});
  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The chamfered brushed-metal frame.
        Positioned.fill(
          child: CustomPaint(painter: _MetalFramePainter()),
        ),
        // Inner content inset from the frame.
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(34, 56, 34, 30),
            child: child,
          ),
        ),
        // Title plate, top-center.
        Align(
          alignment: const Alignment(0.0, -1.0),
          child: Transform.translate(
            offset: const Offset(0, -4),
            child: const _TitlePlate(label: 'ONLINE'),
          ),
        ),
        // Close button, top-right.
        Positioned(
          top: 10,
          right: 14,
          child: _CloseButton(onTap: onClose),
        ),
      ],
    );
  }
}

class _MetalFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const ch = 28.0; // chamfer size

    Path chamfered(Rect r, double c) {
      return Path()
        ..moveTo(r.left + c, r.top)
        ..lineTo(r.right - c, r.top)
        ..lineTo(r.right, r.top + c)
        ..lineTo(r.right, r.bottom - c)
        ..lineTo(r.right - c, r.bottom)
        ..lineTo(r.left + c, r.bottom)
        ..lineTo(r.left, r.bottom - c)
        ..lineTo(r.left, r.top + c)
        ..close();
    }

    // Outer metal bezel.
    final outer = chamfered(rect, ch);
    canvas.drawPath(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFC9D2D8), Color(0xFF7C8896), Color(0xFF4A5360)],
        ).createShader(rect),
    );
    // Bevel highlight + shadow strokes.
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFEFF4F7).withValues(alpha: 0.8),
    );

    // Inner recessed plate.
    final innerRect = rect.deflate(16);
    final inner = chamfered(innerRect, ch * 0.7);
    canvas.drawPath(
      inner,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFAEB7BF), Color(0xFF99A4AD)],
        ).createShader(innerRect),
    );
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF3A4350).withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TitlePlate extends StatelessWidget {
  const _TitlePlate({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8EEF2), Color(0xFFB4BEC6), Color(0xFF8A95A0)],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(10),
        ),
        border: Border.all(color: const Color(0xFFEFF4F7), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF2C333C),
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: 3,
          shadows: [Shadow(color: Colors.white54, blurRadius: 1)],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            bottomLeft: Radius.circular(14),
            topRight: Radius.circular(6),
            bottomRight: Radius.circular(6),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BoardChrome.tealHighlight,
              BoardChrome.tealBody,
              BoardChrome.tealShadow,
            ],
          ),
          border: Border.all(color: BoardChrome.tealRim, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: const Icon(Icons.close, size: 24, color: Color(0xFFCFF3FF)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lobby body: sections + tiles + Create Game bar
// ---------------------------------------------------------------------------

class _LobbyBody extends StatelessWidget {
  const _LobbyBody({
    required this.yourGames,
    required this.moreGames,
    required this.onCreate,
  });

  final List<LobbyGame> yourGames;
  final List<LobbyGame> moreGames;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('Your Games'),
                const SizedBox(height: 8),
                _TileRow(games: yourGames),
                const SizedBox(height: 18),
                const _SectionHeader('More Games'),
                const SizedBox(height: 8),
                _TileRow(games: moreGames),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _CreateGameBar(onTap: onCreate),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF44505C),
          fontSize: 20,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Colors.white38, blurRadius: 1)],
        ),
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.games});
  final List<LobbyGame> games;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [for (final g in games) _GameTile(game: g)],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game});
  final LobbyGame game;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 168,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8FA6B6), Color(0xFF5E7588)],
        ),
        border: Border.all(color: const Color(0xFF49C8E6), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          // Faint art-card thumbnail backdrop bottom-half.
          Positioned.fill(
            top: 64,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(8),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF8E5BB0).withValues(alpha: 0.55),
                      const Color(0xFF3A1F55).withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.person, size: 56, color: Colors.white24),
                ),
              ),
            ),
          ),
          // Status label + player rows.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    game.status,
                    style: const TextStyle(
                      color: Color(0xFF1B2530),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.white38, blurRadius: 1)],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                for (final p in game.players) _PlayerRow(player: p),
              ],
            ),
          ),
          // Delete affordance for owned games.
          if (game.owned)
            const Positioned(
              right: 8,
              bottom: 6,
              child: Icon(Icons.delete, size: 30, color: Color(0xFFBFC9D2)),
            ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});
  final LobbyPlayer player;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: player.ready
                  ? const Color(0xFF35C95B)
                  : const Color(0xFFD8403A),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            player.name,
            style: const TextStyle(
              color: Color(0xFF14202B),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.white30, blurRadius: 1)],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateGameBar extends StatelessWidget {
  const _CreateGameBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BoardChrome.tealHighlight,
              BoardChrome.tealBody,
              BoardChrome.tealShadow,
            ],
          ),
          border: Border.all(color: BoardChrome.tealRim, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 5, offset: Offset(0, 2)),
          ],
        ),
        child: const Text(
          'Create Game',
          style: TextStyle(
            color: Color(0xFFEFF7FA),
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
          ),
        ),
      ),
    );
  }
}
