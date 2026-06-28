import 'package:flutter/material.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/ai_service.dart';
import 'package:simple_card_game/services/game_service.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/widgets/card_fan.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';
import 'package:simple_card_game/ui/widgets/resource_bar.dart';

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
  });

  final GameService gameService;
  final AiService? aiService;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  GameService get _game => widget.gameService;
  AiService? get _ai => widget.aiService;
  String? _selectedHandCardId;
  String? _actionMessage;
  bool _aiThinking = false;
  String? _lastPlayedCardId;

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
      final success = _game.playCard(card.id);
      setState(() {
        _selectedHandCardId = null;
        if (success) {
          _actionMessage = 'Played ${card.name}';
          _lastPlayedCardId = card.id;
        }
      });
      if (success) {
        // Clear the played highlight after a brief delay
        Future.delayed(const Duration(milliseconds: 400), () {
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

  void _playAllCards() {
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
    setState(() {
      if (_game.activateChampion(champion.id)) {
        _actionMessage = 'Activated ${champion.name}!';
      } else {
        _actionMessage = '${champion.name} already activated this turn';
      }
    });
  }

  void _buyCard(CardModel card) {
    final success = _game.buyCard(card.id);
    setState(() {
      if (success) {
        _actionMessage = 'Bought ${card.name}';
      } else {
        _actionMessage = 'Cannot afford ${card.name}';
      }
    });
  }

  void _endTurn() {
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

    return Scaffold(
      backgroundColor: GameTheme.boardBackground,
      body: SafeArea(
        child: Stack(
          children: [
            AbsorbPointer(
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
            // Turn indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Turn ${_game.turnNumber}',
                    style: const TextStyle(
                      color: GameTheme.textSecondary,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: GameTheme.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${currentPlayer.name}\'s Turn',
                    style: const TextStyle(
                      color: GameTheme.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Opponent areas (one per living opponent)
            for (final opponent in livingOpponents)
              _OpponentArea(
                opponent: opponent,
                canAttack: currentPlayer.powerPool > 0,
                onAttackChampion: (champ) =>
                    _attackChampion(champ, opponent.id),
                screenWidth: screenWidth,
              ),

            const SizedBox(height: 4),

            // Center row (market)
            _CenterRow(
              cards: _game.centerRow,
              canAfford: (card) => currentPlayer.gemPool >= card.cost,
              onBuy: _buyCard,
              infinityDeckCount: _game.infinityDeck.length,
              onLongPress: _showCardDetail,
              screenWidth: screenWidth,
            ),

            const SizedBox(height: 4),

            // Current player's played cards and champions
            _PlayArea(
              playedCards: currentPlayer.playedThisTurn,
              champions: currentPlayer.championsInPlay,
              activatedChampionIds: currentPlayer.activatedChampions,
              onActivateChampion: _activateChampion,
              lastPlayedCardId: _lastPlayedCardId,
              screenWidth: screenWidth,
            ),

            // Action message with fade animation
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _actionMessage != null
                  ? Padding(
                      key: ValueKey(_actionMessage),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      child: Text(
                        _actionMessage!,
                        style: const TextStyle(
                          color: GameTheme.gold,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : const SizedBox(height: 18),
            ),

            // Current player resource bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ResourceBar(
                health: currentPlayer.health,
                mastery: currentPlayer.mastery,
                gems: currentPlayer.gemPool,
                power: currentPlayer.powerPool,
                playerName: currentPlayer.name,
                isCurrentPlayer: true,
                deckCount: currentPlayer.drawPile.length,
                discardCount: currentPlayer.discardPile.length,
              ),
            ),

            // Action buttons row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  // Play All button
                  Expanded(
                    child: _ActionButton(
                      label: 'PLAY ALL',
                      icon: Icons.play_arrow,
                      color: GameTheme.gemCyan,
                      compact: Responsive.isMobile(screenWidth),
                      onPressed:
                          currentPlayer.hand.isNotEmpty ? _playAllCards : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Attack button - blocked by guard champions
                  Expanded(
                    child: _ActionButton(
                      label: hasGuards && currentPlayer.powerPool > 0
                          ? 'BLOCKED (${currentPlayer.powerPool})'
                          : 'ATTACK (${currentPlayer.powerPool})',
                      icon: hasGuards && currentPlayer.powerPool > 0
                          ? Icons.shield
                          : Icons.bolt,
                      color: hasGuards
                          ? GameTheme.textSecondary
                          : GameTheme.powerOrange,
                      compact: Responsive.isMobile(screenWidth),
                      onPressed: canDirectAttack ? _attackOpponent : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // End Turn button - always enabled, auto-plays cards first
                  Expanded(
                    child: _ActionButton(
                      label: currentPlayer.hand.isNotEmpty
                          ? 'PLAY & END'
                          : 'END TURN',
                      icon: Icons.skip_next,
                      color: GameTheme.endTurnGreen,
                      compact: Responsive.isMobile(screenWidth),
                      onPressed: _endTurn,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Hand fan
            Expanded(
              child: CardFan(
                cards: currentPlayer.hand,
                onCardTap: _playCard,
                onCardLongPress: _showCardDetail,
                selectedCardId: _selectedHandCardId,
              ),
            ),
          ],
        ),
                    ),
                  );
                },
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _OpponentArea extends StatelessWidget {
  const _OpponentArea({
    required this.opponent,
    required this.screenWidth,
    this.canAttack = false,
    this.onAttackChampion,
  });

  final dynamic opponent; // PlayerState
  final bool canAttack;
  final void Function(CardModel)? onAttackChampion;
  final double screenWidth;

  bool get _hasGuardChampions {
    for (final champ in opponent.championsInPlay) {
      if ((champ as CardModel).hasGuard) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final champions = opponent.championsInPlay as List;
    final champWidth = Responsive.compactCardWidth(screenWidth);
    final champHeight = champWidth * (130 / 90) + 10;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          ResourceBar(
            health: opponent.health,
            mastery: opponent.mastery,
            gems: opponent.gemPool,
            power: opponent.powerPool,
            playerName: opponent.name,
            deckCount: opponent.drawPile.length,
            discardCount: opponent.discardPile.length,
          ),
          if (champions.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_hasGuardChampions && canAttack)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.shield, size: 12, color: GameTheme.gold),
                        SizedBox(width: 4),
                        Text(
                          'Guard champions must be destroyed first!',
                          style: TextStyle(
                            color: GameTheme.gold,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: champHeight,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final champ in champions)
                        Padding(
                          padding: const EdgeInsets.only(right: 4, top: 4),
                          child: Stack(
                            children: [
                              GameCardWidget(
                                card: champ,
                                compact: true,
                                width: champWidth,
                                isHighlighted: canAttack,
                                onTap: canAttack && onAttackChampion != null
                                    ? () => onAttackChampion!(champ)
                                    : null,
                              ),
                              // Guard indicator overlay
                              if ((champ as CardModel).hasGuard)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: GameTheme.gold,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.shield,
                                      size: 10,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CenterRow extends StatelessWidget {
  const _CenterRow({
    required this.cards,
    required this.canAfford,
    required this.onBuy,
    required this.infinityDeckCount,
    required this.screenWidth,
    this.onLongPress,
  });

  final List<CardModel> cards;
  final bool Function(CardModel) canAfford;
  final void Function(CardModel) onBuy;
  final int infinityDeckCount;
  final void Function(CardModel)? onLongPress;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    final cardWidth = Responsive.handCardWidth(screenWidth);
    final rowHeight = cardWidth * (170 / 120) + 6;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: GameTheme.surfaceDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'CENTER ROW',
                style: TextStyle(
                  color: GameTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              const Icon(Icons.layers, size: 12, color: GameTheme.textSecondary),
              const SizedBox(width: 2),
              Text(
                '$infinityDeckCount',
                style: const TextStyle(
                  color: GameTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: rowHeight,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: cards.map((card) {
                final affordable = canAfford(card);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GameCardWidget(
                    card: card,
                    onTap: affordable ? () => onBuy(card) : null,
                    onLongPress: onLongPress != null
                        ? () => onLongPress!(card)
                        : null,
                    isHighlighted: affordable,
                    compact: false,
                    width: cardWidth,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayArea extends StatelessWidget {
  const _PlayArea({
    required this.playedCards,
    required this.champions,
    required this.screenWidth,
    this.activatedChampionIds = const {},
    this.onActivateChampion,
    this.lastPlayedCardId,
  });

  final List<CardModel> playedCards;
  final List<CardModel> champions;
  final Set<String> activatedChampionIds;
  final void Function(CardModel)? onActivateChampion;
  final String? lastPlayedCardId;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    if (champions.isEmpty && playedCards.isEmpty) {
      return const SizedBox(
        height: 50,
        child: Center(
          child: Text(
            'Play area',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ),
      );
    }

    final cardWidth = Responsive.compactCardWidth(screenWidth);
    // Room for the compact card plus the small "CHAMPIONS" header / padding.
    final areaHeight = cardWidth * (130 / 90) + 22;

    return SizedBox(
      height: areaHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Champions section (persistent, tappable to activate)
            if (champions.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: GameTheme.gold.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CHAMPIONS (tap to activate)',
                      style: TextStyle(
                        color: GameTheme.gold,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: champions.map((card) {
                          final isActivated =
                              activatedChampionIds.contains(card.id);
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Stack(
                              children: [
                                GameCardWidget(
                                  card: card,
                                  compact: true,
                                  showCost: false,
                                  width: cardWidth,
                                  isHighlighted: !isActivated,
                                  onTap: !isActivated &&
                                          onActivateChampion != null
                                      ? () => onActivateChampion!(card)
                                      : null,
                                ),
                                // Activated checkmark overlay
                                if (isActivated)
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: GameTheme.endTurnGreen,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
            // Played cards this turn
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: playedCards.map((card) {
                  final isJustPlayed = card.id == lastPlayedCardId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: AnimatedScale(
                      scale: isJustPlayed ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      child: GameCardWidget(
                        card: card,
                        compact: true,
                        showCost: false,
                        width: cardWidth,
                        isHighlighted: isJustPlayed,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  /// When true (mobile), the button uses a larger touch target and text.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    // Mobile gets a taller, easier-to-tap button (>= 48px) with bigger text.
    final verticalPadding = compact ? 14.0 : 10.0;
    final fontSize = compact ? 12.0 : 10.0;
    final iconSize = compact ? 18.0 : 16.0;
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isEnabled ? color : color.withValues(alpha: 0.3),
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.2),
        disabledForegroundColor: Colors.white38,
        padding:
            EdgeInsets.symmetric(horizontal: 8, vertical: verticalPadding),
        minimumSize: Size(0, compact ? Responsive.minTouchTarget : 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
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
