import 'dart:collection';
import 'dart:math';

import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/player_state.dart';
import 'package:simple_card_game/services/deck_service.dart';

class GameService {
  GameService({this.numPlayers = 2, this.initialStartingHandSize = 5, Random? random})
    : _random = random ?? Random() {
    initializeGame();
  }

  final int numPlayers;
  final int initialStartingHandSize;
  final Random _random;

  final List<PlayerState> players = [];
  int currentPlayerIndex = 0;

  final List<CardModel> _marketDeck = <CardModel>[];
  final List<CardModel> _marketRow = <CardModel>[];

  UnmodifiableListView<CardModel> get marketRow =>
      UnmodifiableListView(_marketRow);

  PlayerState get currentPlayer => players[currentPlayerIndex];

  void initializeGame() {
    players.clear();
    for (int i = 0; i < numPlayers; i++) {
      players.add(PlayerState(
        id: 'p${i + 1}',
        name: 'Player ${i + 1}',
        deckService: DeckService(random: _random),
      ));
    }

    _marketDeck.clear();
    _marketRow.clear();
    _marketDeck.addAll(_buildMarketDeck());
    _marketDeck.shuffle(_random);
    
    for (int i = 0; i < 5; i++) {
      if (_marketDeck.isNotEmpty) {
        _marketRow.add(_marketDeck.removeLast());
      }
    }

    currentPlayerIndex = 0;
  }

  void resetGame() {
    initializeGame();
  }

  void endTurn() {
    // 1. Move active player's played cards to their discard pile
    currentPlayer.deckService.discardPlayedCards();

    // 2. Advance turn
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;

    // 3. Draw up to the initial starting hand size
    final int currentHandSize = currentPlayer.deckService.hand.length;
    int cardsToDraw = initialStartingHandSize - currentHandSize;
    if (cardsToDraw < 0) cardsToDraw = 0;
    
    if (cardsToDraw > 0) {
      currentPlayer.deckService.drawCards(cardsToDraw);
    }
  }

  // Delegation wrappers for encapsulated UI orchestration
  List<CardModel> drawCards(int count) => currentPlayer.deckService.drawCards(count);
  bool playCardFromHand(String cardId) => currentPlayer.deckService.playCardFromHand(cardId);
  bool shuffleDiscardIntoDeck() => currentPlayer.deckService.shuffleDiscardIntoDeck();

  bool canAffordCard(CardModel card) {
    return currentPlayer.deckService.canAfford(card.cost);
  }

  bool buyCardFromMarket(String cardId) {
    final int marketIndex = _marketRow.indexWhere((card) => card.id == cardId);
    if (marketIndex == -1) {
      return false;
    }

    final CardModel marketCard = _marketRow[marketIndex];
    if (!canAffordCard(marketCard)) {
      return false;
    }

    final CardModel purchasedCard = _marketRow.removeAt(marketIndex);
    currentPlayer.deckService.receivePurchasedCard(purchasedCard);
    
    if (_marketDeck.isNotEmpty) {
      _marketRow.add(_marketDeck.removeLast());
    }
    
    return true;
  }

  List<CardModel> _buildMarketDeck() {
    final List<CardModel> deck = <CardModel>[];
    for (int i = 0; i < 3; i++) {
      deck.addAll(<CardModel>[
        CardModel(
          id: 'm1_$i',
          name: 'Treasure +5',
          cost: 5,
          playEffects: const <CardEffect>[GainMoneyEffect(5)],
        ),
        CardModel(
          id: 'm2_$i',
          name: 'Treasure +4',
          cost: 4,
          playEffects: const <CardEffect>[GainMoneyEffect(4)],
        ),
        CardModel(
          id: 'm3_$i',
          name: 'Treasure +3',
          cost: 3,
          playEffects: const <CardEffect>[GainMoneyEffect(3)],
        ),
        CardModel(
          id: 'm4_$i',
          name: 'Treasure +2',
          cost: 2,
          playEffects: const <CardEffect>[GainMoneyEffect(2)],
        ),
        CardModel(
          id: 'm5_$i',
          name: 'Scout',
          cost: 3,
          playEffects: const <CardEffect>[DrawCardsEffect(2)],
        ),
      ]);
    }
    return deck;
  }
}
