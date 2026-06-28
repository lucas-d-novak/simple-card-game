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
