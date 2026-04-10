import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/widgets/playing_card_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.gameService});

  final GameService gameService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final GameService _gameService;

  @override
  void initState() {
    super.initState();
    _gameService = widget.gameService;
  }

  void _drawCard() {
    final List<CardModel> drawnCards = _gameService.currentPlayer.deckService.drawCards(2);

    setState(() {});

    if (drawnCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deck is empty!')),
      );
    }
  }

  void _resetDeck() {
    setState(() {
      _gameService.resetGame();
    });
  }

  void _shuffleDiscardIntoDeck() {
    setState(() {
      _gameService.currentPlayer.deckService.shuffleDiscardIntoDeck();
    });
  }

  void _buyCard(String cardId) {
    setState(() {
      _gameService.buyCardFromMarket(cardId);
    });
  }

  void _playCard(String cardId) {
    setState(() {
      _gameService.currentPlayer.deckService.playCardFromHand(cardId);
    });
  }
  
  void _endTurn() {
    setState(() {
      _gameService.endTurn(2); // Draw 2 cards on turn end
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentPlayerState = _gameService.currentPlayer;
    final currentDeckService = currentPlayerState.deckService;

    return Scaffold(
      appBar: AppBar(
        title: Text('Deck Draw Demo - ${currentPlayerState.name}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${currentPlayerState.name}\'s hand',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            currentDeckService.hand.isEmpty
                ? const Text('No cards in hand.',
                    style: TextStyle(fontSize: 16))
                : Column(
                    children: currentDeckService.hand
                        .map(
                          (card) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: PlayingCardWidget(
                              key: ValueKey('hand-card-${card.id}'),
                              card: card,
                              actionLabel: 'Play',
                              actionKey: ValueKey('play-card-${card.id}'),
                              onActionPressed: () => _playCard(card.id),
                            ),
                          ),
                        )
                        .toList(),
                  ),
            const SizedBox(height: 24),
            const Text(
              'Played cards',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            currentDeckService.playedCards.isEmpty
                ? const Text('No cards played.', style: TextStyle(fontSize: 16))
                : Column(
                    children: currentDeckService.playedCards
                        .map(
                          (card) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: PlayingCardWidget(
                              key: ValueKey('played-card-${card.id}'),
                              card: card,
                            ),
                          ),
                        )
                        .toList(),
                  ),
            const SizedBox(height: 24),
            Text(
              'Cards left in deck: ${currentDeckService.deckCount}',
              key: const ValueKey('deck-count-text'),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Discard pile: ${currentDeckService.discardCount}',
              key: const ValueKey('discard-count-text'),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Card(
              key: const ValueKey('hand-money-card'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Money remaining: ${currentDeckService.availableMoney}',
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
              key: const ValueKey('shuffle-discard-button'),
              onPressed: currentDeckService.discardPile.isNotEmpty
                  ? _shuffleDiscardIntoDeck
                  : null,
              child: const Text('Shuffle New Cards Into Deck'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('end-turn-button'),
              onPressed: _endTurn,
              child: const Text('End Turn'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('reset-deck-button'),
              onPressed: _resetDeck,
              child: const Text('Reset & Shuffle Game'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Market row',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_gameService.marketRow.isEmpty)
              const Text('No cards available to buy.')
            else
              Column(
                children: _gameService.marketRow
                    .map(
                      (card) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PlayingCardWidget(
                          key: ValueKey('market-card-${card.id}'),
                          card: card,
                          actionLabel: 'Buy',
                          actionKey: ValueKey('buy-card-${card.id}'),
                          onActionPressed: _gameService.canAffordCard(card)
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
