import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/widgets/playing_card_widget.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.gameService});

  final GameService gameService;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameService _gameService;

  @override
  void initState() {
    super.initState();
    _gameService = widget.gameService;
  }

  void _drawCard() {
    final List<CardModel> drawnCards = _gameService.drawCards(2);

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
      _gameService.shuffleDiscardIntoDeck();
    });
  }

  void _buyCard(String cardId) {
    setState(() {
      _gameService.buyCardFromMarket(cardId);
    });
  }

  void _playCard(String cardId) {
    setState(() {
      _gameService.playCardFromHand(cardId);
    });
  }

  void _endTurn() {
    setState(() {
      _gameService.endTurn();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentPlayerState = _gameService.currentPlayer;

    return Scaffold(
      appBar: AppBar(
        title: Text('Deck Draw Demo - ${currentPlayerState.name}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlayerDashboardWidget(
              playerName: currentPlayerState.name,
              hand: currentPlayerState.deckService.hand,
              playedCards: currentPlayerState.deckService.playedCards,
              deckCount: currentPlayerState.deckService.deckCount,
              discardCount: currentPlayerState.deckService.discardCount,
              availableMoney: currentPlayerState.deckService.availableMoney,
              onPlayCard: _playCard,
            ),
            const SizedBox(height: 24),
            GameControlsWidget(
              onDrawCard: _drawCard,
              onShuffleDiscard: currentPlayerState.deckService.discardPile.isNotEmpty
                  ? _shuffleDiscardIntoDeck
                  : null,
              onEndTurn: _endTurn,
              onResetGame: _resetDeck,
            ),
            const SizedBox(height: 24),
            MarketRowWidget(
              marketRow: _gameService.marketRow,
              onBuyCard: _buyCard,
              canAffordCard: _gameService.canAffordCard,
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerDashboardWidget extends StatelessWidget {
  const PlayerDashboardWidget({
    super.key,
    required this.playerName,
    required this.hand,
    required this.playedCards,
    required this.deckCount,
    required this.discardCount,
    required this.availableMoney,
    required this.onPlayCard,
  });

  final String playerName;
  final List<CardModel> hand;
  final List<CardModel> playedCards;
  final int deckCount;
  final int discardCount;
  final int availableMoney;
  final ValueChanged<String> onPlayCard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$playerName\'s hand',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (hand.isEmpty)
          const Text('No cards in hand.', style: TextStyle(fontSize: 16))
        else
          Column(
            children: hand
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PlayingCardWidget(
                      key: ValueKey('hand-card-${card.id}'),
                      card: card,
                      actionLabel: 'Play',
                      actionKey: ValueKey('play-card-${card.id}'),
                      onActionPressed: () => onPlayCard(card.id),
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
        if (playedCards.isEmpty)
          const Text('No cards played.', style: TextStyle(fontSize: 16))
        else
          Column(
            children: playedCards
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
          'Cards left in deck: $deckCount',
          key: const ValueKey('deck-count-text'),
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          'Discard pile: $discardCount',
          key: const ValueKey('discard-count-text'),
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 8),
        Card(
          key: const ValueKey('hand-money-card'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Money remaining: $availableMoney',
              key: const ValueKey('available-money-text'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class GameControlsWidget extends StatelessWidget {
  const GameControlsWidget({
    super.key,
    required this.onDrawCard,
    required this.onShuffleDiscard,
    required this.onEndTurn,
    required this.onResetGame,
  });

  final VoidCallback onDrawCard;
  final VoidCallback? onShuffleDiscard;
  final VoidCallback onEndTurn;
  final VoidCallback onResetGame;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          key: const ValueKey('draw-card-button'),
          onPressed: onDrawCard,
          child: const Text('Draw 2 cards'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('shuffle-discard-button'),
          onPressed: onShuffleDiscard,
          child: const Text('Shuffle New Cards Into Deck'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('end-turn-button'),
          onPressed: onEndTurn,
          child: const Text('End Turn'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('reset-deck-button'),
          onPressed: onResetGame,
          child: const Text('Reset & Shuffle Game'),
        ),
      ],
    );
  }
}

class MarketRowWidget extends StatelessWidget {
  const MarketRowWidget({
    super.key,
    required this.marketRow,
    required this.onBuyCard,
    required this.canAffordCard,
  });

  final List<CardModel> marketRow;
  final ValueChanged<String> onBuyCard;
  final bool Function(CardModel) canAffordCard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Market row',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (marketRow.isEmpty)
          const Text('No cards available to buy.')
        else
          Column(
            children: marketRow
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PlayingCardWidget(
                      key: ValueKey('market-card-${card.id}'),
                      card: card,
                      actionLabel: 'Buy',
                      actionKey: ValueKey('buy-card-${card.id}'),
                      onActionPressed: canAffordCard(card)
                          ? () => onBuyCard(card.id)
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}
