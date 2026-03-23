import 'dart:collection';
import 'dart:math';

import 'package:simple_card_game/models/card_model.dart';

class DeckService {
  DeckService({Random? random}) : _random = random ?? Random() {
    initializeGame();
  }

  final Random _random;
  final List<CardModel> _deck = <CardModel>[];
  final List<CardModel> _discardPile = <CardModel>[];
  final List<CardModel> _hand = <CardModel>[];
  final List<CardModel> _marketRow = <CardModel>[];
  int _spentMoney = 0;

  UnmodifiableListView<CardModel> get deck => UnmodifiableListView(_deck);

  UnmodifiableListView<CardModel> get discardPile =>
      UnmodifiableListView(_discardPile);

  UnmodifiableListView<CardModel> get hand => UnmodifiableListView(_hand);

  UnmodifiableListView<CardModel> get marketRow =>
      UnmodifiableListView(_marketRow);

  CardModel? get lastDrawn => _hand.isEmpty ? null : _hand.last;

  int get availableMoney {
    final int handMoney = _hand.fold(0, (total, card) => total + card.moneyValue);
    final int remainingMoney = handMoney - _spentMoney;
    return remainingMoney < 0 ? 0 : remainingMoney;
  }

  int get deckCount => _deck.length;

  int get discardCount => _discardPile.length;

  int get marketCount => _marketRow.length;

  void initializeGame() {
    _deck
      ..clear()
      ..addAll(_buildStartingDeck())
      ..shuffle(_random);
    _discardPile.clear();
    _hand.clear();
    _marketRow
      ..clear()
      ..addAll(_buildMarketRow());
    _spentMoney = 0;
  }

  void resetGame() {
    initializeGame();
  }

  CardModel? drawCard() {
    if (_deck.isEmpty && _discardPile.isNotEmpty) {
      _deck
        ..addAll(_discardPile)
        ..shuffle(_random);
      _discardPile.clear();
    }

    if (_deck.isEmpty) {
      return null;
    }

    final CardModel drawnCard = _deck.removeLast();
    _hand.add(drawnCard);
    return drawnCard;
  }

  List<CardModel> drawCards(int count) {
    if (count <= 0) {
      return const <CardModel>[];
    }

    final List<CardModel> drawnCards = <CardModel>[];
    for (int i = 0; i < count; i++) {
      final CardModel? drawnCard = drawCard();
      if (drawnCard == null) {
        break;
      }
      drawnCards.add(drawnCard);
    }

    return drawnCards;
  }

  bool canAffordCard(CardModel card) {
    return availableMoney >= card.moneyValue;
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
    _discardPile.add(purchasedCard);
    _spentMoney += purchasedCard.moneyValue;
    return true;
  }

  List<CardModel> _buildStartingDeck() {
    return const <CardModel>[
      CardModel(id: 'c1', name: 'Coin +1', moneyValue: 1),
      CardModel(id: 'c2', name: 'Coin +1', moneyValue: 1),
      CardModel(id: 'c3', name: 'Coin +2', moneyValue: 2),
      CardModel(id: 'c4', name: 'Coin +2', moneyValue: 2),
      CardModel(id: 'c5', name: 'Coin +3', moneyValue: 3),
      CardModel(id: 'c6', name: 'Coin +4', moneyValue: 4),
    ];
  }

  List<CardModel> _buildMarketRow() {
    return const <CardModel>[
      CardModel(id: 'm1', name: 'Treasure +5', moneyValue: 5),
      CardModel(id: 'm2', name: 'Treasure +4', moneyValue: 4),
      CardModel(id: 'm3', name: 'Treasure +3', moneyValue: 3),
      CardModel(id: 'm4', name: 'Treasure +2', moneyValue: 2),
    ];
  }
}
