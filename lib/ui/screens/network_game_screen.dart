import 'package:flutter/material.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/card_database_asset.dart';
import 'package:simple_card_game/data/starter_deck.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/widgets/beveled_button.dart';
import 'package:simple_card_game/ui/widgets/card_fan.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';
import 'package:simple_card_game/ui/widgets/resource_icons.dart';

/// Networked game view — renders the server's REDACTED state for this player
/// with the SAME polished board chrome as the local [GameScreen], and sends
/// actions over the [GameClient].
///
/// The engine never runs on the client for networked games: this widget is a
/// presentation layer over the authoritative redacted view. Card ids are
/// reconstructed into [CardModel]s via the [CardDatabase] purely for display.
/// Hidden information is honoured structurally — the opponent's hand arrives as
/// a COUNT only, so it is drawn as face-down backs; no opponent card identity is
/// ever available to render.
class NetworkGameScreen extends StatefulWidget {
  const NetworkGameScreen({super.key, required this.client});

  final GameClient client;

  @override
  State<NetworkGameScreen> createState() => _NetworkGameScreenState();
}

class _NetworkGameScreenState extends State<NetworkGameScreen> {
  CardDatabase? _db;
  // Synthetic starter cards (Crystal/Blaster/Shards/Reactor) by instance id,
  // so p0_crystal_3 etc. resolve to a real CardModel for display.
  final Map<String, CardModel> _starter = {};
  String? _actionMessage;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onChanged);
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

  void _flash(String msg) {
    setState(() => _actionMessage = msg);
  }

  // ---- card reconstruction ------------------------------------------------

  /// Resolve a card id from the redacted state into a displayable [CardModel].
  /// DB cards win; starter instance ids (p0_crystal_3) map to the canonical
  /// starter template with the instance id preserved (so widget keys are
  /// stable). Unknown ids become a bare placeholder so the board still renders.
  CardModel _card(String id) {
    final rec = _db?.byId(id);
    if (rec != null) return rec.model;

    final cached = _starter[id];
    if (cached != null) return cached;

    // Build a fresh per-instance CardModel so the widget key (card.id) stays
    // unique even when a player holds several crystals.
    final template = _starterTemplateFor(id);
    final model = template != null
        ? CardModel(
            id: id,
            name: template.name,
            cost: template.cost,
            playEffects: template.playEffects,
            faction: template.faction,
            cardType: template.cardType,
          )
        : CardModel(
            id: id,
            name: _humanizeId(id),
            cost: 0,
            playEffects: const [],
            faction: Faction.none,
          );
    _starter[id] = model;
    return model;
  }

  /// Match a starter instance id (p0_crystal_3, p1_blaster, …) to its template
  /// drawn from the canonical 10-card starter deck.
  CardModel? _starterTemplateFor(String id) {
    final m = RegExp(r'(crystal|blaster|shard|reactor)').firstMatch(id);
    if (m == null) return null;
    final base = m.group(1)!;
    final deck = buildStarterDeck('seed'); // template stats only
    for (final c in deck) {
      final n = c.name.toLowerCase();
      if (base == 'crystal' && n.contains('crystal')) return c;
      if (base == 'blaster' && n.contains('blaster')) return c;
      if (base == 'reactor' && n.contains('reactor')) return c;
      if (base == 'shard' && n.contains('shard') && !n.contains('reactor')) {
        return c;
      }
    }
    return null;
  }

  String _humanizeId(String id) {
    final core = id.replaceFirst(RegExp(r'^p\d+_'), '').replaceAll('_', ' ');
    if (core.isEmpty) return id;
    return core[0].toUpperCase() + core.substring(1);
  }

  // ---- actions ------------------------------------------------------------

  void _onHandTap(CardModel card) {
    widget.client.playCard(card.id);
    _flash('Played ${card.name}');
  }

  void _onCenterTap(CardModel card) {
    widget.client.buyCard(card.id);
    _flash('Recruiting ${card.name}…');
  }

  void _onMyChampionTap(CardModel champ) {
    widget.client.activateChampion(champ.id);
    _flash('Activated ${champ.name}');
  }

  void _onOpponentChampionTap(CardModel champ, String ownerId) {
    widget.client.attackChampion(champ.id, ownerId);
    _flash('Attacking ${champ.name}');
  }

  void _onAttackPlayer(_PlayerView opponent, int power) {
    widget.client.attackPlayer(opponent.id, power);
    _flash('Dealt $power to ${opponent.name}');
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final state = client.gameState;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: BoardBackdropPainter()),
          ),
          SafeArea(
            child: state == null
                ? const Center(
                    child: Text(
                      'Waiting for game state…',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final view = _GameView.parse(state, client.playerId);
                      if (view.isGameOver) {
                        return _NetworkGameOver(view: view, client: client);
                      }
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: Responsive.maxContentWidth,
                          ),
                          child: _board(client, view, constraints.maxWidth),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _board(GameClient client, _GameView view, double screenWidth) {
    final me = view.me;
    final opponent = view.firstOpponent;
    final myTurn = client.isMyTurn;
    // Guard status isn't in the redacted state per champion — resolve each
    // opponent champion id to its card and check the model's hasGuard flag.
    final opponentHasGuard =
        view.opponentChampionIds.any((id) => _card(id).hasGuard);
    final canAttackPlayer =
        myTurn && me.powerPool > 0 && opponent != null && !opponentHasGuard;

    return Column(
      children: [
        // ---- Top bar: opponent pill + turn banner -------------------------
        _NetworkTopBar(opponent: opponent, myTurn: myTurn),

        // ---- Helper / status line -----------------------------------------
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Text(
            myTurn
                ? 'Your turn — play cards, recruit, attack, then End Turn'
                : 'Waiting for ${opponent?.name ?? 'opponent'}…',
            style: const TextStyle(
              color: Color(0xFFBFD8E8),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        // ---- Center row (market) ------------------------------------------
        _NetworkCenterRow(
          cards: [for (final id in view.centerRow) _card(id)],
          canAfford: (c) => myTurn && me.gemPool >= c.cost,
          onTapCard: myTurn ? _onCenterTap : (_) {},
          screenWidth: screenWidth,
        ),

        // ---- Play field ----------------------------------------------------
        Expanded(
          child: _NetworkPlayField(
            opponentChampions: opponent?.champions ?? const [],
            opponentId: opponent?.id,
            cardFor: _card,
            canAttackChampions: myTurn && me.powerPool > 0,
            onAttackChampion: _onOpponentChampionTap,
            myChampions: me.champions,
            playedThisTurn: me.playedThisTurn,
            onActivateChampion: myTurn ? _onMyChampionTap : null,
            actionMessage: _actionMessage,
            screenWidth: screenWidth,
          ),
        ),

        // ---- Bottom zone: End Turn + chips + hand + Play All --------------
        _NetworkBottomZone(
          me: me,
          screenWidth: screenWidth,
          hand: [for (final id in me.hand) _card(id)],
          enabled: myTurn,
          onCardTap: _onHandTap,
          onEndTurn: myTurn ? client.endTurn : null,
          onPlayAll: myTurn && me.hand.isNotEmpty ? client.playAllCards : null,
          onAttack: canAttackPlayer
              ? () => _onAttackPlayer(opponent, me.powerPool)
              : null,
          hasGuards: opponentHasGuard,
        ),
      ],
    );
  }
}

// ===========================================================================
// Redacted-state view models
// ===========================================================================

/// Typed projection of the server's redacted state map.
class _GameView {
  _GameView({
    required this.players,
    required this.meId,
    required this.centerRow,
    required this.currentPlayerIndex,
    required this.turnNumber,
    required this.isGameOver,
    required this.winnerId,
  });

  final List<_PlayerView> players;
  final String meId;
  final List<String> centerRow;
  final int currentPlayerIndex;
  final int turnNumber;
  final bool isGameOver;
  final String? winnerId;

  _PlayerView get me =>
      players.firstWhere((p) => p.id == meId, orElse: () => players.first);

  _PlayerView? get firstOpponent {
    for (final p in players) {
      if (p.id != meId && !p.eliminated) return p;
    }
    return null;
  }

  /// Ids of all living opponents' champions in play (guard status must be
  /// resolved against the card DB by the caller, since the redacted state does
  /// not carry per-champion guard flags).
  List<String> get opponentChampionIds => [
        for (final p in players)
          if (p.id != meId && !p.eliminated)
            for (final c in p.champions) c.id,
      ];

  static _GameView parse(Map<String, dynamic> state, String fallbackId) {
    final rawPlayers = (state['players'] as List? ?? const []).cast<Map>();
    // The redacted state identifies the recipient by ENGINE SEAT id via `you`
    // (e.g. p1), NOT the lobby name the client connected with. Always trust
    // `you`; fall back to the lobby id only if the server omitted it.
    final meId = (state['you'] as String?) ?? fallbackId;
    return _GameView(
      players: [for (final p in rawPlayers) _PlayerView.parse(p)],
      meId: meId,
      centerRow: (state['centerRow'] as List? ?? const []).cast<String>(),
      currentPlayerIndex: (state['currentPlayerIndex'] as int?) ?? 0,
      turnNumber: (state['turnNumber'] as int?) ?? 1,
      isGameOver: state['isGameOver'] == true,
      winnerId: state['winnerId'] as String?,
    );
  }
}

/// One player's public (+ own-hand) redacted slice.
class _PlayerView {
  _PlayerView({
    required this.id,
    required this.name,
    required this.health,
    required this.mastery,
    required this.gemPool,
    required this.powerPool,
    required this.eliminated,
    required this.hand,
    required this.handCount,
    required this.drawPileCount,
    required this.discardCount,
    required this.champions,
    required this.playedThisTurn,
  });

  final String id;
  final String name;
  final int health;
  final int mastery;
  final int gemPool;
  final int powerPool;
  final bool eliminated;

  /// Full ids ONLY for the recipient; empty for opponents (hidden info).
  final List<String> hand;

  /// Card count — always available, even when [hand] is hidden.
  final int handCount;
  final int drawPileCount;
  final int discardCount;
  final List<_ChampionView> champions;
  final List<String> playedThisTurn;

  static _PlayerView parse(Map p) {
    final hand = (p['hand'] as List?)?.cast<String>() ?? const <String>[];
    return _PlayerView(
      id: p['id'] as String,
      name: (p['name'] as String?) ?? (p['id'] as String),
      health: (p['health'] as int?) ?? 0,
      mastery: (p['mastery'] as int?) ?? 0,
      gemPool: (p['gemPool'] as int?) ?? 0,
      powerPool: (p['powerPool'] as int?) ?? 0,
      eliminated: p['eliminated'] == true,
      hand: hand,
      handCount: (p['handCount'] as int?) ?? hand.length,
      drawPileCount: (p['drawPileCount'] as int?) ?? 0,
      discardCount: (p['discardPile'] as List?)?.length ?? 0,
      champions: [
        for (final c in (p['championsInPlay'] as List? ?? const []).cast<Map>())
          _ChampionView.parse(c),
      ],
      playedThisTurn:
          (p['playedThisTurn'] as List?)?.cast<String>() ?? const <String>[],
    );
  }
}

/// A champion in play (public): id + tap/exhaust status + under-card count.
class _ChampionView {
  _ChampionView({
    required this.id,
    required this.exhausted,
    required this.activated,
    required this.underCount,
  });

  final String id;
  final bool exhausted;
  final bool activated;
  final int underCount;

  static _ChampionView parse(Map c) => _ChampionView(
        id: c['id'] as String,
        exhausted: c['exhausted'] == true,
        activated: c['activated'] == true,
        underCount: (c['underCount'] as int?) ?? 0,
      );
}

// ===========================================================================
// Sub-widgets (mirror game_screen.dart chrome, redacted-state driven)
// ===========================================================================

/// Top bar — centered opponent pill (HP/mastery/gems) + a turn badge.
class _NetworkTopBar extends StatelessWidget {
  const _NetworkTopBar({required this.opponent, required this.myTurn});

  final _PlayerView? opponent;
  final bool myTurn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (opponent != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 96),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _OpponentPill(opponent: opponent!),
                ),
              ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: myTurn
                        ? const Color(0xFF19C39C)
                        : const Color(0xFF37474F),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: myTurn
                          ? BoardChrome.greenSheen
                          : Colors.white24,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    myTurn ? 'YOUR TURN' : 'WAITING',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpponentPill extends StatelessWidget {
  const _OpponentPill({required this.opponent});
  final _PlayerView opponent;

  @override
  Widget build(BuildContext context) {
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
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF3E6E8E), Color(0xFF1B3650)],
              ),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: const Icon(Icons.person, size: 15, color: Colors.white70),
          ),
          const SizedBox(width: 6),
          Text(
            opponent.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          _StatChip(icon: ResourceIcon.health, value: opponent.health),
          const SizedBox(width: 8),
          _StatChip(icon: ResourceIcon.mastery, value: opponent.mastery),
          const SizedBox(width: 8),
          _StatChip(icon: ResourceIcon.gem, value: opponent.gemPool),
          const SizedBox(width: 10),
          // Opponent hand size (count-only — hidden info).
          _MiniCount(icon: Icons.style, value: opponent.handCount),
        ],
      ),
    );
  }
}

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

class _MiniCount extends StatelessWidget {
  const _MiniCount({required this.icon, required this.value});
  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white60),
        const SizedBox(width: 2),
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Center row — 6 market cards, sized to fit the row width (mirrors
/// game_screen.dart's _CenterRow).
class _NetworkCenterRow extends StatelessWidget {
  const _NetworkCenterRow({
    required this.cards,
    required this.canAfford,
    required this.onTapCard,
    required this.screenWidth,
  });

  final List<CardModel> cards;
  final bool Function(CardModel) canAfford;
  final void Function(CardModel) onTapCard;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    final usable = (screenWidth - 16).clamp(0.0, Responsive.maxContentWidth);
    final slot = usable / 6;
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
            for (final card in cards)
              GameCardWidget(
                key: ValueKey(card.id),
                card: card,
                onTap: () => onTapCard(card),
                isHighlighted: canAfford(card),
                width: cardWidth,
              ),
          ],
        ),
      ),
    );
  }
}

/// Play field — opponent champions (top) + my champions / played cards.
class _NetworkPlayField extends StatelessWidget {
  const _NetworkPlayField({
    required this.opponentChampions,
    required this.opponentId,
    required this.cardFor,
    required this.canAttackChampions,
    required this.onAttackChampion,
    required this.myChampions,
    required this.playedThisTurn,
    required this.onActivateChampion,
    required this.actionMessage,
    required this.screenWidth,
  });

  final List<_ChampionView> opponentChampions;
  final String? opponentId;
  final CardModel Function(String id) cardFor;
  final bool canAttackChampions;
  final void Function(CardModel champ, String ownerId) onAttackChampion;
  final List<_ChampionView> myChampions;
  final List<String> playedThisTurn;
  final void Function(CardModel)? onActivateChampion;
  final String? actionMessage;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    final cardWidth = Responsive.compactCardWidth(screenWidth);
    final champHeight = cardWidth * (130 / 90) + 4;

    return Stack(
      children: [
        Column(
          children: [
            // Opponent champions row (just under the center row).
            if (opponentChampions.isNotEmpty && opponentId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: champHeight,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final champ in opponentChampions)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: GameCardWidget(
                            card: cardFor(champ.id),
                            compact: true,
                            width: cardWidth,
                            isHighlighted: canAttackChampions,
                            onTap: canAttackChampions
                                ? () => onAttackChampion(
                                    cardFor(champ.id), opponentId!)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const Spacer(),
            // My champions + played-this-turn row, just above the hand.
            if (myChampions.isNotEmpty || playedThisTurn.isNotEmpty)
              SizedBox(
                height: champHeight,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final champ in myChampions)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Stack(
                          children: [
                            GameCardWidget(
                              card: cardFor(champ.id),
                              compact: true,
                              showCost: false,
                              width: cardWidth,
                              isHighlighted: !champ.activated,
                              onTap: onActivateChampion != null
                                  ? () => onActivateChampion!(cardFor(champ.id))
                                  : null,
                            ),
                            if (champ.activated)
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
                    for (final id in playedThisTurn)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: GameCardWidget(
                          card: cardFor(id),
                          compact: true,
                          showCost: false,
                          width: cardWidth,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
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

/// Bottom zone — End Turn + my resource chips + draw pile | hand fan |
/// power diamond + Play All / Attack + discard pile.
class _NetworkBottomZone extends StatelessWidget {
  const _NetworkBottomZone({
    required this.me,
    required this.screenWidth,
    required this.hand,
    required this.enabled,
    required this.onCardTap,
    required this.onEndTurn,
    required this.onPlayAll,
    required this.onAttack,
    required this.hasGuards,
  });

  final _PlayerView me;
  final double screenWidth;
  final List<CardModel> hand;
  final bool enabled;
  final void Function(CardModel) onCardTap;
  final VoidCallback? onEndTurn;
  final VoidCallback? onPlayAll;
  final VoidCallback? onAttack;
  final bool hasGuards;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(screenWidth);
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
              BeveledButton(
                label: 'End Turn',
                onPressed: onEndTurn,
                width: isMobile ? 120 : 150,
                height: 40,
                fontSize: isMobile ? 16 : 20,
              ),
              const SizedBox(height: 4),
              Row(
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
                      icon: ResourceIcon.health,
                      value: me.health,
                      fontSize: 14),
                  const SizedBox(width: 8),
                  _StatChip(
                      icon: ResourceIcon.mastery,
                      value: me.mastery,
                      fontSize: 14),
                  const SizedBox(width: 8),
                  _StatChip(
                      icon: ResourceIcon.gem,
                      value: me.gemPool,
                      fontSize: 14),
                ],
              ),
              const SizedBox(height: 4),
              _PileHex(count: me.drawPileCount, style: _PileStyle.draw),
            ],
          ),
          const SizedBox(width: 8),
          // Power diamond.
          _ValueDiamond(value: me.powerPool),
          const SizedBox(width: 4),
          // Center: hand fan.
          Expanded(
            child: CardFan(
              cards: hand,
              onCardTap: enabled ? onCardTap : (_) {},
              selectedCardId: null,
            ),
          ),
          const SizedBox(width: 4),
          // Right column: Attack (if any) + Play All + discard hex.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (onAttack != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: BeveledButton(
                    label: 'Attack',
                    onPressed: onAttack,
                    width: isMobile ? 96 : 132,
                    height: 34,
                    fontSize: isMobile ? 14 : 18,
                  ),
                )
              else if (hasGuards)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Guard blocks',
                    style: TextStyle(
                        color: Color(0xFFE8C45A),
                        fontSize: 11,
                        fontStyle: FontStyle.italic),
                  ),
                ),
              BeveledButton(
                label: 'Play All',
                onPressed: onPlayAll,
                style: BeveledStyle.green,
                width: isMobile ? 96 : 132,
                height: isMobile ? 56 : 80,
                fontSize: isMobile ? 18 : 26,
                radius: 16,
              ),
              const SizedBox(height: 4),
              _PileHex(count: me.discardCount, style: _PileStyle.discard),
            ],
          ),
        ],
      ),
    );
  }
}

enum _PileStyle { draw, discard }

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
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
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

class _ValueDiamond extends StatelessWidget {
  const _ValueDiamond({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398,
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

/// Game-over panel for the networked view (mirrors the local game-over screen,
/// driven by the redacted state).
class _NetworkGameOver extends StatelessWidget {
  const _NetworkGameOver({required this.view, required this.client});
  final _GameView view;
  final GameClient client;

  @override
  Widget build(BuildContext context) {
    final winner = view.winnerId != null
        ? view.players.where((p) => p.id == view.winnerId).firstOrNull
        : view.players.where((p) => !p.eliminated).firstOrNull;
    final winnerName = winner?.name ?? 'Unknown';
    final iWon = winner != null && winner.id == view.meId;
    final isMasteryWin = winner != null && winner.mastery >= 30;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iWon ? Icons.emoji_events : Icons.flag,
                size: 64, color: GameTheme.gold),
            const SizedBox(height: 16),
            Text(
              iWon ? 'Victory!' : '$winnerName Wins',
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
                  : 'Opponent eliminated',
              style: const TextStyle(
                color: GameTheme.textSecondary,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 24),
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
                  for (final p in view.players)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            p.id == winner?.id
                                ? Icons.emoji_events
                                : p.eliminated
                                    ? Icons.close
                                    : Icons.person,
                            size: 16,
                            color: p.id == winner?.id
                                ? GameTheme.gold
                                : GameTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${p.name}${p.id == view.meId ? ' (you)' : ''}',
                              style: TextStyle(
                                color: p.id == winner?.id
                                    ? GameTheme.gold
                                    : GameTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: p.id == winner?.id
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          Text(
                            'HP: ${p.health}',
                            style: TextStyle(
                              color: p.health > 0
                                  ? GameTheme.healthGreen
                                  : GameTheme.healthRed,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'M: ${p.mastery}',
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
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: GameTheme.textPrimary,
                side: const BorderSide(color: GameTheme.textSecondary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
              child: const Text('Back to Lobby', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
