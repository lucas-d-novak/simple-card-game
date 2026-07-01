import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';

/// A flame-shaped, faction-color-coded backdrop rendered BEHIND the player's
/// draw pile (deck). Its colour tells you which faction you are leaning into —
/// the same information a card like Chlorophyte Guardian keys off — so a player
/// can read their own identity at a glance without inspecting every card.
///
/// The flame gently flickers/sways when motion is enabled; in instant mode
/// (tests, reduced-motion) it renders a single static frame with no timers, so
/// widget/golden tests never hang on a pending animation.
class FactionFlameBackdrop extends StatefulWidget {
  const FactionFlameBackdrop({
    super.key,
    required this.faction,
    required this.child,
    this.width = 78,
    this.height = 104,
  });

  /// The player's dominant faction. [Faction.none] renders a neutral grey flame.
  final Faction faction;

  /// The deck widget the flame sits behind (drawn centred at the flame's base).
  final Widget child;

  final double width;
  final double height;

  @override
  State<FactionFlameBackdrop> createState() => _FactionFlameBackdropState();
}

class _FactionFlameBackdropState extends State<FactionFlameBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // A slow, ~2.4s loop reads as a lazy flicker rather than a strobe.
    duration: const Duration(milliseconds: 2400),
  );

  bool _animating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only run the repeating flicker when motion is enabled. In instant mode we
    // hold a single static frame (phase 0) and never start a timer — keeps
    // tests deterministic and avoids pumpAndSettle hangs.
    final instant = AnimationTiming.of(context).isInstant;
    if (instant && _animating) {
      _controller.stop();
      _animating = false;
    } else if (!instant && !_animating) {
      _controller.repeat();
      _animating = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Flame plume behind the deck.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _FlamePainter(
                  faction: widget.faction,
                  phase: _animating ? _controller.value : 0,
                ),
              ),
            ),
          ),
          // The deck itself, sitting at the flame's base.
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Paints a stack of faction-coloured flame tongues. The plume is built from a
/// few overlapping teardrop shapes whose tips sway on a sine wave keyed to
/// [phase] (0..1), plus a soft radial glow so the colour bleeds behind the deck.
class _FlamePainter extends CustomPainter {
  _FlamePainter({required this.faction, required this.phase});

  final Faction faction;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final primary = FactionColors.getPrimary(faction);
    final light = FactionColors.getLight(faction);
    final dark = FactionColors.getDark(faction);

    final cx = size.width / 2;
    final baseY = size.height;
    final t = phase * 2 * math.pi;

    // Soft ambient glow so the colour reads even where tongues don't cover.
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withValues(alpha: 0.55),
          primary.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(cx, baseY - size.height * 0.46),
          radius: size.width * 0.72,
        ),
      );
    canvas.drawCircle(
      Offset(cx, baseY - size.height * 0.46),
      size.width * 0.72,
      glowPaint,
    );

    // Three tongues, back-to-front: dark (widest), primary (mid), light (core).
    _drawTongue(
      canvas,
      cx: cx,
      baseY: baseY,
      width: size.width * 0.92,
      height: size.height * 0.98,
      sway: math.sin(t) * size.width * 0.07,
      color: dark.withValues(alpha: 0.70),
    );
    _drawTongue(
      canvas,
      cx: cx,
      baseY: baseY,
      width: size.width * 0.66,
      height: size.height * 0.86,
      sway: math.sin(t + 1.1) * size.width * 0.09,
      color: primary.withValues(alpha: 0.88),
    );
    _drawTongue(
      canvas,
      cx: cx,
      baseY: baseY,
      width: size.width * 0.40,
      height: size.height * 0.66,
      sway: math.sin(t + 2.3) * size.width * 0.11,
      color: light.withValues(alpha: 0.92),
    );
  }

  /// One teardrop flame tongue: a rounded base that tapers to a swaying tip.
  void _drawTongue(
    Canvas canvas, {
    required double cx,
    required double baseY,
    required double width,
    required double height,
    required double sway,
    required Color color,
  }) {
    final halfW = width / 2;
    final tipX = cx + sway;
    final tipY = baseY - height;
    final path = Path()
      ..moveTo(cx - halfW, baseY)
      // Left side sweeps up to the tip.
      ..cubicTo(
        cx - halfW, baseY - height * 0.45,
        tipX - halfW * 0.35, tipY + height * 0.30,
        tipX, tipY,
      )
      // Right side sweeps back down to the base.
      ..cubicTo(
        tipX + halfW * 0.35, tipY + height * 0.30,
        cx + halfW, baseY - height * 0.45,
        cx + halfW, baseY,
      )
      // Rounded base.
      ..quadraticBezierTo(cx, baseY + height * 0.08, cx - halfW, baseY)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_FlamePainter old) =>
      old.phase != phase || old.faction != faction;
}
