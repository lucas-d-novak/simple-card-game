import 'dart:collection';

import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/player_state.dart';
import 'package:simple_card_game/services/deck_service.dart';

class GameService {
  GameService({this.numPlayers = 2}) {
    initializeGame();
  }

  final int numPlayers;

  final List<PlayerState> players = [];
  int currentPlayerIndex = 0;

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
        deckService: DeckService(),
      ));
    }

    _marketRow.clear();
    _marketRow.addAll(_buildMarketRow());

    currentPlayerIndex = 0;
  }

  void resetGame() {
    initializeGame();
  }

  void endTurn(int drawCardsAmount) {
    // 1. Move active player's played cards to their discard pile
    currentPlayer.deckService.discardPlayedCards();

    // 2. Advance turn
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;

    // 3. Draw cards for next player automatically
    currentPlayer.deckService.drawCards(drawCardsAmount);
  }

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
    return true;
  }

  List<CardModel> _buildMarketRow() {
    return const <CardModel>[
      CardModel(
        id: 'm1',
        name: 'Treasure +5',
        cost: 5,
        playEffects: <CardEffect>[GainMoneyEffect(5)],
      ),
      CardModel(
        id: 'm2',
        name: 'Treasure +4',
        cost: 4,
        playEffects: <CardEffect>[GainMoneyEffect(4)],
      ),
      CardModel(
        id: 'm3',
        name: 'Treasure +3',
        cost: 3,
        playEffects: <CardEffect>[GainMoneyEffect(3)],
      ),
      CardModel(
        id: 'm4',
        name: 'Treasure +2',
        cost: 2,
        playEffects: <CardEffect>[GainMoneyEffect(2)],
      ),
      CardModel(
        id: 'm5',
        name: 'Scout',
        cost: 3,
        playEffects: <CardEffect>[DrawCardsEffect(2)],
      ),
    ];
  }
}
