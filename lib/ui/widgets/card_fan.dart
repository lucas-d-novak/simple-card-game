import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// Displays a list of cards in a fan arrangement at the bottom of the screen.
/// Cards are slightly rotated and overlap. Tapping a card selects it, tapping
/// again (or a play button) plays it.
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
        height: 140,
        child: Center(
          child: Text(
            'No cards in hand',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),
      );
    }

    final cardCount = widget.cards.length;
    // Fan angle range: more cards = wider fan
    final totalAngle = math.min(cardCount * 5.0, 30.0);
    final angleStep = cardCount > 1 ? totalAngle / (cardCount - 1) : 0.0;
    final startAngle = -totalAngle / 2;

    return SizedBox(
      height: 180,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          // Calculate card overlap based on available width
          final cardWidth = 110.0;
          final totalCardWidth = cardCount * cardWidth;
          final overlap = cardCount > 1
              ? math.max(
                  0.0,
                  (totalCardWidth - availableWidth + 40) / (cardCount - 1),
                )
              : 0.0;
          final effectiveStep = cardWidth - overlap;
          final totalWidth = effectiveStep * (cardCount - 1) + cardWidth;
          final startX = (availableWidth - totalWidth) / 2;

          return Stack(
            clipBehavior: Clip.none,
            children: List.generate(cardCount, (index) {
              final card = widget.cards[index];
              final isSelected = card.id == widget.selectedCardId;
              final angle = cardCount > 1
                  ? (startAngle + angleStep * index) * math.pi / 180
                  : 0.0;
              final xPos = startX + effectiveStep * index;
              // Arc: cards at edges are lower, center cards higher
              final normalizedPos = cardCount > 1
                  ? (index - (cardCount - 1) / 2) / ((cardCount - 1) / 2)
                  : 0.0;
              final yOffset = normalizedPos * normalizedPos * 15;

              return Positioned(
                left: xPos,
                top: yOffset + (isSelected ? -25 : 10),
                child: Transform.rotate(
                  angle: angle,
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
          );
        },
      ),
    );
  }
}
