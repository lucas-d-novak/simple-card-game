import 'package:flutter/material.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';

/// Displays a player's resources (health, mastery, gems, power) in a horizontal bar.
class ResourceBar extends StatelessWidget {
  const ResourceBar({
    super.key,
    required this.health,
    required this.mastery,
    required this.gems,
    required this.power,
    required this.playerName,
    this.isCurrentPlayer = false,
    this.deckCount = 0,
    this.discardCount = 0,
    this.gemKey,
    this.powerKey,
    this.masteryKey,
    this.healthKey,
    this.deckKey,
    this.discardKey,
  });

  final int health;
  final int mastery;
  final int gems;
  final int power;
  final String playerName;
  final bool isCurrentPlayer;
  final int deckCount;
  final int discardCount;

  /// Optional anchor keys for the fly-animation system: resource pips fly TO the
  /// gem/power/mastery/health counters, and cards fly TO/FROM the deck & discard
  /// pile indicators. They only tag the render box (via [KeyedSubtree]) so
  /// [BoardAnimator] can resolve each counter's global rect. Null = no anchor.
  final GlobalKey? gemKey;
  final GlobalKey? powerKey;
  final GlobalKey? masteryKey;
  final GlobalKey? healthKey;
  final GlobalKey? deckKey;
  final GlobalKey? discardKey;

  /// Tag [child] with [key] (if any) so the fly-animation system can resolve its
  /// global rect. [KeyedSubtree] adds no layout — it just carries the key.
  static Widget _anchor(GlobalKey? key, Widget child) =>
      key == null ? child : KeyedSubtree(key: key, child: child);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isCurrentPlayer
            ? GameTheme.surfaceMid.withValues(alpha: 0.8)
            : GameTheme.surfaceDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: isCurrentPlayer
            ? Border.all(color: GameTheme.gold, width: 1.5)
            : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = Responsive.isMobile(constraints.maxWidth);

          final name = Text(
            playerName,
            style: TextStyle(
              color: isCurrentPlayer ? GameTheme.gold : GameTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          );

          final stats = <Widget>[
            _anchor(
              healthKey,
              _ResourceChip(
                icon: Icons.favorite,
                value: health,
                color:
                    health > 25 ? GameTheme.healthGreen : GameTheme.healthRed,
              ),
            ),
            _anchor(masteryKey, _MasteryIndicator(mastery: mastery)),
            _anchor(
              gemKey,
              _ResourceChip(
                icon: Icons.diamond,
                value: gems,
                color: GameTheme.gemCyan,
              ),
            ),
            _anchor(
              powerKey,
              _ResourceChip(
                icon: Icons.bolt,
                value: power,
                color: GameTheme.powerOrange,
              ),
            ),
            _anchor(
              deckKey,
              _PileIndicator(
                  icon: Icons.layers, count: deckCount, label: 'Deck'),
            ),
            _anchor(
              discardKey,
              _PileIndicator(
                  icon: Icons.delete_outline,
                  count: discardCount,
                  label: 'Disc'),
            ),
          ];

          if (isNarrow) {
            // On narrow screens stack the name above wrapping resource chips so
            // nothing overflows horizontally.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                name,
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: stats,
                ),
              ],
            );
          }

          // Wide layout: single row, name left, piles pushed right.
          return Row(
            children: [
              name,
              const SizedBox(width: 12),
              for (int i = 0; i < 4; i++) ...[
                stats[i],
                const SizedBox(width: 8),
              ],
              const Spacer(),
              stats[4],
              const SizedBox(width: 8),
              stats[5],
            ],
          );
        },
      ),
    );
  }
}

class _ResourceChip extends StatelessWidget {
  const _ResourceChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        _AnimatedCounter(
          value: value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Renders an integer that "ticks" toward new values using
/// [TweenAnimationBuilder]. Under instant / reduced motion the duration is
/// [Duration.zero] so it snaps with no special-casing.
class _AnimatedCounter extends StatelessWidget {
  const _AnimatedCounter({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: value, end: value),
      duration: AnimationTiming.of(context).counterTick,
      builder: (context, animatedValue, _) =>
          Text('$animatedValue', style: style),
    );
  }
}

class _MasteryIndicator extends StatelessWidget {
  const _MasteryIndicator({required this.mastery});
  final int mastery;

  @override
  Widget build(BuildContext context) {
    final progress = (mastery / 30).clamp(0.0, 1.0);
    final isMaxed = mastery >= 30;
    final color = isMaxed ? GameTheme.gold : GameTheme.masteryPurple;
    final tickDuration = AnimationTiming.of(context).counterTick;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.auto_awesome,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 40,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Background track
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Fill bar — animates toward the new progress (snaps when instant).
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: progress, end: progress),
                duration: tickDuration,
                curve: Curves.easeOut,
                builder: (context, animatedProgress, _) => FractionallySizedBox(
                  widthFactor: animatedProgress,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 3),
        _AnimatedCounter(
          value: mastery,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _PileIndicator extends StatelessWidget {
  const _PileIndicator({
    required this.icon,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: GameTheme.textSecondary),
        const SizedBox(width: 2),
        Text(
          '$count',
          style: const TextStyle(
            color: GameTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
