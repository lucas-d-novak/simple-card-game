import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/animation_timing.dart';
import '../theme/game_theme.dart';

/// A full-screen, dramatic flourish that plays when a player wins by playing the
/// Infinity Shard at Mastery 30+ (a `winType == 'mastery'` win).
///
/// Choreography: the page darkens to near-black, an Infinity Shard card flies to
/// centre, scales up, and spins two full turns wrapped in an amber glow, then
/// "INFINITY ACHIEVED" + the winner's name fade in. Tapping (or the sequence
/// completing) calls [onDone] — the board then shows its normal game-over screen.
///
/// Reused by BOTH the local board ([game_screen.dart]) and the networked board
/// ([network_game_screen.dart]); it is pure presentation and takes only the
/// winner's display name.
///
/// Honours the app's animation speed: when timing resolves to `instant` (tests,
/// reduced-motion, or the `instant` speed setting) the overlay calls [onDone]
/// on the first frame and renders nothing — so it never blocks tests or users
/// who opt out of motion.
class ShardWinOverlay extends StatefulWidget {
  const ShardWinOverlay({
    super.key,
    required this.winnerName,
    required this.onDone,
    this.isLocalWinner = true,
  });

  /// Display name of the winning player (shown under the title).
  final String winnerName;

  /// Called when the animation finishes or the user taps to skip. The host
  /// should then render the game-over screen.
  final VoidCallback onDone;

  /// Whether the viewer IS the winner (changes the title: "INFINITY ACHIEVED"
  /// for you vs. "<name> ASCENDS" for an opponent's win).
  final bool isLocalWinner;

  @override
  State<ShardWinOverlay> createState() => _ShardWinOverlayState();
}

class _ShardWinOverlayState extends State<ShardWinOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Phase boundaries within the 0..1 timeline.
  static const _dimEnd = 0.18; // page darkens
  static const _flyEnd = 0.45; // card flies in + scales up
  static const _spinEnd = 0.80; // card spins 720deg, glow pulses
  // 0.80..1.0 — title + name fade in, then settle.

  bool _instant = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Hold on the final frame; the user taps to continue (or the host can
        // auto-advance). We do NOT auto-call onDone here so the moment lands.
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve timing once we have a context. If motion is off, skip entirely.
    final timing = AnimationTiming.of(context);
    if (timing.isInstant && !_instant) {
      _instant = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
    } else if (!_instant && !_controller.isAnimating &&
        _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _skip() {
    _controller.stop();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    if (_instant) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _skip,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;

          // Dim: 0 -> 0.92 opacity black over the dim phase, then hold.
          final dim = (t / _dimEnd).clamp(0.0, 1.0) * 0.92;

          // Card entrance: scale 0.2 -> 1.6 over [dimStart..flyEnd], eased.
          final flyT =
              ((t - _dimEnd) / (_flyEnd - _dimEnd)).clamp(0.0, 1.0);
          final scale = _instant
              ? 1.6
              : 0.2 + Curves.easeOutBack.transform(flyT) * 1.4;

          // Spin: 0 -> 720deg (4*pi) over [flyEnd..spinEnd], eased in-out.
          final spinT =
              ((t - _flyEnd) / (_spinEnd - _flyEnd)).clamp(0.0, 1.0);
          final angle = Curves.easeInOut.transform(spinT) * 4 * math.pi;

          // Glow pulse peaks mid-spin.
          final glow = (math.sin(spinT * math.pi)).clamp(0.0, 1.0);

          // Title/name fade in after the spin.
          final textT = ((t - _spinEnd) / (1.0 - _spinEnd)).clamp(0.0, 1.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Darken the whole board.
              Container(color: Colors.black.withValues(alpha: dim)),

              // Radial amber wash behind the card.
              Opacity(
                opacity: (flyT * 0.5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        GameTheme.gold.withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                      radius: 0.7,
                    ),
                  ),
                ),
              ),

              // The spinning shard card.
              Center(
                child: Transform.scale(
                  scale: scale,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(angle),
                    child: _ShardCard(glow: glow),
                  ),
                ),
              ),

              // Title + winner name.
              if (textT > 0)
                Align(
                  alignment: const Alignment(0, 0.62),
                  child: Opacity(
                    opacity: textT,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.isLocalWinner
                              ? 'INFINITY ACHIEVED'
                              : '${widget.winnerName.toUpperCase()} ASCENDS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: GameTheme.gold,
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                            shadows: [
                              Shadow(
                                color: GameTheme.gold.withValues(alpha: 0.8),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.winnerName} reached Mastery 30',
                          style: const TextStyle(
                            color: GameTheme.textPrimary,
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Opacity(
                          opacity: 0.7,
                          child: Text(
                            'tap to continue',
                            style: TextStyle(
                              color: GameTheme.textSecondary,
                              fontSize: 12,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A procedural Infinity Shard card face (the starter cards intentionally use
/// procedural glyphs, so this needs no asset). A dark card with a glowing
/// infinity glyph whose glow intensity is driven by [glow] (0..1).
class _ShardCard extends StatelessWidget {
  const _ShardCard({required this.glow});

  final double glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A2A4E), Color(0xFF12122A)],
        ),
        border: Border.all(color: GameTheme.gold, width: 2),
        boxShadow: [
          BoxShadow(
            color: GameTheme.gold.withValues(alpha: 0.4 + glow * 0.6),
            blurRadius: 20 + glow * 40,
            spreadRadius: glow * 8,
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: const Size(96, 96),
          painter: _InfinityPainter(glow: glow),
        ),
      ),
    );
  }
}

class _InfinityPainter extends CustomPainter {
  _InfinityPainter({required this.glow});

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = GameTheme.gold
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + glow * 6);

    // A lemniscate (∞) drawn from a parametric curve.
    final path = Path();
    const steps = 80;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final a = size.width / 2.6;
    for (var i = 0; i <= steps; i++) {
      final tt = (i / steps) * 2 * math.pi;
      final denom = 1 + math.sin(tt) * math.sin(tt);
      final x = cx + a * math.cos(tt) / denom;
      final y = cy + a * math.sin(tt) * math.cos(tt) / denom;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_InfinityPainter old) => old.glow != glow;
}
