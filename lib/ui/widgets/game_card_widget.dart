import 'package:flutter/material.dart';
import 'package:simple_card_game/data/card_art_map.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';
import 'package:simple_card_game/ui/widgets/card_art.dart';

/// A styled card widget for the Shards of Infinity game.
/// Supports tap-to-play, faction coloring, cost badge, shield badge,
/// and visual indicators for champions/mercenaries/guard.
class GameCardWidget extends StatelessWidget {
  const GameCardWidget({
    super.key,
    required this.card,
    this.onTap,
    this.onLongPress,
    this.isHighlighted = false,
    this.showCost = true,
    this.compact = false,
    this.width,
  });

  final CardModel card;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isHighlighted;
  final bool showCost;
  final bool compact;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final factionColor = FactionColors.getPrimary(card.faction);
    final cardWidth = width ?? (compact ? 90.0 : 120.0);
    // Keep a consistent card aspect ratio regardless of the (responsive) width
    // so cards never look squashed or stretched on different screen sizes.
    // Compact cards are a touch taller relative to width to fit their badges.
    final cardHeight = compact ? cardWidth * (130 / 90) : cardWidth * (170 / 120);
    // On smaller cards there is only room for a single effect line; larger
    // cards can show two. Compact cards always show one.
    final maxEffectLines = compact || cardWidth < 100 ? 1 : 2;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: GameTheme.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHighlighted ? GameTheme.gold : factionColor,
            width: isHighlighted ? 2.5 : 1.5,
          ),
          boxShadow: [
            if (isHighlighted)
              BoxShadow(
                color: GameTheme.gold.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 1,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Faction color header bar
              Container(
                color: factionColor,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 4 : 6,
                  vertical: compact ? 2 : 3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        card.name,
                        style: TextStyle(
                          color: FactionColors.getTextOnPrimary(card.faction),
                          fontSize: compact ? 9 : 11,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showCost && card.cost > 0)
                      _CostBadge(cost: card.cost, compact: compact),
                  ],
                ),
              ),

              // Card art area
              Expanded(
                flex: 3,
                child: _CardArtArea(card: card, compact: compact),
              ),

              // Card info area
              Expanded(
                flex: 2,
                child: Padding(
                  padding: EdgeInsets.all(compact ? 2 : 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Effects summary fills the available space and clips so
                      // it never overflows the info area on small cards.
                      Expanded(
                        child: ClipRect(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final effect
                                  in card.playEffects.take(maxEffectLines))
                                Text(
                                  effect.description,
                                  style: TextStyle(
                                    color: GameTheme.textPrimary,
                                    fontSize: compact ? 7 : 8,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                            ],
                          ),
                        ),
                      ),
                      // Bottom badges row - wrap to prevent overflow
                      Wrap(
                        spacing: 2,
                        runSpacing: 1,
                        children: [
                          if (card.cardType == CardType.champion &&
                              card.shield > 0)
                            _ShieldBadge(
                                shield: card.shield, compact: compact),
                          if (card.hasGuard)
                            _GuardBadge(compact: compact),
                          if (card.cardType == CardType.mercenary)
                            _MercenaryBadge(compact: compact),
                          if (card.faction != Faction.none)
                            _FactionBadge(
                                faction: card.faction, compact: compact),
                        ],
                      ),
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

class _CostBadge extends StatelessWidget {
  const _CostBadge({required this.cost, this.compact = false});
  final int cost;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 16.0 : 20.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: GameTheme.gemCyan,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Center(
        child: Text(
          '$cost',
          style: TextStyle(
            color: Colors.black,
            fontSize: compact ? 9 : 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _ShieldBadge extends StatelessWidget {
  const _ShieldBadge({required this.shield, this.compact = false});
  final int shield;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 4,
        vertical: 1,
      ),
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: Colors.blue.shade800,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield, size: compact ? 8 : 10, color: Colors.white),
          Text(
            '$shield',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 7 : 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardBadge extends StatelessWidget {
  const _GuardBadge({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 4,
        vertical: 1,
      ),
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: GameTheme.gold.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'GUARD',
        style: TextStyle(
          color: Colors.black,
          fontSize: compact ? 6 : 7,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MercenaryBadge extends StatelessWidget {
  const _MercenaryBadge({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 4,
        vertical: 1,
      ),
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: GameTheme.accent.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'MERC',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 6 : 7,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _FactionBadge extends StatelessWidget {
  const _FactionBadge({required this.faction, this.compact = false});
  final Faction faction;
  final bool compact;

  String get _label {
    switch (faction) {
      case Faction.homodeus:
        return 'HOD';
      case Faction.wraethe:
        return 'WRA';
      case Faction.order:
        return 'ORD';
      case Faction.undergrowth:
        return 'UND';
      case Faction.none:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (faction == Faction.none) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 4,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: FactionColors.getPrimary(faction).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 6 : 7,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _CardTypeIcon extends StatelessWidget {
  const _CardTypeIcon({
    required this.cardType,
    required this.hasGuard,
    this.compact = false,
  });
  final CardType cardType;
  final bool hasGuard;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 24.0 : 32.0;
    final IconData icon;
    final Color color;

    switch (cardType) {
      case CardType.champion:
        icon = hasGuard ? Icons.shield : Icons.person;
        color = hasGuard
            ? GameTheme.gold.withValues(alpha: 0.6)
            : Colors.blue.withValues(alpha: 0.4);
      case CardType.mercenary:
        icon = Icons.flash_on;
        color = GameTheme.accent.withValues(alpha: 0.4);
      case CardType.regular:
        icon = Icons.auto_awesome;
        color = Colors.white.withValues(alpha: 0.2);
    }

    return Icon(icon, size: iconSize, color: color);
  }
}

/// Shows asset image if available, falls back to procedural art.
/// Overlays a faction-tinted gradient for visual cohesion.
class _CardArtArea extends StatelessWidget {
  const _CardArtArea({required this.card, this.compact = false});
  final CardModel card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final assetPath = getCardArtAsset(card.name);
    final factionColor = FactionColors.getPrimary(card.faction);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Base art layer
        if (assetPath != null)
          Image.asset(
            assetPath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => CardArt(card: card),
          )
        else
          CardArt(card: card),
        // Faction color overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                factionColor.withValues(alpha: 0.3),
                factionColor.withValues(alpha: 0.1),
                factionColor.withValues(alpha: 0.4),
              ],
            ),
          ),
        ),
        // Card type icon centered
        Center(
          child: _CardTypeIcon(
            cardType: card.cardType,
            hasGuard: card.hasGuard,
            compact: compact,
          ),
        ),
      ],
    );
  }
}
