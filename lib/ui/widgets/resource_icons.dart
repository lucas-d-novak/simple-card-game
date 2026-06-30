import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';

/// Custom-painted resource icons matching the official client legend:
/// gems = blue teardrop, power = red burst, mastery = gold octagon,
/// health = green cross, shield = blue shield.
enum ResourceIcon { gem, power, mastery, health, shield }

class ResourceIconWidget extends StatelessWidget {
  const ResourceIconWidget(this.icon, {super.key, this.size = 18});

  final ResourceIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ResourceIconPainter(icon)),
    );
  }
}

class _ResourceIconPainter extends CustomPainter {
  _ResourceIconPainter(this.icon);
  final ResourceIcon icon;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w / 2, h / 2);
    switch (icon) {
      case ResourceIcon.gem:
        _teardrop(canvas, size);
      case ResourceIcon.power:
        _burst(canvas, c, w * 0.5);
      case ResourceIcon.mastery:
        _octagon(canvas, c, w * 0.5);
      case ResourceIcon.health:
        _cross(canvas, size);
      case ResourceIcon.shield:
        _shield(canvas, size);
    }
  }

  void _teardrop(Canvas canvas, Size size) {
    // A droplet: round bottom, pointed top.
    final w = size.width;
    final h = size.height;
    final path = Path();
    final cx = w / 2;
    path.moveTo(cx, h * 0.04);
    path.cubicTo(w * 0.92, h * 0.42, w * 0.88, h * 0.74, cx, h * 0.96);
    path.cubicTo(w * 0.12, h * 0.74, w * 0.08, h * 0.42, cx, h * 0.04);
    path.close();
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF7FD8F5), BoardChrome.gemBlue, BoardChrome.gemBlueDark],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.06
        ..color = const Color(0xFFCDEEFB).withValues(alpha: 0.9),
    );
    // Glint.
    canvas.drawCircle(
      Offset(w * 0.38, h * 0.5),
      w * 0.1,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  void _burst(Canvas canvas, Offset c, double r) {
    final path = Path();
    const spikes = 8;
    for (int i = 0; i < spikes * 2; i++) {
      final angle = (math.pi / spikes) * i - math.pi / 2;
      final rad = i.isEven ? r : r * 0.45;
      final p = c + Offset(math.cos(angle) * rad, math.sin(angle) * rad);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    final fill = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFFC56B), BoardChrome.powerRed, Color(0xFFA01E18)],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(path, fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = const Color(0xFFFFD9A0).withValues(alpha: 0.85),
    );
  }

  void _octagon(Canvas canvas, Offset c, double r) {
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = (math.pi / 4) * i + math.pi / 8;
      final p = c + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF6E08A), BoardChrome.masteryGold, Color(0xFFB8902E)],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(path, fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..color = const Color(0xFFFFF3C4),
    );
  }

  void _cross(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final t = w * 0.32; // arm thickness
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF7BE08F), BoardChrome.healthGreen, Color(0xFF2E9A48)],
      ).createShader(Offset.zero & size);
    final rrx = RRect.fromRectAndRadius(
      Rect.fromLTWH((w - t) / 2, h * 0.08, t, h * 0.84),
      Radius.circular(t * 0.25),
    );
    final rry = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, (h - t) / 2, w * 0.84, t),
      Radius.circular(t * 0.25),
    );
    canvas.drawRRect(rrx, fill);
    canvas.drawRRect(rry, fill);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..color = const Color(0xFFD7F7DE).withValues(alpha: 0.8);
    canvas.drawRRect(rrx, stroke);
    canvas.drawRRect(rry, stroke);
  }

  void _shield(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w * 0.5, h * 0.04);
    path.lineTo(w * 0.92, h * 0.2);
    path.lineTo(w * 0.92, h * 0.52);
    path.cubicTo(w * 0.92, h * 0.8, w * 0.7, h * 0.92, w * 0.5, h * 0.98);
    path.cubicTo(w * 0.3, h * 0.92, w * 0.08, h * 0.8, w * 0.08, h * 0.52);
    path.lineTo(w * 0.08, h * 0.2);
    path.close();
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF6FB8EC), BoardChrome.shieldBlue, Color(0xFF1F5E96)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.06
        ..color = const Color(0xFFCDE7FB),
    );
  }

  @override
  bool shouldRepaint(covariant _ResourceIconPainter oldDelegate) =>
      oldDelegate.icon != icon;
}
