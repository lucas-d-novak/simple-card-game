import 'package:flutter/material.dart';

import '../theme/animation_timing.dart';

/// LOCAL, in-slot enter/leave animation for a card that appears in or leaves a
/// zone (hand, center row, play area, champions). When a card is ADDED to a
/// zone its widget FADES + SCALES IN within its own slot; when REMOVED it FADES
/// + SCALES OUT. Purely local to the slot — it does NOT fly across the board
/// (that's `BoardAnimator`, which is complementary and untouched here).
///
/// Wrap each zone slot's card in an [AnimatedZoneCard] carrying that card's
/// stable `id` as [zoneKey] (via a [ValueKey]) so the driving [AnimatedSwitcher]
/// / list can tell an add / remove / reorder apart from a plain rebuild.
///
/// Two ways to use it:
///
/// 1. A single slot whose CONTENT swaps (e.g. a center-row position that changes
///    which card it holds): give the child a [ValueKey(card.id)] and
///    [AnimatedZoneCard] cross-fades old→new in place.
///
/// 2. A dynamic list (hand / play area) where whole slots come and go: build the
///    children with keys and wrap the list body in [AnimatedZoneList], or reuse
///    Flutter's own `AnimatedSize`/`AnimatedSwitcher` with these transitions.
///
/// ## Instant mode (tests / reduced motion)
///
/// Duration comes from [AnimationTiming.of] (`cardMove`). In instant mode the
/// duration is [Duration.zero], so the switcher swaps with no transition and no
/// pending timer — `pumpAndSettle` stays clean.
class AnimatedZoneCard extends StatelessWidget {
  const AnimatedZoneCard({
    super.key,
    required this.zoneKey,
    required this.child,
  });

  /// A key that is STABLE for a given card (typically `ValueKey(card.id)`).
  /// Changing it tells the switcher the content changed → animate the swap.
  final Key zoneKey;

  final Widget child;

  /// The fade + scale transition used for a card entering / leaving its slot.
  static Widget transition(Widget child, Animation<double> anim) {
    return FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = AnimationTiming.of(context).cardMove;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: transition,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: KeyedSubtree(key: zoneKey, child: child),
    );
  }
}

/// A zone card LIST whose children fade + scale in/out within their own slots as
/// cards are added / removed / reordered. It is a thin wrapper over
/// [AnimatedSwitcher]-style transitions applied to a keyed [Wrap]/[Row]-like
/// body: each child MUST carry a stable key (the card id) so Flutter can match
/// slots across rebuilds.
///
/// This does NOT change the host layout — it only wraps each child so its
/// appearance/disappearance animates locally. Callers keep building their own
/// Row / Wrap / Stack; they just map each card through [wrap] (or pass the whole
/// keyed list to [AnimatedZoneList]).
///
/// Instant mode → [Duration.zero], no transition, no timer.
class AnimatedZoneList {
  const AnimatedZoneList._();

  /// Wrap a single zone child so it animates in/out locally. [id] must be the
  /// card's stable id. Use this when building a Row/Wrap of cards manually:
  ///
  /// ```dart
  /// Wrap(children: [
  ///   for (final c in cards) AnimatedZoneList.wrap(id: c.id, child: cardWidget(c)),
  /// ])
  /// ```
  static Widget wrap({required String id, required Widget child}) =>
      AnimatedZoneCard(zoneKey: ValueKey('zone-$id'), child: child);
}
