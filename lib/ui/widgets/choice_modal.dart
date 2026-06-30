import 'package:flutter/material.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';

/// One selectable option in a [ChoiceModal].
///
/// Either render a plain text option (the [label] + optional [detail] effect
/// text — used by the ChooseOne "X or Y" picker), or supply a [cardPreview]
/// widget (e.g. a `GameCardWidget`) to show an actual card the player can
/// acquire (used by the Destiny / Relic flows). When [cardPreview] is set the
/// label is rendered as a small caption beneath the preview.
class ChoiceOption {
  const ChoiceOption({
    required this.label,
    this.detail,
    this.cardPreview,
  });

  /// Short headline for the option (e.g. "Gain 2 gems", or a card name).
  final String label;

  /// Optional secondary line — the option's full effect description.
  final String? detail;

  /// Optional rich preview (typically a `GameCardWidget`) for card-acquisition
  /// flows (Destiny / Relic).
  final Widget? cardPreview;
}

/// A full-screen dismissible "choose one" modal, styled to match
/// [CardDetailModal] (dark scrim, centered panel, gold accents, board chrome,
/// cyan glow on the focused / tapped option). It presents a [title] (+ optional
/// [subtitle]) and a row/wrap of 2-3 option tiles, returning the chosen index.
///
/// This is the SINGLE shared picker reused by three flows:
///   * ChooseOne ("X or Y") cards — text options.
///   * Destiny claim (Mastery 5) — card previews.
///   * Relic recruit (Mastery 10) — card previews.
///
/// Show it with [showChoiceModal].
class ChoiceModal extends StatefulWidget {
  const ChoiceModal({
    super.key,
    required this.title,
    this.subtitle,
    required this.options,
  });

  final String title;
  final String? subtitle;
  final List<ChoiceOption> options;

  @override
  State<ChoiceModal> createState() => _ChoiceModalState();
}

class _ChoiceModalState extends State<ChoiceModal> {
  /// The currently-focused option (tap once to focus, again to confirm — or a
  /// dedicated Confirm button confirms the focused option). Defaults to the
  /// first option so the modal always has an obvious primary.
  int _focused = 0;

  void _confirm(int index) {
    Navigator.of(context).pop(index);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final hasPreviews = widget.options.any((o) => o.cardPreview != null);
    // Constrain the panel so it never spans the whole ultra-wide screen.
    final panelMaxWidth = size.width.clamp(0.0, 720.0);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dim scrim — tap to dismiss (returns null).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(color: Colors.black.withValues(alpha: 0.72)),
            ),
          ),

          // Centered panel.
          Center(
            child: GestureDetector(
              // Absorb taps on the panel so they don't dismiss.
              onTap: () {},
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: panelMaxWidth,
                  maxHeight: size.height * 0.9,
                ),
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF15334C), Color(0xFF0B1B2B)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: BoardChrome.goldRim.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF49E4FF).withValues(alpha: 0.25),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                      const BoxShadow(
                        color: Colors.black87,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title.
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: BoardChrome.goldText,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFBFD8E8),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Options — a centered wrap so 2-3 tiles lay out as a row
                      // on wide screens and stack on narrow ones.
                      Flexible(
                        child: SingleChildScrollView(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (int i = 0; i < widget.options.length; i++)
                                _OptionTile(
                                  option: widget.options[i],
                                  focused: _focused == i,
                                  hasPreviews: hasPreviews,
                                  onTap: () {
                                    if (_focused == i) {
                                      _confirm(i);
                                    } else {
                                      setState(() => _focused = i);
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      // Confirm the focused option (large tap target).
                      _ConfirmButton(
                        onPressed: () => _confirm(_focused),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the [ChoiceModal] as a dismissible overlay and resolves to the chosen
/// index, or null if dismissed.
Future<int?> showChoiceModal(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<ChoiceOption> options,
}) {
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss choice',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, __, ___) => ChoiceModal(
      title: title,
      subtitle: subtitle,
      options: options,
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

/// One option tile. A focused tile gets a bright cyan glow + border, matching
/// the focused-card glow in [CardDetailModal].
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.focused,
    required this.hasPreviews,
    required this.onTap,
  });

  final ChoiceOption option;
  final bool focused;

  /// When any option in the modal carries a card preview, all tiles use the
  /// (wider) card layout so the row stays visually consistent.
  final bool hasPreviews;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final glow = focused
        ? [
            BoxShadow(
              color: const Color(0xFF49E4FF).withValues(alpha: 0.8),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ]
        : const <BoxShadow>[];
    final borderColor = focused
        ? const Color(0xFF8FE6FF)
        : Colors.white.withValues(alpha: 0.18);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: BoxConstraints(
          minWidth: hasPreviews ? 140 : 200,
          maxWidth: hasPreviews ? 220 : 320,
        ),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: focused
              ? const Color(0xFF13405E)
              : const Color(0xFF0E2942),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: focused ? 2 : 1),
          boxShadow: glow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (option.cardPreview != null) ...[
              option.cardPreview!,
              const SizedBox(height: 8),
            ],
            Text(
              option.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: focused ? Colors.white : const Color(0xFFE8EEF4),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (option.detail != null) ...[
              const SizedBox(height: 4),
              Text(
                option.detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFBFD8E8),
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The large gold "Choose" confirm button at the bottom of the modal.
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 48,
        constraints: const BoxConstraints(minWidth: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          gradient: const RadialGradient(
            center: Alignment(-0.3, -0.4),
            radius: 1.4,
            colors: [Color(0xFF8FE6FF), Color(0xFF2C8FE0), Color(0xFF15518F)],
            stops: [0.0, 0.55, 1.0],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFCFF3FF).withValues(alpha: 0.95),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF49E4FF).withValues(alpha: 0.6),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Text(
          'Choose',
          style: TextStyle(
            color: BoardChrome.goldText,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.5,
            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}
