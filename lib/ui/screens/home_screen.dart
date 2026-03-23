import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/deck_service.dart';
import 'package:simple_card_game/ui/widgets/playing_card_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.deckService});

  final DeckService deckService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DeckService _deckService;

  @override
  void initState() {
    super.initState();
    _deckService = widget.deckService;
  }

  void _drawCard() {
    final List<CardModel> drawnCards = _deckService.drawCards(2);

    setState(() {});

    if (drawnCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deck is empty!')),
      );
    }
  }

  void _resetDeck() {
    setState(() {
      _deckService.resetGame();
    });
  }

  void _buyCard(String cardId) {
    setState(() {
      _deckService.buyCardFromMarket(cardId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deck Draw Demo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your hand',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _deckService.hand.isEmpty
                ? const Text('No cards in hand.',
                    style: TextStyle(fontSize: 16))
                : Column(
                    children: _deckService.hand
                        .map(
                          (card) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: PlayingCardWidget(
                              key: ValueKey('hand-card-${card.id}'),
                              card: card,
                            ),
                          ),
                        )
                        .toList(),
                  ),
            const SizedBox(height: 24),
            Text(
              'Cards left in deck: ${_deckService.deckCount}',
              key: const ValueKey('deck-count-text'),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Discard pile: ${_deckService.discardCount}',
              key: const ValueKey('discard-count-text'),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Card(
              key: const ValueKey('hand-money-card'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Money remaining: ${_deckService.availableMoney}',
                  key: const ValueKey('available-money-text'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const ValueKey('draw-card-button'),
              onPressed: _drawCard,
              child: const Text('Draw 2 cards'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('reset-deck-button'),
              onPressed: _resetDeck,
              child: const Text('Reset & Shuffle Deck'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Market row',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_deckService.marketRow.isEmpty)
              const Text('No cards available to buy.')
            else
              Column(
                children: _deckService.marketRow
                    .map(
                      (card) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PlayingCardWidget(
                          key: ValueKey('market-card-${card.id}'),
                          card: card,
                          actionLabel: 'Buy',
                          actionKey: ValueKey('buy-card-${card.id}'),
                          onActionPressed: _deckService.canAffordCard(card)
                              ? () => _buyCard(card.id)
                              : null,
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}
