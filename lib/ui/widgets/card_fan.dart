import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// Displays a list of cards in a fan arrangement at the bottom of the screen.
/// Cards are slightly rotated and overlap.
///
/// Gestures:
///  - SINGLE TAP on a card → [onCardTap] (the board wires this to the card
///    ZOOM / detail modal).
///  - LONG-PRESS on a card → begins a DRAG (via [LongPressDraggable]); drop it
///    on the play area's [DragTarget<CardModel>] to play it.
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
    this.draggable = true,
    this.onDragStarted,
    this.conditionsMet,
  });

  final List<CardModel> cards;
  final void Function(CardModel card) onCardTap;

  /// Optional predicate: returns true for a hand card whose [ConditionalEffect]
  /// is currently satisfied, so the card paints a yellow "bonus active" glow.
  /// Null means never glow.
  final bool Function(CardModel card)? conditionsMet;

  /// Legacy long-press hook. Long-press now BEGINS a drag (see [draggable]), so
  /// this only fires when [draggable] is false (e.g. off-turn networked hands).
  final void Function(CardModel card)? onCardLongPress;
  final String? selectedCardId;

  /// When true (the default) a long-press on a hand card begins a drag onto the
  /// play-area [DragTarget<CardModel>] to play it. Set false to suppress
  /// dragging (e.g. when it is not this player's turn on the networked board);
  /// tap and long-press then fall back to [onCardTap] / [onCardLongPress].
  final bool draggable;

  /// Called when a hand-card drag begins (long-press). The board uses this to
  /// kick a small play animation / haptic.
  final void Function(CardModel card)? onDragStarted;

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
                      _DraggableHandCard(
                        card: card,
                        cardWidth: cardWidth,
                        draggable: widget.draggable,
                        isHighlighted: isSelected,
                        conditionsMet:
                            widget.conditionsMet?.call(card) ?? false,
                        onTap: () => widget.onCardTap(card),
                        // Long-press only acts as a plain callback when drag is
                        // disabled; otherwise the long-press initiates the drag.
                        onLongPress: widget.onCardLongPress != null
                            ? () => widget.onCardLongPress!(card)
                            : null,
                        onDragStarted: widget.onDragStarted != null
                            ? () => widget.onDragStarted!(card)
                            : null,
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

/// One hand card wired for the tap-to-zoom / long-press-to-drag mapping:
///  - a SINGLE TAP fires [onTap] (the board opens the card zoom), and
///  - a LONG-PRESS begins a drag whose [LongPressDraggable.data] is the [card],
///    so the play-area [DragTarget<CardModel>] can play it on drop.
///
/// While dragging, the in-fan slot dims ([childWhenDragging]) and a slightly
/// enlarged copy follows the pointer ([feedback]). When [draggable] is false
/// the card is rendered plainly (tap/long-press callbacks only) so off-turn
/// hands can't be dragged.
class _DraggableHandCard extends StatelessWidget {
  const _DraggableHandCard({
    required this.card,
    required this.cardWidth,
    required this.draggable,
    required this.isHighlighted,
    required this.conditionsMet,
    required this.onTap,
    required this.onLongPress,
    required this.onDragStarted,
  });

  final CardModel card;
  final double cardWidth;
  final bool draggable;
  final bool isHighlighted;
  final bool conditionsMet;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDragStarted;

  @override
  Widget build(BuildContext context) {
    // The resting card. When draggable, the long-press is consumed by the
    // LongPressDraggable below (to begin the drag), so we don't also wire the
    // card's own onLongPress in that case.
    final resting = GameCardWidget(
      card: card,
      onTap: onTap,
      onLongPress: draggable ? null : onLongPress,
      isHighlighted: isHighlighted,
      conditionsMet: conditionsMet,
      showCost: false,
      width: cardWidth,
    );

    if (!draggable) return resting;

    // The card that follows the pointer — a touch larger, lifted off the board,
    // and non-interactive (purely visual). Wrapped in Material so the card's
    // own shadows/gradients render correctly above everything else.
    final feedback = Material(
      color: Colors.transparent,
      child: Transform.scale(
        scale: 1.1,
        child: GameCardWidget(
          card: card,
          isHighlighted: true,
          showCost: false,
          width: cardWidth,
        ),
      ),
    );

    return LongPressDraggable<CardModel>(
      data: card,
      dragAnchorStrategy: childDragAnchorStrategy,
      onDragStarted: onDragStarted,
      feedback: feedback,
      // Dim the in-hand slot while the card is being dragged out.
      childWhenDragging: Opacity(opacity: 0.3, child: resting),
      child: resting,
    );
  }
}
