import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// The context action shown on the big circular button in [CardDetailModal].
/// The label + behaviour depend on where the card lives (center row → Recruit,
/// owned champion → Exhaust, etc.).
class CardDetailAction {
  const CardDetailAction({
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;
}

/// A "passive-only" champion is one whose ONLY on-play behaviour is a persistent
/// board AURA — every entry in [CardModel.playEffects] is an
/// [AddStaticModifierEffect] (e.g. zetta_the_encryptor's `cannotBeAttacked`,
/// carmine_eclipse's shield-per-card-under) — AND it has no Exhaust-gated
/// [CardModel.activatedAbility].
///
/// Such an aura already applies the moment the champion enters play
/// (`GameService.playCard` resolves a champion's `playEffects` on enter-play, and
/// the `AddStaticModifierEffect` dedup guard prevents any double-apply). There is
/// therefore nothing for the player to "activate" — so the boards deliberately
/// show NO Activate/Exhaust button for these champions. The predicate is general
/// (not hardcoded to Zetta/Carmine): any future pure-aura champion is covered.
///
/// [CardModel.playEffects] must be non-empty — a champion with no play effects at
/// all is a vanilla body, not a passive aura, and keeps its (disabled) button.
bool isPassiveOnlyChampion(CardModel card) =>
    card.activatedAbility == null &&
    card.playEffects.isNotEmpty &&
    card.playEffects.every((e) => e is AddStaticModifierEffect);

/// A full-screen card-detail modal matching the official Fragments of Boundlessness
/// client (reference 03/04): the tapped card scaled up and centered with a
/// bright cyan glow, blue chevron nav arrows on each side to page through the
/// row, and a large glowing circular action button bottom-left whose label is
/// context-dependent ("Recruit" / "Exhaust"). Tapping outside dismisses.
///
/// Show it with [showCardDetailModal].
class CardDetailModal extends StatefulWidget {
  const CardDetailModal({
    super.key,
    required this.cards,
    required this.initialIndex,
    this.actionFor,
    this.secondaryActionFor,
  });

  /// The set of cards the arrows page through (e.g. the whole center row).
  final List<CardModel> cards;

  /// Index into [cards] of the card to show first.
  final int initialIndex;

  /// Builds the primary context action for the card (e.g. Recruit / Activate),
  /// or null if the card has no primary action (then no button is shown).
  final CardDetailAction? Function(CardModel card)? actionFor;

  /// Builds an OPTIONAL second context action shown beside the primary one
  /// (e.g. a champion's Exhaust-gated ability alongside its free Activate), or
  /// null when the card has no secondary action.
  final CardDetailAction? Function(CardModel card)? secondaryActionFor;

  @override
  State<CardDetailModal> createState() => _CardDetailModalState();
}

class _CardDetailModalState extends State<CardDetailModal> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.cards.length - 1);
  }

  void _move(int delta) {
    setState(() {
      _index = (_index + delta).clamp(0, widget.cards.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.cards[_index];
    final glow = FactionColors.getPrimary(card.faction);
    final action = widget.actionFor?.call(card);
    final secondaryAction = widget.secondaryActionFor?.call(card);
    final size = MediaQuery.of(context).size;
    // Scale the card to a comfortable fraction of the viewport. On wide/landscape
    // screens height drives it (capped by 42% width so it never collides with the
    // side arrows); on tall/portrait phones that height-based value would exceed
    // the screen width, so we cap by a generous share of the WIDTH instead.
    //
    // IMPORTANT: never build an inverted clamp (lower > upper) — on a narrow
    // portrait phone the old `clamp(170, width*0.42)` had upper < lower, which
    // threw during build and left ONLY the scrim on screen (a grey veil that
    // trapped the player). Compute the two candidates and take the min, floored.
    final heightBased = size.height * 0.66 * (120 / 170);
    final widthCap = size.width * 0.82; // leave a margin on portrait
    // Smaller of the two candidates, then a floor that itself never exceeds the
    // width cap — so lower is always <= upper (no inverted clamp, ever).
    final target = heightBased < widthCap ? heightBased : widthCap;
    final floor = 140.0 < widthCap ? 140.0 : widthCap;
    final cardWidth = target < floor ? floor : target;
    final rulesLines = GameCardWidget(card: card).rulesLines();

    final canPrev = _index > 0;
    final canNext = _index < widget.cards.length - 1;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dim scrim — tap to dismiss.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(color: Colors.black.withValues(alpha: 0.72)),
            ),
          ),

          // Left nav chevron.
          if (canPrev)
            Align(
              alignment: const Alignment(-0.82, 0.0),
              child: _NavChevron(
                forward: false,
                onTap: () => _move(-1),
              ),
            ),
          // Right nav chevron.
          if (canNext)
            Align(
              alignment: const Alignment(0.82, 0.0),
              child: _NavChevron(
                forward: true,
                onTap: () => _move(1),
              ),
            ),

          // The focused card (scaled up, cyan glow) with a rules-encoding text
          // panel directly BELOW it, so the full effect text is readable and its
          // encoding is easy to verify against the printed card art.
          Center(
            child: SingleChildScrollView(
              // Bound the content to the viewport and let it scroll if the card
              // + rules panel are taller than the screen (portrait phones), so
              // it never overflows off-screen. The horizontal padding keeps the
              // scrim tappable on the sides to dismiss.
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: size.height * 0.06,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tapping the card artwork exits the zoom (like tapping the
                  // scrim). The rules panel below stays tap-absorbing so the
                  // text can be read/selected without dismissing.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF49E4FF).withValues(alpha: 0.85),
                          blurRadius: 36,
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: glow.withValues(alpha: 0.5),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: GameCardWidget(
                      key: ValueKey('detail_${card.id}'),
                      card: card,
                      width: cardWidth,
                    ),
                  ),
                  ),
                  if (rulesLines.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: cardWidth * 1.35),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E2236).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: glow.withValues(alpha: 0.55),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line in rulesLines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  line,
                                  style: const TextStyle(
                                    color: Color(0xFFF2F6FA),
                                    fontSize: 14,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Primary context action — large glowing circular button on the RIGHT
          // side, about two-thirds up the card (above the centered nav chevron).
          if (action != null)
            Align(
              alignment: const Alignment(0.82, -0.33),
              child: _CircularActionButton(
                label: action.label,
                enabled: action.enabled,
                onPressed: action.enabled
                    ? () {
                        Navigator.of(context).maybePop();
                        action.onPressed();
                      }
                    : null,
              ),
            ),

          // Secondary context action (when a card has two) — mirrored on the
          // LEFT side, same ~two-thirds-up height.
          if (secondaryAction != null)
            Align(
              alignment: const Alignment(-0.82, -0.33),
              child: _CircularActionButton(
                label: secondaryAction.label,
                enabled: secondaryAction.enabled,
                onPressed: secondaryAction.enabled
                    ? () {
                        Navigator.of(context).maybePop();
                        secondaryAction.onPressed();
                      }
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows the [CardDetailModal] as a dismissible overlay over the board.
Future<void> showCardDetailModal(
  BuildContext context, {
  required List<CardModel> cards,
  required int initialIndex,
  CardDetailAction? Function(CardModel card)? actionFor,
  CardDetailAction? Function(CardModel card)? secondaryActionFor,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss card detail',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, __, ___) => CardDetailModal(
      cards: cards,
      initialIndex: initialIndex,
      actionFor: actionFor,
      secondaryActionFor: secondaryActionFor,
    ),
    transitionBuilder: (_, anim, __, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

/// A glowing blue chevron arrow used to page through the row in the modal.
class _NavChevron extends StatelessWidget {
  const _NavChevron({required this.forward, required this.onTap});
  final bool forward;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 84,
        height: 110,
        child: CustomPaint(painter: _ChevronPainter(forward: forward)),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.forward});
  final bool forward;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // A fat triangular arrow pointing left/right.
    final path = Path();
    if (forward) {
      path.moveTo(w * 0.18, h * 0.10);
      path.lineTo(w * 0.86, h * 0.5);
      path.lineTo(w * 0.18, h * 0.90);
      path.lineTo(w * 0.18, h * 0.66);
      path.lineTo(w * 0.46, h * 0.5);
      path.lineTo(w * 0.18, h * 0.34);
    } else {
      path.moveTo(w * 0.82, h * 0.10);
      path.lineTo(w * 0.14, h * 0.5);
      path.lineTo(w * 0.82, h * 0.90);
      path.lineTo(w * 0.82, h * 0.66);
      path.lineTo(w * 0.54, h * 0.5);
      path.lineTo(w * 0.82, h * 0.34);
    }
    path.close();

    // Glow underlay.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF49E4FF).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Body gradient.
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7FE3FF), Color(0xFF2C8FE0), Color(0xFF1559A8)],
        ).createShader(Offset.zero & size),
    );
    // Bright rim.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = const Color(0xFFCFF3FF).withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) =>
      oldDelegate.forward != forward;
}

/// A large glowing circular action button (Recruit / Exhaust) with an italic
/// gold label, matching the modal action discs in the official client.
class _CircularActionButton extends StatelessWidget {
  const _CircularActionButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const diameter = 128.0;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: diameter,
          height: diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.3, -0.4),
              radius: 1.1,
              colors: [
                Color(0xFF8FE6FF),
                Color(0xFF2C8FE0),
                Color(0xFF15518F),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
            border: Border.all(
              color: const Color(0xFFCFF3FF).withValues(alpha: 0.95),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF49E4FF).withValues(alpha: 0.85),
                blurRadius: 28,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: BoardChrome.goldText,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
              letterSpacing: 0.5,
              shadows: [
                Shadow(color: Colors.black87, blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
