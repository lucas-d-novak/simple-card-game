import 'package:flutter/material.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';

/// Visual style for [BeveledButton].
enum BeveledStyle { teal, green }

/// A metallic beveled button matching the official client chrome: a top-edge
/// highlight, a soft inner gradient (lighter top → darker bottom), rounded
/// corners, a thin lighter rim, and a glossy diagonal sheen.
class BeveledButton extends StatelessWidget {
  const BeveledButton({
    super.key,
    required this.label,
    this.onPressed,
    this.style = BeveledStyle.teal,
    this.width,
    this.height = 44,
    this.fontSize = 18,
    this.radius = 12,
    this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final BeveledStyle style;
  final double? width;
  final double height;
  final double fontSize;
  final double radius;

  /// Optional custom content (e.g. the 1:1 ratio row) replacing the label.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final isGreen = style == BeveledStyle.green;
    final body = isGreen ? BoardChrome.greenBody : BoardChrome.tealBody;
    final highlight = isGreen ? BoardChrome.greenSheen : BoardChrome.tealHighlight;
    final shadow = isGreen ? BoardChrome.greenShadow : BoardChrome.tealShadow;
    final rim = isGreen ? BoardChrome.greenSheen : BoardChrome.tealRim;

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [highlight, body, shadow],
              stops: const [0.0, 0.5, 1.0],
            ),
            border: Border.all(color: rim.withValues(alpha: 0.85), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: highlight.withValues(alpha: 0.45),
                blurRadius: 10,
                spreadRadius: -2,
                offset: const Offset(0, -1),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Glossy diagonal sheen across the upper-left.
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: CustomPaint(painter: _SheenPainter()),
                ),
              ),
              // Top inner highlight line.
              Positioned(
                top: 2,
                left: radius,
                right: radius,
                child: Container(
                  height: 1.5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              Center(
                child: child ??
                    Text(
                      label,
                      style: TextStyle(
                        color: BoardChrome.goldText,
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 0.5,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 2),
                        ],
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.55, 0)
      ..lineTo(size.width * 0.30, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant _SheenPainter oldDelegate) => false;
}
