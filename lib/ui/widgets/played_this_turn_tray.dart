import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/widgets/card_detail_modal.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// A horizontally-SCROLLABLE strip of the cards the current player has played
/// THIS turn, meant to sit just ABOVE their resource / stat icons — a running
/// visual of the turn. Cards render SMALL (a fraction of the compact
/// enemy-champion tile), so the strip stays a lightweight ticker.
///
/// [playedCards] are the normal plays (the view's `playedThisTurn` /
/// `PlayerState.playedThisTurn`); [fastPlayedCards] are the mercenary fast-play
/// or free warp plays (the view's `fastPlayedThisTurn` /
/// `PlayerState.fastPlayedThisTurn`). Both live in the SAME strip, played first
/// then fast-played, but a fast-played tile carries a distinct RED shading (a
/// red wash + red border + a "FAST" tag) so it's obvious at a glance it was
/// fast-played. That red flag is derived purely from a card's membership in
/// [fastPlayedCards] — this strip SUPERSEDES the older grey "WARP" tile that
/// used to mark warped cards in the play area, so a warped card is never
/// doubly indicated.
///
/// Tapping a card opens the shared zoom modal ([showCardDetailModal]) with NO
/// action buttons — the card is already played, so there is nothing to do but
/// inspect it. The modal pages across the whole strip.
class PlayedThisTurnTray extends StatelessWidget {
  const PlayedThisTurnTray({
    super.key,
    required this.playedCards,
    required this.fastPlayedCards,
    required this.screenWidth,
  });

  /// Cards played normally this turn (in play order).
  final List<CardModel> playedCards;

  /// Cards fast-played / warped this turn (rendered with the red shading).
  final List<CardModel> fastPlayedCards;

  final double screenWidth;

  /// Small-card width as a fraction of the compact (enemy-champion) width, so
  /// tray cards are visibly SMALLER than the champion tiles, per the spec.
  static const double _smallFactor = 0.62;

  @override
  Widget build(BuildContext context) {
    // The full ordered strip: normal plays first, then fast-plays. The zoom
    // modal pages across this same list.
    final cards = <CardModel>[...playedCards, ...fastPlayedCards];
    if (cards.isEmpty) return const SizedBox.shrink();

    final fastIds = <String>{for (final c in fastPlayedCards) c.id};
    final width =
        (Responsive.compactCardWidth(screenWidth) * _smallFactor)
            .clamp(44.0, 78.0)
            .toDouble();
    final height = width * (130 / 90) + 4;

    return SizedBox(
      key: const ValueKey('playedThisTurnTray'),
      height: height,
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          itemCount: cards.length,
          itemBuilder: (context, i) {
            final card = cards[i];
            return Padding(
              key: ValueKey('playedTray_${card.id}'),
              padding: const EdgeInsets.only(right: 4),
              child: _TrayCard(
                card: card,
                width: width,
                isFastPlayed: fastIds.contains(card.id),
                // NO actionFor / secondaryActionFor → the modal shows no action
                // buttons: the card is already played.
                onTap: () => showCardDetailModal(
                  context,
                  cards: cards,
                  initialIndex: i,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrayCard extends StatelessWidget {
  const _TrayCard({
    required this.card,
    required this.width,
    required this.isFastPlayed,
    required this.onTap,
  });

  final CardModel card;
  final double width;
  final bool isFastPlayed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardWidget = GameCardWidget(
      card: card,
      compact: true,
      showCost: false,
      width: width,
      onTap: onTap,
      onLongPress: onTap,
    );
    if (!isFastPlayed) return cardWidget;

    // Fast-played / warped: a distinct RED wash + red border + a small "FAST"
    // tag. The overlay ignores pointer events so a tap still reaches the card
    // beneath (and opens its zoom).
    final radius = (8.0 * (width / 120.0)).clamp(5.0, 11.0);
    return Stack(
      key: ValueKey('fastPlayShade_${card.id}'),
      children: [
        cardWidget,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                color: const Color(0xFFE03B3B).withValues(alpha: 0.34),
                border: Border.all(
                  color: const Color(0xFFFF5A5A),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 2,
          left: 2,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFC0281F),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'FAST',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
