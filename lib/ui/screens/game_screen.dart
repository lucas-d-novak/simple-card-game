import 'package:flutter/material.dart';
import 'package:simple_card_game/data/database/game_state_codec.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/ai_service.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/theme/animation_timing.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/widgets/beveled_button.dart';
import 'package:simple_card_game/ui/widgets/card_detail_modal.dart';
import 'package:simple_card_game/ui/widgets/card_fan.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';
import 'package:simple_card_game/ui/widgets/resource_icons.dart';

/// The main game screen for Shards of Infinity.
/// Layout (top to bottom):
///   1. Opponent resource bar
///   2. Opponent champions in play
///   3. Center row (market) - 6 buyable cards
///   4. Current player's played cards & champions
///   5. Current player resource bar + action buttons
///   6. Card fan (hand) at bottom
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.gameService,
    this.aiService,
    this.debugOpenModal,
  });

  final GameService gameService;
  final AiService? aiService;

  /// Visual-iteration hook: when set ('recruit' / 'exhaust'), auto-opens the
  /// matching card-detail modal after first frame so the capture pipeline can
  /// screenshot it without a tap. Null in normal play.
  final String? debugOpenModal;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  // The engine + AI are held as swappable State fields (rather than read
  // straight off the widget) so Undo can replace the live GameService with a
  // decoded snapshot. The AiService is recreated to point at the new engine on
  // every swap so a vs-AI game never desyncs against a stale GameService.
  late GameService _game;
  late AiService? _ai;
  String? _selectedHandCardId;
  String? _actionMessage;
  bool _aiThinking = false;
  String? _lastPlayedCardId;

  /// LIFO stack of full game-state snapshots. Each user-initiated mutating
  /// action pushes one BEFORE mutating, so Undo restores the prior state.
  /// Bounded to keep memory flat in long games; cleared on endTurn so undo is
  /// scoped to the current turn (you cannot undo across a turn boundary, which
  /// would otherwise re-run the opponent/AI turn into a different state).
  final List<Map<String, dynamic>> _undoStack = [];
  static const int _maxUndoDepth = 50;

  bool get _canUndo => _undoStack.isNotEmpty && !_aiThinking;

  /// Capture a snapshot of the current engine state onto the undo stack. Call
  /// this immediately BEFORE any user-initiated mutation of [_game].
  void _pushUndo() {
    _undoStack.add(GameStateCodec.encode(_game));
    if (_undoStack.length > _maxUndoDepth) {
      _undoStack.removeAt(0);
    }
  }

  /// Pop the most recent snapshot and replace the live engine with it. The
  /// AiService (if any) is rebuilt against the restored engine so it never
  /// points at a discarded GameService.
  void _undo() {
    if (_undoStack.isEmpty) return;
    final snapshot = _undoStack.removeLast();
    final restored = GameStateCodec.decode(snapshot);
    setState(() {
      _game = restored;
      final ai = _ai;
      if (ai != null) {
        _ai = AiService(game: restored, aiPlayerId: ai.aiPlayerId)
          ..phaseDelay = ai.phaseDelay;
      }
      _selectedHandCardId = null;
      _lastPlayedCardId = null;
      _actionMessage = 'Undid last action';
    });
  }

  @override
  void initState() {
    super.initState();
    _game = widget.gameService;
    _ai = widget.aiService;
    final which = widget.debugOpenModal;
    if (which != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (which == 'recruit' && _game.centerRow.isNotEmpty) {
          _openCenterRowDetail(_game.centerRow[(_game.centerRow.length / 2)
              .floor()]);
        } else if (which == 'exhaust') {
          // Ensure a champion is on the board for the capture pipeline.
          final champs = _game.currentPlayer.championsInPlay;
          if (champs.isEmpty) {
            final champ = _game.centerRow.firstWhere(
              (c) => c.cardType == CardType.champion,
              orElse: () => _game.centerRow.first,
            );
            _game.currentPlayer.championsInPlay.add(champ);
          }
          if (_game.currentPlayer.championsInPlay.isNotEmpty) {
            _openChampionDetail(
                _game.currentPlayer.championsInPlay.first);
          }
        }
      });
    }
  }

  void _playCard(CardModel card) {
    if (_selectedHandCardId == card.id) {
      // Check if card has a ChooseOneEffect — show picker dialog
      final chooseEffect = card.playEffects
          .whereType<ChooseOneEffect>()
          .firstOrNull;
      if (chooseEffect != null) {
        _showChoiceDialog(card, chooseEffect);
        return;
      }
      _pushUndo();
      final success = _game.playCard(card.id);
      setState(() {
        _selectedHandCardId = null;
        if (success) {
          _actionMessage = 'Played ${card.name}';
          _lastPlayedCardId = card.id;
        }
      });
      if (success) {
        // Clear the played highlight after a brief delay (scaled by speed;
        // zero under instant / reduced motion).
        final highlightDelay = AnimationTiming.of(context).phaseDelay;
        Future.delayed(highlightDelay, () {
          if (mounted) {
            setState(() => _lastPlayedCardId = null);
          }
        });
        _handlePostPlayEffects(card);
      }
    } else {
      setState(() {
        _selectedHandCardId = card.id;
      });
    }
  }

  /// After a card is played, check for effects that require player selection.
  void _handlePostPlayEffects(CardModel card) {
    for (final effect in card.playEffects) {
      if (effect is BanishCardEffect) {
        _showBanishDialog(effect.source);
        return;
      }
      if (effect is ScrapFromCenterRowEffect) {
        _showScrapDialog();
        return;
      }
    }
  }

  void _showBanishDialog(BanishSource source) {
    final player = _game.currentPlayer;
    final candidates = <_BanishCandidate>[];

    if (source == BanishSource.hand || source == BanishSource.handOrDiscard) {
      for (final c in player.hand) {
        candidates.add(_BanishCandidate(c, 'Hand'));
      }
    }
    if (source == BanishSource.discard ||
        source == BanishSource.handOrDiscard) {
      for (final c in player.discardPile) {
        candidates.add(_BanishCandidate(c, 'Discard'));
      }
    }

    if (candidates.isEmpty) {
      setState(() => _actionMessage = 'No cards to banish');
      return;
    }

    showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: GameTheme.surfaceDark,
        title: const Text(
          'Banish a Card',
          style: TextStyle(color: GameTheme.gold, fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (_, i) {
              final bc = candidates[i];
              return ListTile(
                title: Text(
                  bc.card.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: Text(
                  bc.zone,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                onTap: () => Navigator.of(ctx).pop(bc.card.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Skip', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    ).then((cardId) {
      if (cardId != null) {
        final success = _game.banishCard(cardId, source);
        setState(() {
          _actionMessage = success ? 'Banished a card' : 'Banish failed';
        });
      }
    });
  }

  void _showScrapDialog() {
    final cards = _game.centerRow;
    if (cards.isEmpty) {
      setState(() => _actionMessage = 'No cards to scrap');
      return;
    }

    showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: GameTheme.surfaceDark,
        title: const Text(
          'Scrap from Center Row',
          style: TextStyle(color: GameTheme.gold, fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: cards.length,
            itemBuilder: (_, i) {
              final card = cards[i];
              return ListTile(
                title: Text(
                  card.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: Text(
                  'Cost: ${card.cost}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                onTap: () => Navigator.of(ctx).pop(card.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Skip', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    ).then((cardId) {
      if (cardId != null) {
        final success = _game.scrapFromCenterRow(cardId);
        setState(() {
          _actionMessage = success ? 'Scrapped a card' : 'Scrap failed';
        });
      }
    });
  }

  void _showChoiceDialog(CardModel card, ChooseOneEffect effect) {
    showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: GameTheme.surfaceDark,
        title: Text(
          card.name,
          style: const TextStyle(color: GameTheme.gold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose an effect:',
              style: TextStyle(color: GameTheme.textPrimary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < effect.choices.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(i),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GameTheme.surfaceMid,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    effect.choices[i]
                        .map((e) => e.description)
                        .join(', '),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    ).then((choiceIndex) {
      if (choiceIndex != null) {
        _pushUndo();
        final success = _game.playCard(card.id, choiceIndex: choiceIndex);
        setState(() {
          _selectedHandCardId = null;
          if (success) {
            _actionMessage = 'Played ${card.name}';
          }
        });
      }
    });
  }

  void _showCardDetail(CardModel card) {
    final factionColor = FactionColors.getPrimary(card.faction);
    final factionName = card.faction == Faction.none
        ? 'Factionless'
        : card.faction.name[0].toUpperCase() + card.faction.name.substring(1);
    final cardTypeName = switch (card.cardType) {
      CardType.regular => 'Regular',
      CardType.champion => 'Champion',
      CardType.mercenary => 'Mercenary',
    };

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: GameTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Card name header
              Text(
                card.name,
                style: TextStyle(
                  color: factionColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),

              // Faction label
              Text(
                factionName,
                style: TextStyle(
                  color: factionColor.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const Divider(color: Colors.white24, height: 20),

              // Type row
              _DetailRow(label: 'Type', value: cardTypeName),

              // Cost (only if > 0)
              if (card.cost > 0)
                _DetailRow(label: 'Cost', value: '${card.cost} gems'),

              // Shield (champions only)
              if (card.cardType == CardType.champion && card.shield > 0)
                _DetailRow(label: 'Shield', value: '${card.shield}'),

              // Guard badge
              if (card.hasGuard)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GameTheme.gold.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'GUARD — Must be destroyed before attacking player',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Play effects
              if (card.playEffects.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Effects:',
                  style: TextStyle(
                    color: GameTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                for (final effect in card.playEffects)
                  _EffectRow(text: effect.description),
              ],

              // Ally ability
              if (card.allyAbility.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Ally Ability:',
                  style: TextStyle(
                    color: GameTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                for (final effect in card.allyAbility)
                  _EffectRow(
                    text: effect.description,
                    color: factionColor.withValues(alpha: 0.9),
                  ),
              ],

              // Mastery bonus
              if (card.masteryThreshold != null &&
                  card.masteryBonus.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Mastery ${card.masteryThreshold}+:',
                  style: const TextStyle(
                    color: GameTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                for (final effect in card.masteryBonus)
                  _EffectRow(
                    text: effect.description,
                    color: Colors.deepPurple.shade200,
                  ),
              ],

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: factionColor,
                  ),
                  child: const Text('CLOSE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the official-style card-detail modal for a center-row card, with a
  /// circular "Recruit" action that buys the card if affordable. Arrows page
  /// through the whole center row.
  void _openCenterRowDetail(CardModel card) {
    final row = _game.centerRow;
    final start = row.indexWhere((c) => c.id == card.id);
    if (start < 0) return;
    showCardDetailModal(
      context,
      cards: row,
      initialIndex: start,
      actionFor: (c) => CardDetailAction(
        label: 'Recruit',
        enabled: _game.currentPlayer.gemPool >= c.cost,
        onPressed: () => _buyCard(c),
      ),
    );
  }

  /// Opens the card-detail modal for one of the current player's champions,
  /// with a circular "Exhaust" action that activates it (once per turn).
  void _openChampionDetail(CardModel champion) {
    final champs = _game.currentPlayer.championsInPlay;
    final start = champs.indexWhere((c) => c.id == champion.id);
    if (start < 0) return;
    showCardDetailModal(
      context,
      cards: champs,
      initialIndex: start,
      actionFor: (c) => CardDetailAction(
        label: 'Exhaust',
        enabled: !_game.currentPlayer.activatedChampions.contains(c.id),
        onPressed: () => _activateChampion(c),
      ),
    );
  }

  void _playAllCards() {
    _pushUndo();
    setState(() {
      final played = _game.playAllCards();
      _actionMessage = 'Played $played cards';
      _selectedHandCardId = null;
    });
  }

  void _attackOpponent() {
    if (_game.currentPlayer.powerPool <= 0) return;
    final opponents = _game.players
        .where((p) => p.id != _game.currentPlayer.id && !p.isEliminated)
        .toList();
    if (opponents.isEmpty) return;

    if (opponents.length == 1) {
      _doAttackPlayer(opponents.first.id);
    } else {
      _showAttackTargetDialog(opponents);
    }
  }

  void _doAttackPlayer(String targetId) {
    _pushUndo();
    setState(() {
      final power = _game.currentPlayer.powerPool;
      final target = _game.players.firstWhere((p) => p.id == targetId);
      if (_game.attackPlayer(targetId, power)) {
        _actionMessage = 'Dealt $power damage to ${target.name}!';
      } else {
        _actionMessage = 'Cannot attack ${target.name} directly';
      }
    });
  }

  void _showAttackTargetDialog(List<dynamic> opponents) {
    showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: GameTheme.surfaceDark,
        title: const Text(
          'Choose a target',
          style: TextStyle(color: GameTheme.gold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Who do you want to attack?',
              style: TextStyle(color: GameTheme.textPrimary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final opponent in opponents)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(opponent.id as String),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GameTheme.surfaceMid,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        opponent.name as String,
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        '${opponent.health} HP',
                        style: const TextStyle(
                          fontSize: 12,
                          color: GameTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ).then((targetId) {
      if (targetId != null) {
        _doAttackPlayer(targetId);
      }
    });
  }

  void _attackChampion(CardModel champion, String ownerId) {
    if (_game.currentPlayer.powerPool <= 0) return;
    _pushUndo();
    setState(() {
      if (_game.attackChampion(champion.id, ownerId)) {
        _actionMessage =
            'Destroyed ${champion.name}! (cost ${champion.shield} power)';
      } else {
        _actionMessage =
            'Need ${champion.shield} power to destroy ${champion.name}';
      }
    });
  }

  void _activateChampion(CardModel champion) {
    _pushUndo();
    setState(() {
      if (_game.activateChampion(champion.id)) {
        _actionMessage = 'Activated ${champion.name}!';
      } else {
        _actionMessage = '${champion.name} already activated this turn';
      }
    });
  }

  void _buyCard(CardModel card) {
    _pushUndo();
    final success = _game.buyCard(card.id);
    setState(() {
      if (success) {
        _actionMessage = 'Bought ${card.name}';
      } else {
        _actionMessage = 'Cannot afford ${card.name}';
      }
    });
  }

  void _focus() {
    _pushUndo();
    setState(() {
      if (_game.focus()) {
        _actionMessage = 'Focus: spent 1 gem → +1 mastery';
      }
    });
  }

  /// Minimal local UI hook for the Destiny system (Into the Horizon): when a
  /// Destiny supply is enabled and the current player may claim/use a Destiny,
  /// this returns the action to run; the board calls it from the (future)
  /// Destiny-row widget. Returns null when no Destiny action is available, which
  /// is always the case on the live single-player board today (no
  /// `destinySupply` is wired into [GameService]). Keeping this as a small,
  /// referenced helper makes the engine API discoverable from the UI without
  /// introducing a half-built dialog or changing any visible behavior/goldens.
  /// See [GameService.claimDestiny] / [GameService.useDestinyAbility].
  VoidCallback? destinyActionFor(String destinyId) {
    if (_game.destinyRow.isEmpty && _game.currentPlayer.claimedDestinies.isEmpty) {
      return null;
    }
    final canClaim =
        _game.destinyRow.any((c) => c.id == destinyId);
    return () {
      setState(() {
        final ok = canClaim
            ? _game.claimDestiny(destinyId)
            : _game.useDestinyAbility(destinyId);
        if (ok) {
          _actionMessage = canClaim ? 'Claimed Destiny' : 'Used Destiny ability';
        }
      });
    };
  }

  void _endTurn() {
    // Undo is scoped to the current turn: once the turn ends (and the AI/next
    // player acts), the prior in-turn snapshots are no longer meaningful, so
    // the stack is cleared.
    _undoStack.clear();
    setState(() {
      // Auto-play remaining cards before ending turn
      if (_game.currentPlayer.hand.isNotEmpty) {
        final played = _game.playAllCards();
        if (played > 0) {
          _actionMessage = 'Auto-played $played cards';
        }
      }
      // End turn — unspent power/gems are lost per the rules
      _game.endTurn();
      _selectedHandCardId = null;
      _actionMessage =
          'Turn ${_game.turnNumber} - ${_game.currentPlayer.name}\'s turn';
    });

    // If the next player is AI, trigger AI turn
    _maybeRunAiTurn();
  }

  void _maybeRunAiTurn() {
    if (_ai == null) return;
    if (_game.isGameOver) return;
    if (_game.currentPlayer.id != _ai!.aiPlayerId) return;

    setState(() {
      _aiThinking = true;
      _actionMessage = 'AI is thinking...';
    });

    _ai!.takeTurn().then((_) {
      if (mounted) {
        setState(() {
          _aiThinking = false;
          _actionMessage =
              'Turn ${_game.turnNumber} - ${_game.currentPlayer.name}\'s turn';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_game.isGameOver) {
      return _GameOverScreen(
        game: _game,
        onRestart: () {
          Navigator.of(context).pop();
        },
        onRematch: () {
          final playerCount = _game.players.length;
          final newGame = GameService(playerCount: playerCount);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => GameScreen(gameService: newGame),
            ),
          );
        },
      );
    }

    final currentPlayer = _game.currentPlayer;
    final livingOpponents = _game.players
        .where((p) => p.id != currentPlayer.id && !p.isEliminated)
        .toList();
    // Blocked if ANY living opponent has a guard champion
    final hasGuards = livingOpponents.any(
      (opp) => opp.championsInPlay.any((c) => c.hasGuard),
    );
    final canDirectAttack = currentPlayer.powerPool > 0 && !hasGuards;

    final opponent = livingOpponents.isNotEmpty ? livingOpponents.first : null;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Painted board backdrop (deep blue-teal + central glow).
          const Positioned.fill(
            child: CustomPaint(painter: BoardBackdropPainter()),
          ),
          SafeArea(
            child: AbsorbPointer(
              absorbing: _aiThinking,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = constraints.maxWidth;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: Responsive.maxContentWidth,
                      ),
                      child: Column(
                        children: [
                          // ---- Top bar: opponent pill + hamburger ----------
                          _TopBar(
                            opponent: opponent,
                            allOpponents: livingOpponents,
                          ),

                          // ---- Helper line --------------------------------
                          const Padding(
                            padding: EdgeInsets.only(top: 2, bottom: 4),
                            child: Text(
                              'Drag to Play cards, Exhaust champions, '
                              'or Recruit from the center row',
                              style: TextStyle(
                                color: Color(0xFFBFD8E8),
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                          // ---- Center row (6 market cards) ----------------
                          _CenterRow(
                            cards: _game.centerRow,
                            canAfford: (card) =>
                                currentPlayer.gemPool >= card.cost,
                            onTapCard: _openCenterRowDetail,
                            infinityDeckCount: _game.infinityDeck.length,
                            onLongPress: _showCardDetail,
                            screenWidth: screenWidth,
                          ),

                          // ---- Play area (opponent champs + played) -------
                          Expanded(
                            child: _PlayField(
                              opponentChampions:
                                  opponent?.championsInPlay ?? const [],
                              opponentId: opponent?.id,
                              canAttackChampions:
                                  currentPlayer.powerPool > 0,
                              onAttackChampion: (champ, ownerId) =>
                                  _attackChampion(champ, ownerId),
                              playedCards: currentPlayer.playedThisTurn,
                              champions: currentPlayer.championsInPlay,
                              activatedChampionIds:
                                  currentPlayer.activatedChampions,
                              onActivateChampion: _openChampionDetail,
                              lastPlayedCardId: _lastPlayedCardId,
                              actionMessage: _actionMessage,
                              screenWidth: screenWidth,
                            ),
                          ),

                          // ---- Bottom zone: chrome + hand -----------------
                          _BottomZone(
                            player: currentPlayer,
                            screenWidth: screenWidth,
                            hand: currentPlayer.hand,
                            selectedCardId: _selectedHandCardId,
                            onCardTap: _playCard,
                            onCardLongPress: _showCardDetail,
                            onEndTurn: _endTurn,
                            onUndo: _canUndo ? _undo : null,
                            onPlayAll: currentPlayer.hand.isNotEmpty
                                ? _playAllCards
                                : null,
                            onAttack: canDirectAttack ? _attackOpponent : null,
                            hasGuards: hasGuards,
                            onFocus: (!currentPlayer.focusedThisTurn &&
                                    currentPlayer.gemPool >= 1)
                                ? _focus
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // AI thinking overlay
          if (_aiThinking)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: GameTheme.gold),
                    SizedBox(height: 16),
                    Text(
                      'AI is thinking...',
                      style: TextStyle(
                        color: GameTheme.gold,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Top bar — centered opponent pill + hamburger menu
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.opponent, required this.allOpponents});

  final dynamic opponent; // PlayerState?
  final List<dynamic> allOpponents;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Centered opponent pill (kept clear of the hamburger via padding
            // so the right-most stat chip is never clipped). FittedBox lets it
            // shrink rather than overflow on very narrow screens.
            if (opponent != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _OpponentPill(opponent: opponent),
                ),
              ),
            // Hamburger top-right.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(child: _HamburgerButton()),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpponentPill extends StatelessWidget {
  const _OpponentPill({required this.opponent});
  final dynamic opponent; // PlayerState

  @override
  Widget build(BuildContext context) {
    final name = opponent.name as String;
    final label = name == 'Player 2' ? 'Hard AI' : name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF14405E), Color(0xFF0B2236)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: BoardChrome.tealHighlight.withValues(alpha: 0.7),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: BoardChrome.tealHighlight.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar disc.
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFE5443B), Color(0xFF7A1E18)],
              ),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: const Icon(Icons.smart_toy,
                size: 15, color: Colors.white70),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: ResourceIcon.health,
            value: opponent.health as int,
          ),
          const SizedBox(width: 8),
          _StatChip(
            icon: ResourceIcon.mastery,
            value: opponent.mastery as int,
          ),
          const SizedBox(width: 8),
          _StatChip(
            icon: ResourceIcon.gem,
            value: opponent.gemPool as int,
          ),
        ],
      ),
    );
  }
}

/// A small icon + value pair used in the opponent pill and resource chip row.
class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.value, this.fontSize = 15});
  final ResourceIcon icon;
  final int value;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ResourceIconWidget(icon, size: fontSize + 2),
        const SizedBox(width: 3),
        Text(
          '$value',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _HamburgerButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          bottomLeft: Radius.circular(6),
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(6),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BoardChrome.tealHighlight,
            BoardChrome.tealBody,
            BoardChrome.tealShadow,
          ],
        ),
        border: Border.all(color: BoardChrome.tealRim, width: 1.2),
      ),
      child: const Icon(Icons.menu, size: 18, color: Color(0xFF0B2236)),
    );
  }
}

// ---------------------------------------------------------------------------
// Center row (6 market cards, evenly spaced, no chrome box)
// ---------------------------------------------------------------------------

class _CenterRow extends StatelessWidget {
  const _CenterRow({
    required this.cards,
    required this.canAfford,
    required this.onTapCard,
    required this.infinityDeckCount,
    required this.screenWidth,
    this.onLongPress,
  });

  final List<CardModel> cards;
  final bool Function(CardModel) canAfford;
  final void Function(CardModel) onTapCard;
  final int infinityDeckCount;
  final void Function(CardModel)? onLongPress;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    final refillDuration = AnimationTiming.of(context).cardMove;
    // Size cards so 6 fit the row width evenly (like the reference). Cap the
    // width so the row leaves room for the play area + hand below, matching the
    // reference proportions (cards ~36% of board height, not the full top half).
    final usable = (screenWidth - 16).clamp(0.0, Responsive.maxContentWidth);
    final slot = usable / 6;
    // Allow cards to shrink on very narrow screens so all six always fit the
    // row width (no horizontal overflow), but cap the size on wide screens.
    final cardWidth = (slot - 8).clamp(46.0, 138.0);
    final rowHeight = cardWidth * (170 / 120) + 4;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: rowHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < cards.length; i++)
              AnimatedSwitcher(
                duration: refillDuration,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Builder(
                  key: ValueKey(cards[i].id),
                  builder: (context) {
                    final card = cards[i];
                    final affordable = canAfford(card);
                    return GameCardWidget(
                      card: card,
                      onTap: () => onTapCard(card),
                      onLongPress: onLongPress != null
                          ? () => onLongPress!(card)
                          : null,
                      isHighlighted: affordable,
                      compact: false,
                      width: cardWidth,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Play field — opponent champions (top) + played cards / your champions
// ---------------------------------------------------------------------------

class _PlayField extends StatelessWidget {
  const _PlayField({
    required this.opponentChampions,
    required this.opponentId,
    required this.canAttackChampions,
    required this.onAttackChampion,
    required this.playedCards,
    required this.champions,
    required this.activatedChampionIds,
    required this.onActivateChampion,
    required this.lastPlayedCardId,
    required this.actionMessage,
    required this.screenWidth,
  });

  final List<dynamic> opponentChampions;
  final String? opponentId;
  final bool canAttackChampions;
  final void Function(CardModel champ, String ownerId) onAttackChampion;
  final List<CardModel> playedCards;
  final List<CardModel> champions;
  final Set<String> activatedChampionIds;
  final void Function(CardModel)? onActivateChampion;
  final String? lastPlayedCardId;
  final String? actionMessage;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    final cardWidth = Responsive.compactCardWidth(screenWidth);
    return Stack(
      children: [
        Column(
          children: [
            // Opponent champions row (just under the center row).
            if (opponentChampions.isNotEmpty && opponentId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: cardWidth * (130 / 90) + 4,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final champ in opponentChampions)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: GameCardWidget(
                            card: champ as CardModel,
                            compact: true,
                            width: cardWidth,
                            isHighlighted: canAttackChampions,
                            onTap: canAttackChampions
                                ? () => onAttackChampion(champ, opponentId!)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const Spacer(),
            // Your champions + played-this-turn row sit just above the hand.
            if (champions.isNotEmpty || playedCards.isNotEmpty)
              SizedBox(
                height: cardWidth * (130 / 90) + 4,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final card in champions)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Stack(
                          children: [
                            GameCardWidget(
                              card: card,
                              compact: true,
                              showCost: false,
                              width: cardWidth,
                              isHighlighted:
                                  !activatedChampionIds.contains(card.id),
                              onTap: onActivateChampion != null
                                  ? () => onActivateChampion!(card)
                                  : null,
                            ),
                            if (activatedChampionIds.contains(card.id))
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: GameTheme.endTurnGreen,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(Icons.check,
                                      size: 10, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    for (final card in playedCards)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: AnimatedScale(
                          scale: card.id == lastPlayedCardId ? 1.12 : 1.0,
                          duration: AnimationTiming.of(context).cardMove,
                          curve: Curves.easeOutBack,
                          child: GameCardWidget(
                            card: card,
                            compact: true,
                            showCost: false,
                            width: cardWidth,
                            isHighlighted: card.id == lastPlayedCardId,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        // Action message floats over the play area centre.
        if (actionMessage != null)
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    actionMessage!,
                    style: const TextStyle(
                      color: BoardChrome.goldText,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom zone — End Turn + resource chips + draw hex | hand | power | Play All
// ---------------------------------------------------------------------------

class _BottomZone extends StatelessWidget {
  const _BottomZone({
    required this.player,
    required this.screenWidth,
    required this.hand,
    required this.selectedCardId,
    required this.onCardTap,
    required this.onCardLongPress,
    required this.onEndTurn,
    required this.onUndo,
    required this.onPlayAll,
    required this.onAttack,
    required this.hasGuards,
    required this.onFocus,
  });

  final dynamic player; // PlayerState
  final double screenWidth;
  final List<CardModel> hand;
  final String? selectedCardId;
  final void Function(CardModel) onCardTap;
  final void Function(CardModel) onCardLongPress;
  final VoidCallback onEndTurn;

  /// Undo the last action. Null (button disabled) when there is nothing to undo
  /// or the AI is acting.
  final VoidCallback? onUndo;
  final VoidCallback? onPlayAll;
  final VoidCallback? onAttack;
  final bool hasGuards;

  /// Character Focus (1 gem → 1 mastery). Null when unavailable this turn.
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(screenWidth);
    final power = player.powerPool as int;
    // Bottom row strip with a subtle teal-tinted band like the reference.
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0E2C44).withValues(alpha: 0.0),
            const Color(0xFF0E2C44).withValues(alpha: 0.55),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left column: End Turn + resource chips + draw pile hex.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FittedBox lets the End Turn + Undo row shrink rather than
              // overflow on the narrowest mobile widths.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BeveledButton(
                      label: 'End Turn',
                      onPressed: onEndTurn,
                      width: isMobile ? 110 : 150,
                      height: 40,
                      fontSize: isMobile ? 15 : 20,
                    ),
                    const SizedBox(width: 6),
                    _UndoButton(onPressed: onUndo),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3E6E8E), Color(0xFF1B3650)],
                      ),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.person,
                        size: 14, color: Colors.white70),
                  ),
                  const SizedBox(width: 6),
                  _StatChip(
                    icon: ResourceIcon.mastery,
                    value: player.mastery as int,
                    fontSize: 14,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    icon: ResourceIcon.gem,
                    value: player.gemPool as int,
                    fontSize: 14,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _FocusButton(onPressed: onFocus),
              const SizedBox(height: 4),
              _PileHex(
                count: player.drawPile.length as int,
                style: _PileStyle.draw,
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Power diamond (gems/power available for the turn).
          _ValueDiamond(value: power),
          const SizedBox(width: 4),
          // Center: hand fan.
          Expanded(
            child: CardFan(
              cards: hand,
              onCardTap: onCardTap,
              onCardLongPress: onCardLongPress,
              selectedCardId: selectedCardId,
            ),
          ),
          const SizedBox(width: 4),
          // Right column: Play All button + discard hex.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BeveledButton(
                label: 'Play All',
                onPressed: onPlayAll,
                style: BeveledStyle.green,
                width: isMobile ? 96 : 132,
                height: isMobile ? 64 : 92,
                fontSize: isMobile ? 20 : 28,
                radius: 16,
              ),
              const SizedBox(height: 4),
              _PileHex(
                count: player.discardPile.length as int,
                style: _PileStyle.discard,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small "Focus" pill — spend 1 gem to gain 1 mastery (once per turn). Greyed
/// out when unavailable (already focused this turn / no gems).
class _FocusButton extends StatelessWidget {
  const _FocusButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF7B4FC0), Color(0xFF4A2A78)],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFFB89AE8).withValues(alpha: 0.8),
                width: 1.2),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ResourceIconWidget(ResourceIcon.gem, size: 13),
              Text('→', style: TextStyle(color: Colors.white, fontSize: 12)),
              ResourceIconWidget(ResourceIcon.mastery, size: 13),
              SizedBox(width: 4),
              Text('Focus',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "Undo" button shown next to End Turn. Greyed out and non-interactive
/// when [onPressed] is null (nothing to undo, or the AI is acting).
class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          key: const ValueKey('undo_button'),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3E6E8E), Color(0xFF1B3650)],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: BoardChrome.tealHighlight.withValues(alpha: 0.7),
              width: 1.2,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.undo, size: 16, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'Undo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PileStyle { draw, discard }

/// A small beveled hex showing a pile count — green for the draw pile,
/// red-brown for the discard pile (matching the reference corners).
class _PileHex extends StatelessWidget {
  const _PileHex({required this.count, required this.style});
  final int count;
  final _PileStyle style;

  @override
  Widget build(BuildContext context) {
    final isDraw = style == _PileStyle.draw;
    final colors = isDraw
        ? const [Color(0xFF2FA85B), Color(0xFF16622F)]
        : const [Color(0xFF9A4A2E), Color(0xFF5A2415)];
    return Container(
      width: 44,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
        ),
      ),
    );
  }
}

/// The diamond badge showing available power/gems for the turn.
class _ValueDiamond extends StatelessWidget {
  const _ValueDiamond({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEAF2F6), Color(0xFFAFC4D0)],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        child: Transform.rotate(
          angle: -0.785398,
          child: Text(
            '$value',
            style: const TextStyle(
              color: Color(0xFF14405E),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _GameOverScreen extends StatelessWidget {
  const _GameOverScreen({
    required this.game,
    required this.onRestart,
    required this.onRematch,
  });
  final GameService game;
  final VoidCallback onRestart;
  final VoidCallback onRematch;

  @override
  Widget build(BuildContext context) {
    final winner = game.winnerId != null
        ? game.players.where((p) => p.id == game.winnerId).firstOrNull
        : game.players.where((p) => !p.isEliminated).firstOrNull;
    final winnerName = winner?.name ?? 'Unknown';
    final isMasteryWin = winner != null && winner.mastery >= 30;

    return Scaffold(
      backgroundColor: GameTheme.boardBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emoji_events, size: 64, color: GameTheme.gold),
              const SizedBox(height: 16),
              Text(
                '$winnerName Wins!',
                style: const TextStyle(
                  color: GameTheme.gold,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isMasteryWin
                    ? 'Infinity Shard victory at Mastery ${winner.mastery}'
                    : 'Eliminated all opponents',
                style: const TextStyle(
                  color: GameTheme.textSecondary,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Turn ${game.turnNumber}',
                style: const TextStyle(
                  color: GameTheme.textSecondary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              // Player stats table
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GameTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Final Standings',
                      style: TextStyle(
                        color: GameTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final player in game.players)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              player.id == winner?.id
                                  ? Icons.emoji_events
                                  : player.isEliminated
                                      ? Icons.close
                                      : Icons.person,
                              size: 16,
                              color: player.id == winner?.id
                                  ? GameTheme.gold
                                  : GameTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                player.name,
                                style: TextStyle(
                                  color: player.id == winner?.id
                                      ? GameTheme.gold
                                      : GameTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: player.id == winner?.id
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Text(
                              'HP: ${player.health}',
                              style: TextStyle(
                                color: player.health > 0
                                    ? GameTheme.healthGreen
                                    : GameTheme.healthRed,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'M: ${player.mastery}',
                              style: const TextStyle(
                                color: GameTheme.masteryPurple,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: onRematch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GameTheme.endTurnGreen,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                    ),
                    child: const Text('Rematch',
                        style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: onRestart,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: GameTheme.textPrimary,
                      side: const BorderSide(color: GameTheme.textSecondary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                    ),
                    child: const Text('New Game',
                        style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card detail dialog helpers
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: GameTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: GameTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EffectRow extends StatelessWidget {
  const _EffectRow({required this.text, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3, left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              color: color ?? GameTheme.textPrimary,
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color ?? GameTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BanishCandidate {
  const _BanishCandidate(this.card, this.zone);
  final CardModel card;
  final String zone;
}
