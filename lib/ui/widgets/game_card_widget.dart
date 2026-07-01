import 'package:flutter/material.dart';
import 'package:simple_card_game/data/card_art_map.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';
import 'package:simple_card_game/ui/widgets/card_art.dart';
import 'package:simple_card_game/ui/widgets/card_detail_modal.dart'
    show isPassiveOnlyChampion;
import 'package:simple_card_game/ui/widgets/resource_icons.dart';

/// Whether an in-play champion still has an ACTION its controller can fire this
/// turn — the SINGLE source of truth behind BOTH the champion's enabled
/// "Exhaust"/"Activate" zoom button AND its blue "unused" board border
/// ([GameCardWidget.hasUnusedAction]), so the two can never disagree.
///
/// True iff the champion is NOT an [isPassiveOnlyChampion] (a pure aura like
/// Zetta / Carmine carries no action, ever — so it must NEVER glow) AND it has
/// either an unspent free play-effect activation OR an unspent Exhaust-gated
/// ability this turn. This is exactly the negation of the zoom button's
/// "everything spent" state (`!(activationDone && exhaustDone)`).
///
/// The per-turn [activated]/[exhausted] flags are supplied by the caller so the
/// logic is identical on the local board (from
/// `PlayerState.activatedChampions` / `exhaustedChampions`) and the networked
/// board (from the redacted view's per-champion `activated` / `exhausted`),
/// rather than being re-derived divergently in each screen.
bool championHasUnusedAction(
  CardModel card, {
  required bool activated,
  required bool exhausted,
}) {
  if (isPassiveOnlyChampion(card)) return false;
  final canActivate = card.playEffects.isNotEmpty && !activated;
  final canExhaust = card.activatedAbility != null && !exhausted;
  return canActivate || canExhaust;
}

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
    this.interactable = true,
    this.hasUnusedAction = false,
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

  /// Whether the card can currently be ACTED ON (e.g. an affordable market card
  /// on your turn). The gold [conditionsMet] "synergy is active" glow only paints
  /// when this is true, so a synergy prompt never appears on a card you can't
  /// interact with — mirroring the blue affordable prompt. Market call sites pass
  /// affordability here; hand/other contexts leave it `true` (default) so their
  /// glow is unchanged.
  final bool interactable;

  /// When true this card paints the SAME bright-blue glow/border as the market
  /// [isHighlighted] "affordable" prompt, but for a DIFFERENT context: an
  /// in-play CHAMPION that still has an available action this turn ("unused").
  /// It is a distinct, explicit flag (not a repurposing of [isHighlighted]) so
  /// the two contexts can't collide — a champion is never a market card, and a
  /// market card never sets this. Callers derive it from
  /// [championHasUnusedAction] (the same predicate driving the champion's
  /// enabled Exhaust/Activate button), so a passive-only aura champion never
  /// glows. The GOLD synergy glow still trumps it, exactly as it trumps the
  /// affordable blue. Defaults false.
  final bool hasUnusedAction;
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
    // The blue glow fires for EITHER an affordable market card ([isHighlighted])
    // OR an in-play champion with an unused action ([hasUnusedAction]) — two
    // non-overlapping contexts sharing one styling. GOLD (synergy) still trumps.
    final blueGlow = isHighlighted || hasUnusedAction;

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
          // Outline precedence: GOLD (synergy active) trumps BLUE (affordable).
          // Each shows only when the card is ACTIONABLE — gold is gated on
          // [interactable] just as blue is on affordability — so a synergy prompt
          // never appears on a card you can't act on. Exactly ONE glow paints
          // (gold wins when both apply), so gold no longer merely stacks on blue.
          // Both are ~15% more pronounced (spread + blur + alpha) than before.
          boxShadow: [
            if (conditionsMet && interactable)
              // GOLD/amber "this card's synergy is active AND you can act on it".
              BoxShadow(
                color: const Color(0xFFFFC53D).withValues(alpha: 0.98),
                blurRadius: 16.1 * scale,
                spreadRadius: 1.7,
              )
            else if (blueGlow)
              // Bright BLUE glow — affordable market card ([isHighlighted]) OR
              // an in-play champion with an unused action ([hasUnusedAction]).
              BoxShadow(
                color: const Color(0xFF49B4FF),
                blurRadius: 18.4 * scale,
                spreadRadius: 2.3,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
          ],
          // Border mirrors the glow precedence: gold (actionable synergy) → blue
          // (affordable) → none, ~15% thicker than before.
          border: (conditionsMet && interactable)
              ? Border.all(
                  color: const Color(0xFFFFD666),
                  width: 1.7 * scale.clamp(0.7, 1.4),
                )
              : blueGlow
                  ? Border.all(
                      color: const Color(0xFF6FD0FF),
                      width: 1.84 * scale.clamp(0.7, 1.4),
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
