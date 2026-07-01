import 'package:flutter/material.dart';
import 'package:simple_card_game/data/card_art_map.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';
import 'package:simple_card_game/ui/widgets/card_art.dart';
import 'package:simple_card_game/ui/widgets/resource_icons.dart';

/// A styled card widget matching the official Fragments of Boundlessness card frame:
/// faction-tinted title bar, blue teardrop recruit cost, painted art filling
/// the upper portion, a faction "<Faction> <Type>" italic banner, a green
/// value chevron, a shield badge (champions), and a MERCENARY tab.
class GameCardWidget extends StatelessWidget {
  const GameCardWidget({
    super.key,
    required this.card,
    this.onTap,
    this.onLongPress,
    this.isHighlighted = false,
    this.conditionsMet = false,
    this.showCost = true,
    this.compact = false,
    this.width,
  });

  final CardModel card;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isHighlighted;

  /// When true the card paints a YELLOW/amber glow border signalling that at
  /// least one of its [ConditionalEffect]s is currently SATISFIED ("this card's
  /// bonus is active right now"). Distinct from the teal affordable [isHighlighted]
  /// glow. The caller computes this (engine `conditionsSatisfied` locally, or a
  /// client-side evaluator over the redacted state online). Defaults false.
  final bool conditionsMet;
  final bool showCost;
  final bool compact;
  final double? width;

  /// At/above this rendered width a card shows its full multi-line rules text.
  /// Below it (small board cards) the rules-text area is suppressed entirely so
  /// text never overflows, cuts off, or wraps vertically — the zoom modal (which
  /// renders a large-width [GameCardWidget]) is where the full text lives.
  static const double rulesTextMinWidth = 150.0;

  /// The ordered rules-text lines this card renders (play effects + Exhaust
  /// activated ability + mastery bonus). Exposed for testing. This is the full
  /// computed set; on-card rendering is additionally gated by card width (see
  /// [rulesTextMinWidth]).
  List<String> rulesLines() => _rulesLines(card, compact);

  @override
  Widget build(BuildContext context) {
    final factionColor = FactionColors.getPrimary(card.faction);
    final factionDark = FactionColors.getDark(card.faction);
    final cardWidth = width ?? (compact ? 90.0 : 120.0);
    final cardHeight =
        compact ? cardWidth * (130 / 90) : cardWidth * (170 / 120);
    final scale = cardWidth / 120.0; // 120 is the reference design width
    final radius = 8.0 * scale.clamp(0.7, 1.4);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: AnimationTiming.of(context).hoverScale,
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          // Metallic faction frame: a thin lighter inner rim over the faction
          // colour, with a subtle vertical sheen.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(factionColor, Colors.white, 0.35)!,
              factionColor,
              factionDark,
            ],
          ),
          boxShadow: [
            // Yellow/amber "conditions active right now" glow — additive, so a
            // card can be both affordable (teal) AND have its bonus active
            // (amber). Painted first so it sits under the teal/affordable glow.
            if (conditionsMet)
              BoxShadow(
                color: const Color(0xFFFFC53D).withValues(alpha: 0.85),
                blurRadius: 14 * scale,
                spreadRadius: 1.5,
              ),
            if (isHighlighted)
              BoxShadow(
                color: BoardChrome.tealHighlight.withValues(alpha: 0.7),
                blurRadius: 12 * scale,
                spreadRadius: 1,
              )
            else if (!conditionsMet)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
          ],
          border: conditionsMet
              ? Border.all(
                  color: const Color(0xFFFFD666),
                  width: 1.5 * scale.clamp(0.7, 1.4),
                )
              : null,
        ),
        padding: EdgeInsets.all(2.0 * scale.clamp(0.7, 1.3)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ---- Art fills the whole inner card ----------------------
              _CardArtArea(card: card),
              // No dark overlay over the artwork — the art shows through fully.
              // Legibility of the faction/name text is carried by the text's own
              // drop shadows (see the Text styles below), not a scrim.

              // ---- Title bar -------------------------------------------
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _TitleBar(
                  card: card,
                  factionColor: factionColor,
                  factionDark: factionDark,
                  scale: scale,
                  showCost: showCost,
                ),
              ),

              // ---- Shield badge (champions), lower-left of art ---------
              if (card.cardType == CardType.champion && card.shield > 0)
                Positioned(
                  left: 4 * scale,
                  top: cardHeight * 0.30,
                  child: _ShieldBadge(shield: card.shield, scale: scale),
                ),

              // ---- MERCENARY tab ---------------------------------------
              if (card.cardType == CardType.mercenary)
                Positioned(
                  right: 0,
                  top: cardHeight * 0.42,
                  child: _MercTab(scale: scale),
                ),

              // ---- Type banner (italic, right-aligned) -----------------
              Positioned(
                left: 4 * scale,
                right: 4 * scale,
                top: cardHeight * 0.48,
                child: Text(
                  _typeBanner(card),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (8.5 * scale).clamp(6.5, 12),
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 3),
                    ],
                  ),
                ),
              ),

              // NOTE: on-card rules TEXT is intentionally NOT overlaid on board
              // cards — a dark scrim behind it made the art's own printed text
              // hard to read. The card keeps its ICONS/badges (cost, shield,
              // faction banner, MERCENARY tab) so encodings are still verifiable
              // at a glance, and the FULL rules-encoding text is shown in a clean
              // panel UNDER the card in the tap-to-zoom detail modal
              // (card_detail_modal.dart).
            ],
          ),
        ),
      ),
    );
  }
}

// --- Frame helpers ----------------------------------------------------------

String _typeBanner(CardModel card) {
  final faction = card.faction == Faction.none
      ? ''
      : card.faction.name[0].toUpperCase() + card.faction.name.substring(1);
  final type = switch (card.cardType) {
    CardType.champion => 'Champion',
    CardType.mercenary => 'Ally',
    CardType.regular => 'Ally',
  };
  return faction.isEmpty ? type : '$faction $type';
}

/// The ordered rules-text lines for a card's info area — covering every place a
/// card's text can live, not just [CardModel.playEffects]:
///   1. the normal play effects,
///   2. an Exhaust-gated [CardModel.activatedAbility] (prefixed "Exhaust:",
///      folding in any activation cost), and
///   3. [CardModel.masteryBonus] effects (prefixed "Mastery N:").
///
/// Champions whose only text is an activated ability (e.g. Isa Tel Tor, the Axe,
/// which has empty [CardModel.playEffects]) therefore still render their ability
/// text instead of a blank info area. Compact cards show one line; full cards
/// up to three.
List<String> _rulesLines(CardModel card, bool compact) {
  final lines = [for (final e in card.playEffects) e.description];

  final ability = card.activatedAbility;
  if (ability != null) {
    final cost = ability.cost;
    String unit(int n, String singular) =>
        '$n ${n == 1 ? singular : '${singular}s'}';
    final costParts = <String>[
      if (cost.gems > 0) unit(cost.gems, 'gem'),
      if (cost.mastery > 0) '${cost.mastery} mastery',
      if (cost.health > 0) unit(cost.health, 'health').replaceFirst(
          'healths', 'health'),
    ];
    if (costParts.isEmpty) {
      lines.add(ability.description);
    } else {
      // Splice the cost into the existing "Exhaust: ..." prefix so it reads
      // "Exhaust, pay 1 gem: ...".
      final paid = 'Exhaust, pay ${costParts.join(', ')}:';
      lines.add(ability.description.replaceFirst('Exhaust:', paid));
    }
  }

  if (card.masteryBonus.isNotEmpty) {
    final tier = card.masteryThreshold;
    final prefix = tier != null ? 'Mastery $tier:' : 'Mastery:';
    for (final e in card.masteryBonus) {
      lines.add('$prefix ${e.description}');
    }
  }

  return compact ? lines.take(1).toList() : lines.take(3).toList();
}

// --- Sub-components ----------------------------------------------------------

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.card,
    required this.factionColor,
    required this.factionDark,
    required this.scale,
    required this.showCost,
  });

  final CardModel card;
  final Color factionColor;
  final Color factionDark;
  final double scale;
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(5 * scale, 3 * scale, 3 * scale, 3 * scale),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(factionColor, Colors.white, 0.2)!
                .withValues(alpha: 0.95),
            factionDark.withValues(alpha: 0.92),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: FactionColors.getTextOnPrimary(card.faction),
                fontSize: (10 * scale).clamp(8, 14),
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(color: Colors.black38, blurRadius: 2)],
              ),
            ),
          ),
          if (showCost && card.cost > 0) ...[
            SizedBox(width: 3 * scale),
            _CostTeardrop(cost: card.cost, scale: scale),
          ],
        ],
      ),
    );
  }
}

/// Recruit cost shown in a blue gem teardrop (top-right of the title bar).
class _CostTeardrop extends StatelessWidget {
  const _CostTeardrop({required this.cost, required this.scale});
  final int cost;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = (20 * scale).clamp(15.0, 28.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ResourceIconWidget(ResourceIcon.gem, size: size),
          Text(
            '$cost',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.5,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShieldBadge extends StatelessWidget {
  const _ShieldBadge({required this.shield, required this.scale});
  final int shield;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = (22 * scale).clamp(16.0, 30.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ResourceIconWidget(ResourceIcon.shield, size: size),
          Text(
            '$shield',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 2)],
            ),
          ),
        ],
      ),
    );
  }
}

class _MercTab extends StatelessWidget {
  const _MercTab({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1.5 * scale),
      decoration: const BoxDecoration(
        color: Color(0xFFC0392B),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(3),
          bottomLeft: Radius.circular(3),
        ),
      ),
      child: Text(
        'MERCENARY',
        style: TextStyle(
          color: Colors.white,
          fontSize: (6.5 * scale).clamp(5, 9),
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Shows asset image if available, falls back to procedural art.
class _CardArtArea extends StatelessWidget {
  const _CardArtArea({required this.card});
  final CardModel card;

  @override
  Widget build(BuildContext context) {
    // Prefer the card's own DB art path (authoritative); fall back to the
    // name-based art map, then to procedural art.
    final assetPath = (card.art != null && card.art!.isNotEmpty)
        ? 'assets/cards/${card.art}'
        : getCardArtAsset(card.name);
    if (assetPath != null) {
      return Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CardArt(card: card),
      );
    }
    return CardArt(card: card);
  }
}
