import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';

/// Generates procedural card art based on card properties.
/// Each card gets a unique visual based on its name hash, faction, and type.
class CardArt extends StatelessWidget {
  const CardArt({super.key, required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CardArtPainter(card: card),
    );
  }
}

class _CardArtPainter extends CustomPainter {
  _CardArtPainter({required this.card});
  final CardModel card;

  @override
  void paint(Canvas canvas, Size size) {
    final hash = card.name.hashCode;
    final rng = math.Random(hash);
    final factionColor = FactionColors.getPrimary(card.faction);
    final factionDark = FactionColors.getDark(card.faction);

    // Background gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          factionDark.withValues(alpha: 0.8),
          factionColor.withValues(alpha: 0.4),
          factionDark.withValues(alpha: 0.6),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw faction-specific art patterns
    switch (card.faction) {
      case Faction.homodeus:
        _drawHomodeusArt(canvas, size, rng, factionColor);
      case Faction.wraethe:
        _drawWraetheArt(canvas, size, rng, factionColor);
      case Faction.order:
        _drawOrderArt(canvas, size, rng, factionColor);
      case Faction.undergrowth:
        _drawUndergrowthArt(canvas, size, rng, factionColor);
      case Faction.none:
        _drawNeutralArt(canvas, size, rng, factionColor);
    }

    // Card type overlay
    switch (card.cardType) {
      case CardType.champion:
        _drawChampionOverlay(canvas, size, card.hasGuard);
      case CardType.mercenary:
        _drawMercenaryOverlay(canvas, size);
      case CardType.regular:
        break;
    }
  }

  void _drawHomodeusArt(
      Canvas canvas, Size size, math.Random rng, Color color) {
    // Circuit-like patterns for tech faction
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Concentric circles (tech/energy)
    final cx = size.width * 0.5;
    final cy = size.height * 0.45;
    for (int i = 0; i < 4; i++) {
      final r = (size.width * 0.1) + i * (size.width * 0.08);
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }

    // Circuit lines
    for (int i = 0; i < 6; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final r1 = size.width * 0.1;
      final r2 = size.width * 0.4;
      canvas.drawLine(
        Offset(cx + math.cos(angle) * r1, cy + math.sin(angle) * r1),
        Offset(cx + math.cos(angle) * r2, cy + math.sin(angle) * r2),
        paint,
      );
    }

    // Node dots
    final dotPaint = Paint()..color = color.withValues(alpha: 0.7);
    for (int i = 0; i < 8; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 2, dotPaint);
    }
  }

  void _drawWraetheArt(
      Canvas canvas, Size size, math.Random rng, Color color) {
    // Dark energy swirls for destruction faction
    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Jagged energy bolts
    for (int bolt = 0; bolt < 3; bolt++) {
      final path = Path();
      var x = rng.nextDouble() * size.width;
      var y = 0.0;
      path.moveTo(x, y);
      while (y < size.height) {
        x += (rng.nextDouble() - 0.5) * size.width * 0.4;
        y += size.height * 0.15;
        path.lineTo(x.clamp(0, size.width), y);
      }
      canvas.drawPath(path, paint);
    }

    // Dark orbs
    final orbPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 5; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 3.0 + rng.nextDouble() * 6;
      canvas.drawCircle(Offset(x, y), r, orbPaint);
    }
  }

  void _drawOrderArt(Canvas canvas, Size size, math.Random rng, Color color) {
    // Geometric patterns for holy/order faction
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Central diamond/star
    final cx = size.width * 0.5;
    final cy = size.height * 0.45;
    final starSize = size.width * 0.25;
    for (int i = 0; i < 6; i++) {
      final angle = (i * math.pi / 3) + math.pi / 6;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(
            cx + math.cos(angle) * starSize, cy + math.sin(angle) * starSize),
        paint,
      );
    }

    // Hexagonal border
    final hexPath = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * math.pi / 3) - math.pi / 6;
      final x = cx + math.cos(angle) * starSize;
      final y = cy + math.sin(angle) * starSize;
      if (i == 0) {
        hexPath.moveTo(x, y);
      } else {
        hexPath.lineTo(x, y);
      }
    }
    hexPath.close();
    canvas.drawPath(hexPath, paint);

    // Light rays
    final rayPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 3;
    for (int i = 0; i < 4; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + math.cos(angle) * size.width,
            cy + math.sin(angle) * size.height),
        rayPaint,
      );
    }
  }

  void _drawUndergrowthArt(
      Canvas canvas, Size size, math.Random rng, Color color) {
    // Organic vine patterns for nature faction
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Vine tendrils
    for (int vine = 0; vine < 3; vine++) {
      final path = Path();
      var x = rng.nextDouble() * size.width;
      path.moveTo(x, size.height);
      for (int seg = 0; seg < 5; seg++) {
        final controlX = x + (rng.nextDouble() - 0.5) * size.width * 0.5;
        final endX =
            (x + (rng.nextDouble() - 0.5) * size.width * 0.3).clamp(
                0.0, size.width);
        final endY = size.height - (seg + 1) * size.height * 0.2;
        path.quadraticBezierTo(controlX, endY + size.height * 0.1, endX, endY);
        x = endX;
      }
      canvas.drawPath(path, paint);
    }

    // Leaves / dots
    final leafPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 8; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 6, height: 4),
        leafPaint,
      );
    }
  }

  void _drawNeutralArt(
      Canvas canvas, Size size, math.Random rng, Color color) {
    // The four factionless STARTER cards (Crystal, Blaster, Infinity Shard,
    // Shard Reactor) get a recognizable themed glyph keyed by name so they no
    // longer rely on the misleading stock-photo placeholders. Any other neutral
    // card falls back to the generic abstract-gem motif.
    switch (card.name) {
      case 'Crystal':
        _drawCrystalGlyph(canvas, size);
        return;
      case 'Blaster':
        _drawBlasterGlyph(canvas, size);
        return;
      case 'Shard Reactor':
        _drawReactorGlyph(canvas, size);
        return;
      case 'Infinity Shard':
        _drawInfinityShardGlyph(canvas, size);
        return;
    }
    _drawGenericNeutralArt(canvas, size, rng);
  }

  void _drawGenericNeutralArt(Canvas canvas, Size size, math.Random rng) {
    // Abstract geometric for neutral cards
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Grid pattern
    for (int i = 0; i < 5; i++) {
      final y = size.height * (i + 1) / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      final x = size.width * (i + 1) / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Center gem
    final gemPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final path = Path();
    final cx = size.width / 2;
    final cy = size.height / 2;
    final gemSize = size.width * 0.15;
    path.moveTo(cx, cy - gemSize);
    path.lineTo(cx + gemSize * 0.7, cy);
    path.lineTo(cx, cy + gemSize);
    path.lineTo(cx - gemSize * 0.7, cy);
    path.close();
    canvas.drawPath(path, gemPaint);
  }

  /// Crystal — a faceted blue/cyan gem (gem currency). Matches the official
  /// client, where Crystal is a blue/purple crystalline gem.
  void _drawCrystalGlyph(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.46;
    final w = size.width * 0.34;
    final h = size.height * 0.42;

    // Soft radial glow behind the gem.
    canvas.drawCircle(
      Offset(cx, cy),
      w * 1.2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF7FE9FF).withValues(alpha: 0.35),
            const Color(0xFF7FE9FF).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: w * 1.2)),
    );

    // Gem outline: a tall hexagonal/diamond crystal.
    final top = Offset(cx, cy - h * 0.55);
    final upperL = Offset(cx - w * 0.55, cy - h * 0.18);
    final upperR = Offset(cx + w * 0.55, cy - h * 0.18);
    final lowerL = Offset(cx - w * 0.32, cy + h * 0.2);
    final lowerR = Offset(cx + w * 0.32, cy + h * 0.2);
    final bottom = Offset(cx, cy + h * 0.55);

    final body = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(upperR.dx, upperR.dy)
      ..lineTo(lowerR.dx, lowerR.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(lowerL.dx, lowerL.dy)
      ..lineTo(upperL.dx, upperL.dy)
      ..close();

    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFBFF3FF), Color(0xFF3FA9D8), Color(0xFF5A5BD8)],
        ).createShader(Rect.fromLTWH(cx - w, cy - h, w * 2, h * 2)),
    );

    // Facet lines for the crystalline look.
    final facet = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawLine(top, lowerL, facet);
    canvas.drawLine(top, lowerR, facet);
    canvas.drawLine(top, bottom, facet);
    canvas.drawLine(upperL, lowerR, facet);
    canvas.drawLine(upperR, lowerL, facet);
    canvas.drawLine(lowerL, lowerR, facet);

    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// Blaster — an energy bolt / muzzle flash (1 power). Orange power-coloured.
  void _drawBlasterGlyph(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.46;
    final s = size.width * 0.42;

    // Glow.
    canvas.drawCircle(
      Offset(cx, cy),
      s,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFC14D).withValues(alpha: 0.40),
            const Color(0xFFFF7A00).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: s)),
    );

    // Lightning/energy bolt zig-zag.
    final bolt = Path()
      ..moveTo(cx + s * 0.35, cy - s * 0.9)
      ..lineTo(cx - s * 0.12, cy - s * 0.05)
      ..lineTo(cx + s * 0.18, cy - s * 0.05)
      ..lineTo(cx - s * 0.35, cy + s * 0.9)
      ..lineTo(cx + s * 0.2, cy + s * 0.02)
      ..lineTo(cx - s * 0.12, cy + s * 0.02)
      ..close();

    canvas.drawPath(
      bolt,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE39A), Color(0xFFFF8A1E)],
        ).createShader(Rect.fromLTWH(cx - s, cy - s, s * 2, s * 2)),
    );
    canvas.drawPath(
      bolt,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // A couple of radiating spark lines for the "blast".
    final spark = Paint()
      ..color = const Color(0xFFFFD27A).withValues(alpha: 0.5)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final a in [-0.5, 0.5, 2.6, -2.6]) {
      canvas.drawLine(
        Offset(cx + math.cos(a) * s * 0.55, cy + math.sin(a) * s * 0.55),
        Offset(cx + math.cos(a) * s * 0.95, cy + math.sin(a) * s * 0.95),
        spark,
      );
    }
  }

  /// Shard Reactor — a glowing golden reactor core (concentric rings + core).
  /// Matches the official client's golden glowing reactor.
  void _drawReactorGlyph(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.46;
    final r = size.width * 0.34;

    // Radiant glow.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFE08A).withValues(alpha: 0.45),
            const Color(0xFFFFB100).withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.5)),
    );

    // Containment rings.
    final ring = Paint()
      ..color = const Color(0xFFFFD45A).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(cx, cy), r, ring);
    canvas.drawCircle(Offset(cx, cy), r * 0.7, ring);

    // Radial struts (reactor housing).
    final strut = Paint()
      ..color = const Color(0xFFFFC83A).withValues(alpha: 0.7)
      ..strokeWidth = 2;
    for (int i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawLine(
        Offset(cx + math.cos(a) * r * 0.7, cy + math.sin(a) * r * 0.7),
        Offset(cx + math.cos(a) * r, cy + math.sin(a) * r),
        strut,
      );
    }

    // Bright molten core.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.42,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFFFC83A), Color(0xFFFF8A00)],
        ).createShader(
            Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.42)),
    );
  }

  /// Infinity Shard — a violet shard pierced by an infinity (∞) loop, the
  /// game's win-condition motif.
  void _drawInfinityShardGlyph(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.46;
    final w = size.width * 0.3;
    final h = size.height * 0.46;

    // Glow.
    canvas.drawCircle(
      Offset(cx, cy),
      w * 1.6,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFC79BFF).withValues(alpha: 0.40),
            const Color(0xFF7A3FD8).withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromCircle(center: Offset(cx, cy), radius: w * 1.6)),
    );

    // Upright shard (diamond).
    final shard = Path()
      ..moveTo(cx, cy - h * 0.55)
      ..lineTo(cx + w * 0.5, cy)
      ..lineTo(cx, cy + h * 0.55)
      ..lineTo(cx - w * 0.5, cy)
      ..close();
    canvas.drawPath(
      shard,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE4C9FF), Color(0xFF8A4BE0), Color(0xFF4A1F8F)],
        ).createShader(Rect.fromLTWH(cx - w, cy - h, w * 2, h * 2)),
    );
    canvas.drawPath(
      shard,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Infinity (∞) symbol overlaid across the shard.
    final inf = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final lobe = w * 0.42;
    final loop = Path();
    loop.addOval(Rect.fromCenter(
        center: Offset(cx - lobe * 0.7, cy), width: lobe, height: lobe * 0.8));
    loop.addOval(Rect.fromCenter(
        center: Offset(cx + lobe * 0.7, cy), width: lobe, height: lobe * 0.8));
    canvas.drawPath(loop, inf);
  }

  void _drawChampionOverlay(Canvas canvas, Size size, bool hasGuard) {
    if (hasGuard) {
      // Shield outline
      final shieldPaint = Paint()
        ..color = Colors.amber.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final path = Path();
      final cx = size.width / 2;
      path.moveTo(cx, size.height * 0.1);
      path.quadraticBezierTo(
          size.width * 0.85, size.height * 0.2, size.width * 0.8, size.height * 0.5);
      path.quadraticBezierTo(
          size.width * 0.7, size.height * 0.75, cx, size.height * 0.85);
      path.quadraticBezierTo(
          size.width * 0.3, size.height * 0.75, size.width * 0.2, size.height * 0.5);
      path.quadraticBezierTo(
          size.width * 0.15, size.height * 0.2, cx, size.height * 0.1);
      canvas.drawPath(path, shieldPaint);
    }
  }

  void _drawMercenaryOverlay(Canvas canvas, Size size) {
    // Flame-like effect at bottom
    final flamePaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, size.height);
    path.quadraticBezierTo(
        size.width * 0.25, size.height * 0.7, size.width * 0.5, size.height * 0.8);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.7, size.width, size.height);
    path.close();
    canvas.drawPath(path, flamePaint);
  }

  @override
  bool shouldRepaint(covariant _CardArtPainter oldDelegate) =>
      card.id != oldDelegate.card.id;
}
