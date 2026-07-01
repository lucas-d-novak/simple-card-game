import 'package:flutter/material.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';

/// A fan-made "About" page. Frames the project as a non-commercial labour of
/// love by fans, that accepts no compensation, and is intended ONLY for people
/// who own the physical board game and have supported its creators.
///
/// Reachable from the setup screen's ABOUT button and via `?about=1`.
/// Note: the page deliberately avoids naming the original board game or its
/// publisher — it uses vague, affectionate euphemisms ("our favourite board
/// game") instead.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: BoardBackdropPainter()),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title
                      ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                          colors: [GameTheme.gold, GameTheme.accent],
                        ).createShader(b),
                        child: const Text(
                          'A LABOUR OF LOVE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'A fan tribute to our favourite board game',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: GameTheme.textSecondary,
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 24),

                      const _Card(
                        icon: Icons.favorite,
                        iconColor: Color(0xFFE5443B),
                        title: 'Made by huge fans',
                        body:
                            'This digital companion was built by people who '
                            'love our favourite board game — purely out of '
                            'admiration for a brilliant design. Every faction, '
                            'champion, and mastery tier here exists because we '
                            'could not stop playing the real thing.',
                      ),
                      const _Card(
                        icon: Icons.volunteer_activism,
                        iconColor: BoardChrome.greenSheen,
                        title: 'No compensation, ever',
                        body:
                            'We accept no money for this. It is not sold, it '
                            'carries no ads, and it never will. This is a gift '
                            'to the community, not a product. All credit — and '
                            'all support — belongs to the game\'s creators.',
                      ),
                      const _Card(
                        icon: Icons.handshake,
                        iconColor: GameTheme.gold,
                        title: 'For owners & supporters only',
                        body:
                            'You should only play here if you OWN the physical '
                            'board game and have supported its creators. This '
                            'companion is meant to extend the table you already '
                            'love — never to replace buying the game. If you '
                            'have not yet, please buy our favourite board game '
                            '(and its expansions) from its original publisher '
                            'first.',
                      ),
                      const _Card(
                        icon: Icons.copyright,
                        iconColor: GameTheme.textSecondary,
                        title: 'Credit where it is due',
                        body:
                            'Our favourite board game was created by its '
                            'original designers and is published by its original '
                            'publisher. All card names, art, and game mechanics '
                            'are their intellectual property. We claim none of '
                            'it — we are simply fans saying thank you.',
                      ),

                      const SizedBox(height: 16),
                      const Text(
                        'Own it. Support them. Then enjoy this with us.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: BoardChrome.goldText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Maker credit footer.
                      const Text(
                        'Made with care by',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: GameTheme.textSecondary,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'slowfadegold.com',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: GameTheme.gold,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GameTheme.accent,
                            side: const BorderSide(color: GameTheme.accent),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 12),
                          ),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('BACK'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Back-to-lobby affordance, pinned top-left (this screen has no
          // AppBar, so there's no automatic back arrow). Popping this pushed
          // route returns to the lobby.
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, left: 8),
                child: IconButton(
                  key: const ValueKey('aboutBackButton'),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  color: const Color(0xFFBFD8E8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One titled info panel in the About page.
class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12283F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: GameTheme.gold,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: GameTheme.textPrimary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
