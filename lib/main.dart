import 'package:flutter/material.dart';

void main() {
  runApp(const DeckDrawApp());
}

/// Root widget for the deck drawing demo.
class DeckDrawApp extends StatelessWidget {
  const DeckDrawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deck Draw Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

/// Simple card model for this demo.
class CardModel {
  final String id;
  final String name;
  final int moneyValue; // how much money this card gives when played

  const CardModel({
    required this.id,
    required this.name,
    required this.moneyValue,
  });
}

/// Home screen: shows deck + draw button.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // In a “real” app, this starting deck would be built elsewhere.
  late List<CardModel> _deck;
  CardModel? _lastDrawn;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeDeck();
  }

  void _initializeDeck() {
    // Simple starting deck: a few cards that give 1–4 money
    final startingCards = <CardModel>[
      const CardModel(id: 'c1', name: 'Coin +1', moneyValue: 1),
      const CardModel(id: 'c2', name: 'Coin +1', moneyValue: 1),
      const CardModel(id: 'c3', name: 'Coin +2', moneyValue: 2),
      const CardModel(id: 'c4', name: 'Coin +2', moneyValue: 2),
      const CardModel(id: 'c5', name: 'Coin +3', moneyValue: 3),
      const CardModel(id: 'c6', name: 'Coin +4', moneyValue: 4),
    ];

    _deck = List<CardModel>.from(startingCards)..shuffle();
    _lastDrawn = null;
    _initialized = true;
  }

  void _drawCard() {
    if (_deck.isEmpty) {
      // For now, just show a snackbar; later, you can reshuffle a discard pile.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deck is empty!')),
      );
      return;
    }

    setState(() {
      _lastDrawn = _deck.removeLast(); // draw from top (end of list)
    });
  }

  void _resetDeck() {
    setState(() {
      _initializeDeck();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deck Draw Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Last drawn card:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _lastDrawn == null
                ? const Text('No card drawn yet.',
                    style: TextStyle(fontSize: 16))
                : Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _lastDrawn!.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('Money value: ${_lastDrawn!.moneyValue}'),
                        ],
                      ),
                    ),
                  ),
            const SizedBox(height: 24),
            Text(
              'Cards left in deck: ${_deck.length}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _drawCard,
              child: const Text('Draw card'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _resetDeck,
              child: const Text('Reset & Shuffle Deck'),
            ),
          ],
        ),
      ),
    );
  }
}
