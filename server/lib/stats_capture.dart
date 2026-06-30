// Telemetry capture — builds the decision snapshots and outcome events that
// GameSession.apply hands to the StatsStore. Pulled out of game_session.dart so
// the (somewhat fiddly) feature extraction is independently unit-testable and
// the session stays small.
//
// HIDDEN-INFO RULE (hard — mirrors server/lib/views.dart redaction):
//   * the actor's OWN hand is part of their legal information set -> hand card
//     ids ARE captured for `play` options and in selfState.handCardIds.
//   * every OPPONENT hand is a COUNT only (handCount). We NEVER read an
//     opponent's hand cards.
//   * NO draw-pile ORDER is ever captured — only sizes (deckSize / drawPileCount).
//     The infinity deck and destiny cascade likewise contribute COUNT only.
// A model trained on these records can only ever use information a real player at
// that seat legally had.

import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/player_state.dart';
import 'package:simple_card_game/services/game_service.dart';

/// A fully-built decision record ready to hand to `StatsStore.recordDecision`.
/// Null `chosenIndex` means the chosen option could not be located among the
/// captured options (we still record the decision, with chosenIndex = -1).
class DecisionSnapshot {
  DecisionSnapshot({
    required this.decisionType,
    required this.chosenIndex,
    required this.options,
    required this.selfState,
    required this.oppState,
    required this.board,
  });

  final String decisionType;
  final int chosenIndex;
  final List<Map<String, dynamic>> options;
  final Map<String, dynamic> selfState;
  final List<Map<String, dynamic>> oppState;
  final Map<String, dynamic> board;
}

/// Compact card features used in option lists (the action-space encoding). Only
/// public/visible-to-the-actor properties — these come from cards the actor can
/// legally see (center row, their own hand, destiny row, their own relics).
Map<String, dynamic> cardFeatures(CardModel c) => {
      'id': c.id,
      'name': c.name,
      'faction': c.faction.name,
      'cost': c.cost,
      'type': c.cardType.name,
      'shield': c.shield,
      'hasActivatedAbility': c.activatedAbility != null,
    };

/// Map an action `type` to a decisionType, or null when the action is not a
/// modelled CHOICE (e.g. endTurn, undo, playAllCards, focus — no option set).
String? decisionTypeFor(String actionType) {
  switch (actionType) {
    case 'buyCard':
    case 'recruitFromCenter':
      return 'recruit';
    case 'playCard':
      return 'play';
    case 'claimDestiny':
      return 'claimDestiny';
    case 'recruitRelic':
      return 'recruitRelic';
    case 'attackPlayer':
      return 'attackTarget';
    case 'attackChampion':
    case 'destroyChampion':
      return 'destroyTarget';
    case 'banishCard':
      return 'banishTarget';
    case 'returnFromDiscard':
      return 'returnTarget';
    default:
      return null;
  }
}

/// Build the actor's own legal-state feature map (design §4b `self`). All fields
/// are from the actor's information set; deckSize/discardSize are SIZES only (no
/// order), and the hand cards are the actor's OWN (legal to them).
Map<String, dynamic> selfStateOf(PlayerState p) => {
      'health': p.health,
      'mastery': p.mastery,
      'gems': p.gemPool,
      'power': p.powerPool,
      'handSize': p.hand.length,
      'deckSize': p.drawPile.length,
      'discardSize': p.discardPile.length,
      'championsInPlay': [for (final c in p.championsInPlay) c.id],
      'claimedDestinies': [for (final c in p.claimedDestinies) c.id],
      'relicRecruited': p.relicRecruited,
      // The actor's own hand is known to them — legal to record.
      'handCardIds': [for (final c in p.hand) c.id],
    };

/// Per-opponent PUBLIC state (design §4b `opponents`). CRUCIAL: hand is a COUNT
/// only (`handCount`) — never the opponent's hand card ids; deck/discard are
/// SIZES only. This is the exact redaction boundary from views.dart.
List<Map<String, dynamic>> oppStateOf(GameService game, String actorSeatId) => [
      for (final p in game.players)
        if (p.id != actorSeatId)
          {
            'id': p.id,
            'health': p.health,
            'mastery': p.mastery,
            'championsInPlay': [for (final c in p.championsInPlay) c.id],
            'handCount': p.hand.length, // COUNT ONLY — hidden-info safe.
            'discardSize': p.discardPile.length,
            'eliminated': p.isEliminated,
          },
    ];

/// Shared-supply board features (design §4b `board`). Counts only for hidden
/// piles (infinity deck, destiny cascade); face-up rows are public ids.
Map<String, dynamic> boardOf(GameService game) => {
      'centerRowCardIds': [for (final c in game.centerRow) c.id],
      'destinyRowCardIds': [for (final c in game.destinyRow) c.id],
      'infinityDeckCount': game.infinityDeck.length,
      'destinyDeckCount': game.destinyDeck.length,
      'turn': game.turnNumber,
    };

/// Build a decision snapshot for [actionType] taken by the player seated at
/// [actorSeatId], or null when the action is not a modelled choice. Captured
/// BEFORE the action is applied, from the actor's legal information set.
DecisionSnapshot? buildDecisionSnapshot({
  required GameService game,
  required String actorSeatId,
  required String actionType,
  required Map<String, dynamic> action,
}) {
  final decisionType = decisionTypeFor(actionType);
  if (decisionType == null) return null;

  final actor = game.players.firstWhere((p) => p.id == actorSeatId);
  final self = selfStateOf(actor);
  final opps = oppStateOf(game, actorSeatId);
  final board = boardOf(game);

  String s(String k) => action[k] as String? ?? '';

  List<Map<String, dynamic>> options;
  int chosenIndex;

  switch (decisionType) {
    case 'recruit':
      // Options = every center-row card (with affordability + conditionsMet) PLUS
      // an implicit "pass" (buy nothing). chosenIndex = the bought card's slot.
      final chosenId = s('cardId');
      options = [
        for (final c in game.centerRow)
          {
            ...cardFeatures(c),
            'affordable': actor.gemPool >= c.cost,
            'conditionsMet': game.conditionsSatisfied(c),
          },
      ];
      final passIndex = options.length;
      options.add({'id': '__pass__', 'name': 'pass', 'pass': true});
      chosenIndex =
          game.centerRow.indexWhere((c) => c.id == chosenId);
      if (chosenIndex < 0) chosenIndex = passIndex; // shouldn't happen on accept
      break;

    case 'play':
      // Options = the actor's OWN hand (legal to them) + features + conditionsMet.
      final chosenId = s('cardId');
      options = [
        for (final c in actor.hand)
          {
            ...cardFeatures(c),
            'conditionsMet': game.conditionsSatisfied(c),
          },
      ];
      chosenIndex = actor.hand.indexWhere((c) => c.id == chosenId);
      break;

    case 'claimDestiny':
      final chosenId = s('cardId');
      options = [for (final c in game.destinyRow) cardFeatures(c)];
      chosenIndex = game.destinyRow.indexWhere((c) => c.id == chosenId);
      break;

    case 'recruitRelic':
      // The 2 set-aside relic options are the actor's OWN private choice.
      final chosenId = s('cardId');
      options = [for (final c in actor.relicOptions) cardFeatures(c)];
      chosenIndex = actor.relicOptions.indexWhere((c) => c.id == chosenId);
      break;

    case 'attackTarget':
      // Legal targets = living opponents (public health/mastery only).
      final chosenId = s('targetId');
      options = [
        for (final p in game.players)
          if (p.id != actorSeatId && !p.isEliminated)
            {'id': p.id, 'kind': 'player', 'health': p.health},
      ];
      chosenIndex = options.indexWhere((o) => o['id'] == chosenId);
      break;

    case 'destroyTarget':
      // Legal targets = opponents' champions in play (public). Both
      // attackChampion and destroyChampion carry the target in `championId`.
      final chosenChampId = s('championId');
      options = [
        for (final p in game.players)
          if (p.id != actorSeatId)
            for (final c in p.championsInPlay)
              {
                ...cardFeatures(c),
                'ownerId': p.id,
                'hasGuard': c.hasGuard,
              },
      ];
      chosenIndex = options.indexWhere((o) => o['id'] == chosenChampId);
      break;

    case 'banishTarget':
      // Banish a card from the actor's OWN hand or discard (both legal to them).
      final chosenId = s('cardId');
      options = [
        for (final c in actor.hand)
          {...cardFeatures(c), 'zone': 'hand'},
        for (final c in actor.discardPile)
          {...cardFeatures(c), 'zone': 'discard'},
      ];
      chosenIndex = options.indexWhere((o) => o['id'] == chosenId);
      break;

    case 'returnTarget':
      // Return a card from the actor's OWN discard (legal to them).
      final chosenId = s('cardId');
      options = [for (final c in actor.discardPile) cardFeatures(c)];
      chosenIndex = options.indexWhere((o) => o['id'] == chosenId);
      break;

    default:
      return null;
  }

  return DecisionSnapshot(
    decisionType: decisionType,
    chosenIndex: chosenIndex,
    options: options,
    selfState: self,
    oppState: opps,
    board: board,
  );
}

/// Classify HOW a finished game was won, for the `games.winType` column. The
/// engine records the precise path on `GameService.winType` ('mastery' via the
/// Infinity-Shard win at mastery 30, or 'elimination'), set at the win site — so
/// we read it directly rather than guessing from the winner's mastery (which can
/// be >= 30 on an elimination win in a long game). 'none' for a drawn/abandoned
/// game with no winner.
String winTypeOf(GameService game) {
  if (game.winnerId == null) return 'none';
  return game.winType ?? 'elimination';
}

/// Resolve the [CardModel] an action refers to, searching the zones the actor
/// could legally act on (hand / center row / destiny row / their own champions /
/// discard / relic options). Used to denormalize name/faction/cost onto the
/// compact OUTCOME event. Returns null if no card id is involved or not found.
CardModel? resolveActionCard({
  required GameService game,
  required PlayerState actor,
  required Map<String, dynamic> action,
}) {
  final cardId = (action['cardId'] as String?) ??
      (action['championId'] as String?);
  if (cardId == null || cardId.isEmpty) return null;
  final pools = <List<CardModel>>[
    actor.hand,
    game.centerRow,
    game.destinyRow,
    actor.championsInPlay,
    actor.discardPile,
    actor.relicOptions,
    actor.claimedDestinies,
  ];
  for (final pool in pools) {
    for (final c in pool) {
      if (c.id == cardId) return c;
    }
  }
  // Enemy champions (for destroy/attack-champion targets).
  for (final p in game.players) {
    for (final c in p.championsInPlay) {
      if (c.id == cardId) return c;
    }
  }
  return null;
}
