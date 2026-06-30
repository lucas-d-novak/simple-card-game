import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// Displays a list of cards in a fan arrangement at the bottom of the screen.
/// Cards are slightly rotated and overlap. Tapping a card selects it, tapping
/// again (or a play button) plays it.
///
/// The fan adapts to the available width: card size and overlap scale down on
/// narrow / mobile screens so the whole hand stays on screen and remains
/// touch-friendly.
class CardFan extends StatefulWidget {
  const CardFan({
    super.key,
    required this.cards,
    required this.onCardTap,
    this.onCardLongPress,
    this.selectedCardId,
  });

  final List<CardModel> cards;
  final void Function(CardModel card) onCardTap;
  final void Function(CardModel card)? onCardLongPress;
  final String? selectedCardId;

  @override
  State<CardFan> createState() => _CardFanState();
}

class _CardFanState extends State<CardFan> {
  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No cards in hand',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),
      );
    }

    final cardCount = widget.cards.length;
    // The official client lays the hand out as a near-flat upright row rather
    // than a steep fan, so keep only a whisper of rotation for life.
    final totalAngle = math.min(cardCount * 1.2, 6.0);
    final angleStep = cardCount > 1 ? totalAngle / (cardCount - 1) : 0.0;
    final startAngle = -totalAngle / 2;

    final cardMove = AnimationTiming.of(context).cardMove;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final cardWidth = Responsive.handCardWidth(availableWidth);
        // Card height mirrors GameCardWidget's non-compact aspect ratio.
        final cardHeight = cardWidth * (170 / 120);
        // Raise distance for the selected card, scaled to card size.
        final selectedLift = cardWidth * 0.22;
        // Vertical room: card + lift headroom + a little for the arc/label.
        final fanHeight =
            (cardHeight + selectedLift + 36).clamp(140.0, 280.0).toDouble();

        // Calculate card overlap based on available width.
        final totalCardWidth = cardCount * cardWidth;
        final overlap = cardCount > 1
            ? math.max(
                0.0,
                (totalCardWidth - availableWidth + 24) / (cardCount - 1),
              )
            : 0.0;
        final effectiveStep = cardWidth - overlap;
        final totalWidth = effectiveStep * (cardCount - 1) + cardWidth;
        final startX = (availableWidth - totalWidth) / 2;

        return SizedBox(
          height: fanHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: List.generate(cardCount, (index) {
              final card = widget.cards[index];
              final isSelected = card.id == widget.selectedCardId;
              final angle = cardCount > 1
                  ? (startAngle + angleStep * index) * math.pi / 180
                  : 0.0;
              final xPos = startX + effectiveStep * index;
              // Near-flat row: only a faint arc so the centre cards sit a hair
              // higher than the edges (matches the official client).
              final normalizedPos = cardCount > 1
                  ? (index - (cardCount - 1) / 2) / ((cardCount - 1) / 2)
                  : 0.0;
              final yOffset = normalizedPos * normalizedPos * 4;

              return AnimatedPositioned(
                key: ValueKey(card.id),
                duration: cardMove,
                curve: Curves.easeOutCubic,
                left: xPos,
                top: yOffset + (isSelected ? -selectedLift : 10),
                child: AnimatedRotation(
                  duration: cardMove,
                  curve: Curves.easeOutCubic,
                  // AnimatedRotation expresses rotation in turns (1 = 2*pi).
                  turns: angle / (2 * math.pi),
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'TAP TO PLAY',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      GameCardWidget(
                        card: card,
                        onTap: () => widget.onCardTap(card),
                        onLongPress: widget.onCardLongPress != null
                            ? () => widget.onCardLongPress!(card)
                            : null,
                        isHighlighted: isSelected,
                        showCost: false,
                        width: cardWidth,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
