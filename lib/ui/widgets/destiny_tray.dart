import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// One row in the Destinies tray: a claimed Destiny, plus per-card UI state the
/// tray needs to render its "Use" action.
class DestinyEntry {
  const DestinyEntry({
    required this.card,
    required this.canUse,
    required this.exhausted,
  });

  /// The claimed Destiny card (carries its [CardModel.activatedAbility] when it
  /// has an activated ability; a passive-only Destiny has none).
  final CardModel card;

  /// Whether the player may use this Destiny's activated ability right now
  /// (it has an ability, it is the player's turn, it is not exhausted, and the
  /// cost is payable). Computed by the caller against the engine / redacted view.
  final bool canUse;

  /// Whether this Destiny's ability was already used this turn (greys the row).
  final bool exhausted;
}

/// Shows the Destinies tray as a dismissible bottom sheet listing each claimed
/// Destiny: a mini card preview, the Destiny's ability/effect text, and a "Use"
/// action (disabled when not usable). [onUse] is invoked with the chosen
/// Destiny's id; the sheet closes first so the board can rebuild on the new
/// state. A passive-only Destiny (no activated ability) is listed for reference
/// but exposes no Use action.
Future<void> showDestinyTray(
  BuildContext context, {
  required List<DestinyEntry> entries,
  required void Function(String destinyId) onUse,
  void Function(CardModel card)? onZoom,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF0E2236),
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Destinies',
                style: TextStyle(
                  color: BoardChrome.goldText,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Each Destiny ability can be used once per turn.',
                style: TextStyle(
                  color: Color(0xFFBFD8E8),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.6,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in entries)
                        _DestinyTile(
                          entry: entry,
                          onUse: () {
                            Navigator.of(ctx).pop();
                            onUse(entry.card.id);
                          },
                          onZoom: onZoom == null
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  onZoom(entry.card);
                                },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('CLOSE',
                      style: TextStyle(color: Color(0xFF5FD0E6))),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DestinyTile extends StatelessWidget {
  const _DestinyTile({required this.entry, required this.onUse, this.onZoom});

  final DestinyEntry entry;
  final VoidCallback onUse;

  /// Tap the mini card to zoom it (always available, even when the Destiny's
  /// ability can't be used right now). Null disables the zoom gesture.
  final VoidCallback? onZoom;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final ability = card.activatedAbility;
    // Ability text when activated, otherwise the passive play-effect text.
    final String description;
    if (ability != null) {
      description = ability.description;
    } else if (card.playEffects.isNotEmpty) {
      description = card.playEffects.map((e) => e.description).join(', ');
    } else {
      description = 'Passive Destiny';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E2942),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mini card preview — tap to zoom (works even when not usable).
          Opacity(
            opacity: entry.exhausted ? 0.55 : 1.0,
            child: GameCardWidget(
              card: card,
              width: 84,
              onTap: onZoom,
              onLongPress: onZoom,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  card.name.isEmpty ? card.id : card.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFFCBDDEC),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                if (ability != null)
                  _UseButton(
                    enabled: entry.canUse,
                    exhausted: entry.exhausted,
                    onPressed: onUse,
                  )
                else
                  const Text(
                    'Passive — always active',
                    style: TextStyle(
                      color: Color(0xFF8FB4CC),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UseButton extends StatelessWidget {
  const _UseButton({
    required this.enabled,
    required this.exhausted,
    required this.onPressed,
  });

  final bool enabled;
  final bool exhausted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = exhausted ? 'Used this turn' : 'Use';
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE8C45A), Color(0xFFB8902F)],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: BoardChrome.goldRim.withValues(alpha: 0.9),
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2A1C00),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
