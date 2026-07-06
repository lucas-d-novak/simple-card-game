import 'package:flutter/material.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/widgets/resource_icons.dart';

/// A single opponent's condensed, board-visible state as consumed by
/// [OpponentBarStrip].
///
/// This is a plain value class (const-constructible) so the strip is decoupled
/// from the networked board's private view models — the screen maps its redacted
/// per-player view into these, and tests can construct them directly.
///
/// All fields here are already board-visible for opponents (no hidden info):
/// name, champion COUNT, mastery, health, and the opponent's last-revealed
/// in-hand [shield] total.
class OpponentBarData {
  const OpponentBarData({
    required this.id,
    required this.name,
    required this.championCount,
    required this.mastery,
    required this.health,
    this.revealedShield,
    this.eliminated = false,
  });

  /// Engine seat id — used for the widget key and passed back on tap.
  final String id;

  /// Display name (lobby username).
  final String name;

  /// Number of champions this opponent has in play.
  final int championCount;
  final int mastery;
  final int health;

  /// The opponent's in-hand SHIELD total as last REVEALED by attacking them
  /// (hidden info until an attack exposes it), or null until they have been
  /// attacked. When non-null the strip renders a shield chip showing it.
  final int? revealedShield;

  /// Defensive: eliminated opponents render greyed/struck (they are not normally
  /// passed to the strip, which only lists living opponents).
  final bool eliminated;
}

/// A condensed, read-only strip of opponent "bars" across the top of the
/// networked board. Each bar shows one living opponent's name plus their
/// champion count, mastery, health and (when revealed) their in-hand-shield chip.
///
/// PHASE A is display-only: [selectedId] highlights a bar and tapping fires
/// [onSelect], but the networked board currently passes a no-op (target
/// selection wiring lands in Phase B).
///
/// Layout is a [Row] of [Flexible] bars each wrapped in a
/// `FittedBox(BoxFit.scaleDown)`, so the strip never overflows — bars shrink to
/// share the available width. On mobile widths ([Responsive.isMobile]) each bar
/// drops its name to an initial/avatar so 3 bars fit a ~390px phone.
class OpponentBarStrip extends StatelessWidget {
  const OpponentBarStrip({
    super.key,
    required this.opponents,
    required this.selectedId,
    required this.onSelect,
  });

  final List<OpponentBarData> opponents;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final compact = Responsive.isMobile(MediaQuery.of(context).size.width);
    return Padding(
      key: const ValueKey('opponentBarStrip'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          for (final o in opponents)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                // scaleDown keeps each bar within its flex slot — the strip
                // never overflows, it just shrinks the bars to fit.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _OpponentBar(
                    data: o,
                    selected: o.id == selectedId,
                    compact: compact,
                    onSelect: onSelect,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OpponentBar extends StatelessWidget {
  const _OpponentBar({
    required this.data,
    required this.selected,
    required this.compact,
    required this.onSelect,
  });

  final OpponentBarData data;
  final bool selected;
  final bool compact;
  final ValueChanged<String> onSelect;

  String get _initial =>
      data.name.trim().isEmpty ? '?' : data.name.trim()[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    final timing = AnimationTiming.of(context);
    final elim = data.eliminated;
    // Selected bars get a gold accent border + glow; unselected keep the teal
    // chrome edge that matches the opponent pill.
    final borderColor = selected
        ? BoardChrome.goldRim
        : BoardChrome.tealHighlight.withValues(alpha: 0.55);

    final children = <Widget>[
      // Avatar (always) — carries the initial so a name-less/compact bar still
      // identifies the opponent.
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF3E6E8E), Color(0xFF1B3650)],
          ),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Text(
          _initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      if (!compact) ...[
        const SizedBox(width: 6),
        Text(
          data.name,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            decoration:
                elim ? TextDecoration.lineThrough : TextDecoration.none,
          ),
        ),
      ],
      const SizedBox(width: 8),
      _BarStat(materialIcon: Icons.groups, value: data.championCount, dim: elim),
      const SizedBox(width: 6),
      _BarStat(resourceIcon: ResourceIcon.mastery, value: data.mastery, dim: elim),
      const SizedBox(width: 6),
      _BarStat(resourceIcon: ResourceIcon.health, value: data.health, dim: elim),
      if (data.revealedShield != null) ...[
        const SizedBox(width: 6),
        _BarStat(
          resourceIcon: ResourceIcon.shield,
          value: data.revealedShield!,
          dim: elim,
        ),
      ],
    ];

    return GestureDetector(
      key: ValueKey('opponentBar_${data.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: elim ? null : () => onSelect(data.id),
      child: AnimatedContainer(
        duration: timing.hoverScale,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF14405E), Color(0xFF0B2236)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 2 : 1.2),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: BoardChrome.goldRim.withValues(alpha: 0.35),
                    blurRadius: 8,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: elim ? 0.45 : 1,
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// A compact icon + value chip for one opponent stat. Accepts EITHER a painted
/// [ResourceIcon] glyph (mastery / health / shield) or a material [IconData]
/// (champion count), never both.
class _BarStat extends StatelessWidget {
  const _BarStat({
    this.resourceIcon,
    this.materialIcon,
    required this.value,
    this.dim = false,
  }) : assert(resourceIcon != null || materialIcon != null,
            'Provide a resourceIcon or a materialIcon.');

  final ResourceIcon? resourceIcon;
  final IconData? materialIcon;
  final int value;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final icon = resourceIcon != null
        ? Opacity(
            opacity: dim ? 0.4 : 0.9,
            child: ResourceIconWidget(resourceIcon!, size: 15),
          )
        : Icon(
            materialIcon,
            size: 14,
            color: dim ? Colors.white38 : Colors.white70,
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 3),
        Text(
          '$value',
          style: TextStyle(
            color: dim ? Colors.white38 : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            shadows: const [
              Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
        ),
      ],
    );
  }
}
