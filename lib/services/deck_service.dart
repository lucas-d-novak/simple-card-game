import 'dart:collection';
import 'dart:math';

import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';

class DeckService {
  DeckService({Random? random}) : _random = random ?? Random() {
    initializeGame();
  }

  final Random _random;
  final List<CardModel> _deck = <CardModel>[];
  final List<CardModel> _discardPile = <CardModel>[];
  final List<CardModel> _hand = <CardModel>[];
  final List<CardModel> _playedCards = <CardModel>[];
  final List<CardModel> _marketRow = <CardModel>[];
  int _spentMoney = 0;
  CardModel? _lastDrawn;

  UnmodifiableListView<CardModel> get deck => UnmodifiableListView(_deck);

  UnmodifiableListView<CardModel> get discardPile =>
      UnmodifiableListView(_discardPile);

  UnmodifiableListView<CardModel> get hand => UnmodifiableListView(_hand);

  UnmodifiableListView<CardModel> get playedCards =>
      UnmodifiableListView(_playedCards);

  UnmodifiableListView<CardModel> get marketRow =>
      UnmodifiableListView(_marketRow);

  CardModel? get lastDrawn => _lastDrawn;

  int get availableMoney {
    final int playedMoney = _playedCards.fold(
      0,
      (total, card) => total + _moneyFromCard(card),
    );
    final int remainingMoney = playedMoney - _spentMoney;
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
    _playedCards.clear();
    _marketRow
      ..clear()
      ..addAll(_buildMarketRow());
    _spentMoney = 0;
    _lastDrawn = null;
  }

  void resetGame() {
    initializeGame();
  }

  bool shuffleDiscardIntoDeck() {
    if (_discardPile.isEmpty) {
      return false;
    }

    _moveDiscardPileIntoDeck();
    return true;
  }

  CardModel? drawCard() {
    if (_deck.isEmpty && _discardPile.isNotEmpty) {
      _moveDiscardPileIntoDeck();
    }

    if (_deck.isEmpty) {
      return null;
    }

    final CardModel drawnCard = _deck.removeLast();
    _hand.add(drawnCard);
    _lastDrawn = drawnCard;
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

  bool playCardFromHand(String cardId) {
    final int handIndex = _hand.indexWhere((card) => card.id == cardId);
    if (handIndex == -1) {
      return false;
    }

    final CardModel playedCard = _hand.removeAt(handIndex);
    _playedCards.add(playedCard);
    _applyCardEffects(playedCard);
    return true;
  }

  bool canAffordCard(CardModel card) {
    return availableMoney >= card.cost;
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
    _spentMoney += purchasedCard.cost;
    return true;
  }

  List<CardModel> _buildStartingDeck() {
    return const <CardModel>[
      CardModel(
        id: 'c1',
        name: 'Coin +1',
        cost: 1,
        playEffects: <CardEffect>[GainMoneyEffect(1)],
      ),
      CardModel(
        id: 'c2',
        name: 'Coin +1',
        cost: 1,
        playEffects: <CardEffect>[GainMoneyEffect(1)],
      ),
      CardModel(
        id: 'c3',
        name: 'Coin +2',
        cost: 2,
        playEffects: <CardEffect>[GainMoneyEffect(2)],
      ),
      CardModel(
        id: 'c4',
        name: 'Coin +2',
        cost: 2,
        playEffects: <CardEffect>[GainMoneyEffect(2)],
      ),
      CardModel(
        id: 'c5',
        name: 'Coin +3',
        cost: 3,
        playEffects: <CardEffect>[GainMoneyEffect(3)],
      ),
      CardModel(
        id: 'c6',
        name: 'Coin +4',
        cost: 4,
        playEffects: <CardEffect>[GainMoneyEffect(4)],
      ),
    ];
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

  void _applyCardEffects(CardModel card) {
    for (final CardEffect effect in card.playEffects) {
      switch (effect) {
        case GainMoneyEffect():
          break;
        case DrawCardsEffect():
          drawCards(effect.count);
      }
    }
  }

  int _moneyFromCard(CardModel card) {
    return card.playEffects
        .whereType<GainMoneyEffect>()
        .fold(0, (total, effect) => total + effect.amount);
  }

  void _moveDiscardPileIntoDeck() {
    _deck
      ..addAll(_discardPile)
      ..shuffle(_random);
    _discardPile.clear();
  }
}
