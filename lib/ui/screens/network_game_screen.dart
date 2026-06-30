import 'package:flutter/material.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/card_database_asset.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';

/// Networked game view — renders the server's REDACTED state for this player and
/// sends actions over the [GameClient]. The engine never runs on the client for
/// networked games; this widget is a thin terminal over the authoritative state.
///
/// This is the functional Phase-2 view (hand, center row, both players' public
/// stats, turn indicator, core actions). The polished board (game_screen.dart's
/// chrome) can be ported on top of this data source later.
class NetworkGameScreen extends StatefulWidget {
  const NetworkGameScreen({super.key, required this.client});

  final GameClient client;

  @override
  State<NetworkGameScreen> createState() => _NetworkGameScreenState();
}

class _NetworkGameScreenState extends State<NetworkGameScreen> {
  CardDatabase? _db;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onChanged);
    // Load the card DB so we can show card names instead of bare ids.
    CardDatabaseAsset.load().then((db) {
      if (mounted) setState(() => _db = db);
    }).catchError((_) {/* names fall back to ids */});
  }

  @override
  void dispose() {
    widget.client.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Display name for a card id (strip instance suffix → DB name, else the id).
  String _cardName(String id) {
    final rec = _db?.byId(id);
    if (rec != null) return rec.name;
    // starter-deck instance ids like p0_crystal_3 → "Crystal"
    final m = RegExp(r'_(crystal|blaster|shard|reactor)_?\d*$').firstMatch(id);
    if (m != null) {
      final base = m.group(1)!;
      return base[0].toUpperCase() + base.substring(1);
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final state = client.gameState;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: CustomPaint(painter: BoardBackdropPainter())),
          SafeArea(
            child: state == null
                ? const Center(
                    child: Text('Waiting for game state…',
                        style: TextStyle(color: Colors.white70)))
                : _board(client, state),
          ),
        ],
      ),
    );
  }

  Widget _board(GameClient client, Map<String, dynamic> state) {
    final players = (state['players'] as List).cast<Map>();
    final me = state['you'] as String?;
    final myTurn = client.isMyTurn;
    final centerRow = (state['centerRow'] as List? ?? const []).cast<String>();
    final mine = players.firstWhere((p) => p['id'] == me, orElse: () => {});
    final hand = (mine['hand'] as List? ?? const []).cast<String>();
    final gems = mine['gemPool'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Turn banner.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: myTurn ? const Color(0xFF1B5E20) : const Color(0xFF37474F),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              myTurn ? 'YOUR TURN' : "Waiting for opponent…",
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ),
          const SizedBox(height: 8),
          // Players' public stats.
          Row(
            children: [
              for (final p in players) Expanded(child: _playerChip(p, p['id'] == me)),
            ],
          ),
          const SizedBox(height: 12),
          _sectionLabel('Center row'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in centerRow)
                _cardButton(_cardName(id),
                    enabled: myTurn, onTap: () => client.buyCard(id)),
            ],
          ),
          const SizedBox(height: 12),
          _sectionLabel('Your hand ($gems gems)'),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in hand)
                    _cardButton(_cardName(id),
                        enabled: myTurn, onTap: () => client.playCard(id)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Action bar.
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: myTurn ? client.playAllCards : null,
                  child: const Text('Play All'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: myTurn ? client.endTurn : null,
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0)),
                  child: const Text('End Turn'),
                ),
              ),
            ],
          ),
          if (state['isGameOver'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('GAME OVER — winner: ${state['winnerId'] ?? '—'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFFE8C45A),
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
            ),
        ],
      ),
    );
  }

  Widget _playerChip(Map p, bool isMe) {
    final hand = p['hand'] as List?;
    final handLabel = hand != null ? '${hand.length}' : '${p['handCount'] ?? 0}';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF12283F) : const Color(0xFF1B2A38),
        border: Border.all(
            color: isMe ? const Color(0xFF5FD0E6) : Colors.white24, width: isMe ? 2 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p['id']}${isMe ? ' (you)' : ''}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('HP ${p['health']}   ★${p['mastery']}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text('gems ${p['gemPool']}  pow ${p['powerPool']}  hand $handLabel',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFFE8C45A),
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      );

  Widget _cardButton(String label,
      {required bool enabled, required VoidCallback onTap}) {
    return SizedBox(
      width: 110,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFF1B3A57),
          side: const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        ),
        child: Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }
}
