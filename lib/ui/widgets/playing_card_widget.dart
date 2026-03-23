import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';

class PlayingCardWidget extends StatelessWidget {
  const PlayingCardWidget({
    super.key,
    required this.card,
    this.actionLabel,
    this.actionKey,
    this.onActionPressed,
  });

  final CardModel card;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text('Money value: ${card.moneyValue}'),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: actionKey,
                  onPressed: onActionPressed,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
