# Flutter Deck Drawing Demo – Architecture & Step‑by‑Step Guide

This guide shows a **minimal Flutter app** where a single player taps a button to draw cards from a deck.

- Tech: Flutter
- Scope: Local-only, no backend, just in‑memory deck
- Goal: Have something simple that you (or an AI assistant) can extend into a full deck‑builder later.

---

## 1. Suggested Project / File Structure

For this tiny demo, you *can* keep everything in `lib/main.dart`.  
But here’s a simple structure that scales a bit better once you start adding more game logic:

```text
your_project/
├─ lib/
│  ├─ main.dart                     # Entry point; wires up MaterialApp & HomeScreen
│  ├─ models/
│  │   └─ card_model.dart           # Card data class
│  ├─ services/
│  │   └─ deck_service.dart         # (Optional) Deck logic: shuffle, draw, reset
│  └─ ui/
│      ├─ screens/
│      │   └─ home_screen.dart      # Simple screen with "Draw card" button
│      └─ widgets/
│          └─ playing_card_widget.dart  # (Optional) visual representation of a card
```

For the **first pass**, you can do everything in `main.dart`, then later split out:

- Move the `CardModel` into `models/card_model.dart`
- Move deck operations into `services/deck_service.dart`
- Move the UI widget into `ui/screens/home_screen.dart`

---

## 2. One‑Time Setup

1. **Create a new Flutter project** (from terminal):

   ```bash
   flutter create deck_draw_demo
   cd deck_draw_demo
   ```

2. Open the project in your editor (VS Code, Android Studio, etc.).

3. Replace the contents of `lib/main.dart` with the code in the next section.

4. Run the app:

   ```bash
   flutter run
   ```

   You should see:
   - A title bar “Deck Draw Demo”
   - Text showing the last drawn card
   - A button “Draw card”
   - A counter for how many cards remain in the deck

---

## 3. Minimal Example: Drawing Cards From a Deck

Below is a **single‑file Flutter example** that:

- Defines a simple `CardModel` (name + value)
- Creates an initial deck of money cards (1–4 money)
- Shuffles the deck on startup
- Lets the user tap “Draw card” to draw from the top of the deck
- Shows:
  - The last card drawn
  - How many cards are left

You can paste this entire file into `lib/main.dart`.

```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const DeckDrawApp());
}

/// Root widget
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

/// Simple card model for this demo
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

/// Home screen: shows deck + draw button
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
```

---

## 4. How to Evolve This Later

Once this works, you can:

1. **Move models into their own files**
   - Create `lib/models/card_model.dart`
   - Move `CardModel` there and import it into `main.dart` / other files.

2. **Create a `DeckService`**
   - New file: `lib/services/deck_service.dart`
   - Put functions like `initializeDeck()`, `shuffleDeck()`, `drawCard()`, etc.
   - Keep UI widgets dumb: they call the service instead of owning deck logic.

3. **Add a “market row”**
   - Another list of `CardModel` representing cards in the middle to buy.
   - A function `buyCardFromMarket()` that removes from the market and adds to a discard pile.

4. **Hook it into multiplayer / backend later**
   - Once the local deck logic is solid, you can sync deck state to a backend for async multiplayer.
   - For now, this file is a safe, minimal playground for your deck logic.
