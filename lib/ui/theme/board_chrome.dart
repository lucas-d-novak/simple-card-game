import 'package:flutter/material.dart';

/// Palette + reusable painted chrome (beveled teal buttons, board background,
/// stat chips) extracted from the official Fragments of Boundlessness client mockups.
///
/// See `ai-docs/design_reference/DESIGN_SPEC.md` for the source colours.
class BoardChrome {
  BoardChrome._();

  // --- Board background -----------------------------------------------------
  static const Color bgDeep = Color(0xFF0E2236);
  static const Color bgMid = Color(0xFF163A55);
  static const Color bgGlow = Color(0xFF2A6E92);

  // --- Chrome teal ----------------------------------------------------------
  static const Color tealHighlight = Color(0xFF5FD0E6);
  static const Color tealBody = Color(0xFF1C7E96);
  static const Color tealShadow = Color(0xFF0E4A5A);
  static const Color tealRim = Color(0xFF8DE3F2);

  // --- Play All green-teal ---------------------------------------------------
  static const Color greenBody = Color(0xFF19C39C);
  static const Color greenSheen = Color(0xFF7DEBD0);
  static const Color greenShadow = Color(0xFF0C6F58);

  // --- Accents --------------------------------------------------------------
  static const Color goldText = Color(0xFFE8C45A);
  static const Color goldRim = Color(0xFFF4DD8C);

  // --- Resource colours -----------------------------------------------------
  static const Color gemBlue = Color(0xFF36B7E8);
  static const Color gemBlueDark = Color(0xFF1C6FA8);
  static const Color powerRed = Color(0xFFE5443B);
  static const Color masteryGold = Color(0xFFE8C45A);
  static const Color healthGreen = Color(0xFF4FC36A);
  static const Color shieldBlue = Color(0xFF3E8FD0);

  /// The board background: a deep blue radial-over-linear gradient with a soft
  /// central glow, approximating the server-room mood without the painted boss.
  static BoxDecoration boardBackground() => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgDeep, bgMid, bgDeep],
          stops: [0.0, 0.5, 1.0],
        ),
      );
}

/// A soft central glow + faint vertical seams to evoke the server-room set
/// piece behind the board. Cheap CustomPaint, no asset needed.
class BoardBackdropPainter extends CustomPainter {
  const BoardBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Base vertical gradient.
    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [BoardChrome.bgDeep, BoardChrome.bgMid, BoardChrome.bgDeep],
        stops: [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    // Central glow disc.
    final center = Offset(size.width / 2, size.height * 0.5);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          BoardChrome.bgGlow.withValues(alpha: 0.55),
          BoardChrome.bgGlow.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: size.width * 0.32),
      );
    canvas.drawCircle(center, size.width * 0.32, glow);

    // Bright core highlight.
    final core = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFBFE9FF).withValues(alpha: 0.30),
          const Color(0xFFBFE9FF).withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: size.width * 0.06),
      );
    canvas.drawCircle(center, size.width * 0.06, core);

    // Faint architectural seams left/right.
    final seam = Paint()
      ..color = const Color(0xFF1B3E5A).withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    for (final fx in [0.12, 0.2, 0.8, 0.88]) {
      canvas.drawLine(
        Offset(size.width * fx, size.height * 0.18),
        Offset(size.width * fx, size.height * 0.82),
        seam,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoardBackdropPainter oldDelegate) => false;
}
