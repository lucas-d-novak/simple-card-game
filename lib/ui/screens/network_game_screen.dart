import 'package:flutter/material.dart';
import 'package:simple_card_game/data/database/card_serialization.dart';
import 'package:simple_card_game/models/card_effect.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/services/fullscreen.dart';
import 'package:simple_card_game/services/game_client.dart';
import 'package:simple_card_game/services/redacted_condition_evaluator.dart';
import 'package:simple_card_game/ui/theme/board_chrome.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';
import 'package:simple_card_game/ui/widgets/action_playback_overlay.dart';
import 'package:simple_card_game/ui/widgets/animated_value.dart';
import 'package:simple_card_game/ui/widgets/animated_zone.dart';
import 'package:simple_card_game/ui/widgets/beveled_button.dart';
import 'package:simple_card_game/ui/widgets/board_animator.dart';
import 'package:simple_card_game/ui/widgets/card_detail_modal.dart';
import 'package:simple_card_game/ui/widgets/card_fan.dart';
import 'package:simple_card_game/ui/widgets/choice_modal.dart';
import 'package:simple_card_game/ui/widgets/destiny_tray.dart';
import 'package:simple_card_game/ui/widgets/faction_flame_backdrop.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';
import 'package:simple_card_game/ui/widgets/resource_grant.dart';
import 'package:simple_card_game/ui/widgets/resource_icons.dart';
import 'package:simple_card_game/ui/widgets/scrollable_board.dart';
import 'package:simple_card_game/ui/widgets/shard_win_overlay.dart';

/// Networked game view — renders the server's REDACTED state for this player
/// with the SAME polished board chrome as the local [GameScreen], and sends
/// actions over the [GameClient].
///
/// The engine never runs on the client for networked games: this widget is a
/// presentation layer over the authoritative redacted view. Each VISIBLE card
/// arrives fully serialized (name + effects + stats) in the state's `cards`
/// dictionary, so the board renders EXACTLY the cards the engine created — the
/// same content the local [GameScreen] shows. There is no client-side catalog
/// guessing. Hidden information is honoured structurally: opponents' hands and
/// all draw piles are never dictionaried, so their card identities are simply
/// not present to render.
class NetworkGameScreen extends StatefulWidget {
  const NetworkGameScreen({super.key, required this.client});

  final GameClient client;

  @override
  State<NetworkGameScreen> createState() => _NetworkGameScreenState();
}

class _NetworkGameScreenState extends State<NetworkGameScreen> {
  String? _actionMessage;

  /// True once the Infinity-Shard mastery-win flourish has been shown (or
  /// skipped) this game, so the board advances to the networked game-over screen.
  bool _shardWinShown = false;

  /// Rehydrated card models from the latest state's `cards` dictionary, by id.
  Map<String, CardModel> _cards = const {};

  /// A deferred target-selection prompt queued by a card we just played. It runs
  /// on the NEXT server state (not synchronously after [GameClient.playCard],
  /// which only sends a message) so the picker reads the POST-play state — e.g.
  /// the just-played card is already out of hand, opponents' champions reflect
  /// the play, etc. Cleared once fired.
  VoidCallback? _pendingSelection;

  // ---- Fly-animation anchors (see board_animator.dart) ----------------------
  final GlobalKey _gemAnchorKey = GlobalKey(debugLabel: 'netGemAnchor');
  final GlobalKey _powerAnchorKey = GlobalKey(debugLabel: 'netPowerAnchor');
  final GlobalKey _masteryAnchorKey = GlobalKey(debugLabel: 'netMasteryAnchor');
  final GlobalKey _deckAnchorKey = GlobalKey(debugLabel: 'netDeckAnchor');
  final GlobalKey _discardAnchorKey = GlobalKey(debugLabel: 'netDiscardAnchor');
  final GlobalKey _centerRowKey = GlobalKey(debugLabel: 'netCenterRow');
  final GlobalKey _playAreaKey = GlobalKey(debugLabel: 'netPlayArea');

  /// The [GlobalKey] anchor for a resource counter (where its pips fly TO).
  GlobalKey? _counterKeyFor(ResourceIcon icon) {
    switch (icon) {
      case ResourceIcon.gem:
        return _gemAnchorKey;
      case ResourceIcon.power:
        return _powerAnchorKey;
      case ResourceIcon.mastery:
        return _masteryAnchorKey;
      case ResourceIcon.health:
        return _masteryAnchorKey;
      case ResourceIcon.shield:
        return null;
    }
  }

  /// Fly resource-gain pips from [fromKey] to the matching counters for every
  /// simple resource grant on [card]. No-op in instant mode.
  void _flyResourceGains(CardModel card, GlobalKey fromKey) {
    final animator = BoardAnimator.of(context);
    if (animator.isNoop) return;
    for (final grant in resourceGrantsOf(card.playEffects)) {
      final toKey = _counterKeyFor(grant.icon);
      if (toKey == null) continue;
      animator.flyResource(
        fromKey: fromKey,
        toKey: toKey,
        icon: grant.icon,
        count: grant.count,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onChanged);
    _syncCards();
  }

  @override
  void dispose() {
    widget.client.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _syncCards();
    // Fire any deferred selection now that the post-play state has arrived.
    final pending = _pendingSelection;
    if (pending != null) {
      _pendingSelection = null;
      // Schedule after this frame so the modal opens over the updated board.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) pending();
      });
    }
    if (mounted) setState(() {});
  }

  /// Rebuild the id → CardModel map from the latest redacted state.
  void _syncCards() {
    final dict = widget.client.gameState?['cards'];
    if (dict is Map) {
      _cards = {
        for (final entry in dict.entries)
          entry.key as String:
              cardModelFromJson((entry.value as Map).cast<String, dynamic>()),
      };
    }
  }

  void _flash(String msg) {
    setState(() => _actionMessage = msg);
  }

  // ---- card reconstruction ------------------------------------------------

  /// Resolve a card id to its server-provided [CardModel]. Returns a minimal
  /// placeholder only if the id is somehow absent from the dictionary (e.g. a
  /// face-down / hidden card we should never be asked to render).
  CardModel _card(String id) {
    return _cards[id] ??
        CardModel(id: id, name: '', cost: 0, playEffects: const []);
  }

  /// The player's dominant faction across every card they own (draw pile + hand
  /// + discard + played + champions). Starter/neutral cards (Faction.none) are
  /// ignored so they don't outweigh a real faction lean. Ties break by a fixed
  /// faction order for stability. Returns [Faction.none] when the player owns no
  /// faction cards yet (all starters) — a neutral grey flame.
  Faction _dominantFaction(_PlayerView p) {
    final counts = <Faction, int>{};
    void tally(String id) {
      final f = _card(id).faction;
      if (f == Faction.none) return;
      counts[f] = (counts[f] ?? 0) + 1;
    }

    for (final id in p.drawPileContents) {
      tally(id);
    }
    for (final id in p.hand) {
      tally(id);
    }
    for (final id in p.discard) {
      tally(id);
    }
    for (final id in p.playedThisTurn) {
      tally(id);
    }
    for (final c in p.champions) {
      tally(c.id);
    }

    if (counts.isEmpty) return Faction.none;
    // Stable tie-break: highest count, then a fixed faction ordering.
    const order = [
      Faction.homodeus,
      Faction.wraethe,
      Faction.order,
      Faction.undergrowth,
    ];
    Faction best = Faction.none;
    int bestCount = -1;
    for (final f in order) {
      final c = counts[f] ?? 0;
      if (c > bestCount) {
        bestCount = c;
        best = f;
      }
    }
    return best;
  }

  /// Build the playback entries for the action-ticker overlay from the current
  /// action-log tail. Each entry is "<actor> <message>" plus the involved card
  /// (resolved from the `cards` dict) when the log entry carries a public
  /// `cardId`. Card-less events (focus / turn change / direct attack / end turn)
  /// have no cardId and show text only.
  List<PlaybackEntry> _playbackEntries(_GameView view) {
    return [
      for (final e in view.actionLog)
        () {
          final who = view.nameFor(e['playerId'] as String?);
          final msg = e['message'] as String? ?? '';
          final line = who.isEmpty ? msg : '$who $msg';
          final cardId = e['cardId'] as String?;
          // Only attach a mini card when the id resolves to a real, dictionaried
          // (public) card — a missing id renders as text only.
          final card =
              (cardId != null && _cards.containsKey(cardId)) ? _card(cardId) : null;
          return PlaybackEntry(message: line, card: card);
        }(),
    ];
  }

  // ---- actions ------------------------------------------------------------

  /// Play a hand card (reached by dropping it on the play-area DragTarget, or
  /// via the zoom modal's "Play" action).
  ///
  /// Cards carrying a [ChooseOneEffect] in their (server-serialized) play
  /// effects prompt the shared choice modal FIRST, then send the chosen index
  /// to the server. Without this, an online X/Y card would silently resolve as
  /// choiceIndex 0. The "Play All" path can't prompt per-card, so it always
  /// uses the default — only this single-card path prompts.
  void _playHandCard(CardModel card) {
    final choose = card.playEffects.whereType<ChooseOneEffect>().firstOrNull;
    if (choose != null) {
      showChoiceModal(
        context,
        title: card.name,
        subtitle: 'Choose an effect',
        options: [
          for (final group in choose.choices)
            ChoiceOption(label: group.map((e) => e.description).join(' and ')),
        ],
      ).then((index) {
        if (index == null) return;
        widget.client.playCard(card.id, choiceIndex: index);
        _flash('Played ${card.name}');
      });
      return;
    }
    widget.client.playCard(card.id);
    _flash('Played ${card.name}');
    _animatePlay(card);
    // Queue any target picker to run on the NEXT server state (after the play
    // is reflected), not synchronously — playCard only sent a message.
    _queuePostPlayEffects(card);
  }

  /// Telegraph a hand-card play: fly resource pips from the play area (where the
  /// card lands) to their counters. No-op under instant / reduced motion.
  void _animatePlay(CardModel card) {
    final animator = BoardAnimator.of(context);
    if (animator.isNoop) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _flyResourceGains(card, _playAreaKey);
    });
  }

  // ---- deferred-selection target pickers ----------------------------------
  // Several effects resolve to a no-op at play time and expose a follow-up the
  // UI calls AFTER the player picks a target (mirrors the local board's
  // game_screen.dart pickers). When a just-played card carries one of these, we
  // prompt with a choice modal and send the matching action. Candidates are read
  // from the LATEST redacted view at prompt time (own hand/discard, center row,
  // opponent champions) — all hidden-info-safe, since the server still validates.

  /// Queue a target picker for the FIRST deferred effect a just-played card
  /// carries (banish / scrap / destroy-champion / return-from-discard). The
  /// picker runs on the next server state via [_pendingSelection] so it reads
  /// the POST-play board (the played card already gone from hand, etc.).
  void _queuePostPlayEffects(CardModel card) =>
      _queueDeferredSelection(card, card.playEffects);

  /// Queue a deferred target picker for the first deferred effect in [effects]
  /// (a card's playEffects, or a champion's activated-ability effects), with
  /// [source] as the effect's source card for condition evaluation.
  void _queueDeferredSelection(CardModel source, List<CardEffect> effects) {
    // Evaluate conditions against the POST-action state (the played card is now
    // in playedThisTurn / championsInPlay), mirroring what the engine saw.
    final me = _view?.me;
    final ctx = me != null ? _conditionContext(me) : null;
    final picker = _deferredPickerFor(effects, source, ctx);
    if (picker != null) _pendingSelection = picker;
  }

  /// Walks a list of effects (recursing into `ConditionalEffect.then` and
  /// `ChooseOneEffect.choices`) and returns the target picker for the FIRST
  /// deferred effect found, or null if none. Nesting matters: cards like Limiter
  /// Drones carry their banish INSIDE a `ConditionalEffect` (Inspire — "if you
  /// control a Champion, you may banish…"), so a flat top-level scan would miss
  /// it and the banish prompt would silently never appear.
  ///
  /// A `ConditionalEffect` is only recursed into when its condition HOLDS — the
  /// server's banish/destroy/etc. actions are unconditional, so prompting when
  /// the condition failed would let the player take an effect they didn't earn.
  /// Conditions the redacted state can't evaluate are treated as NOT holding
  /// (conservative: no spurious prompt).
  VoidCallback? _deferredPickerFor(
    List<CardEffect> effects,
    CardModel source,
    RedactedConditionContext? ctx,
  ) {
    for (final effect in effects) {
      switch (effect) {
        case BanishCardEffect():
          return () => _promptBanish(effect.source);
        case ScrapFromCenterRowEffect():
          return _promptScrap;
        case DestroyChampionEffect() when !effect.all:
          return _promptDestroyChampion;
        case ReturnFromDiscardEffect():
          return _promptReturnFromDiscard;
        case ConditionalEffect():
          final holds = ctx != null &&
              redactedConditionHolds(effect.condition, source, ctx);
          if (!holds) break;
          final nested = _deferredPickerFor(effect.then, source, ctx);
          if (nested != null) return nested;
        case ChooseOneEffect():
          for (final group in effect.choices) {
            final nested = _deferredPickerFor(group, source, ctx);
            if (nested != null) return nested;
          }
        default:
          break;
      }
    }
    return null;
  }

  /// The latest typed view, or null when no state has arrived yet.
  _GameView? get _view {
    final st = widget.client.gameState;
    if (st == null) return null;
    return _GameView.parse(st, widget.client.playerId);
  }

  /// Mastery a player must reach to claim a Destiny (mirrors
  /// GameService.destinyClaimMastery = 5).
  static const int _destinyClaimMastery = 5;

  /// Mastery a player must reach to recruit a Relic (mirrors the engine's
  /// recruitRelic threshold = 10).
  static const int _relicRecruitMastery = 10;

  /// Whether [me] may claim a Destiny right now: it is their turn, they are at
  /// the threshold, still under the per-game claim allowance, and the row is
  /// non-empty. Mirrors the engine gate; the server re-validates on send.
  bool _canClaimDestiny(_GameView view, _PlayerView me) =>
      widget.client.isMyTurn &&
      me.mastery >= _destinyClaimMastery &&
      me.canClaimAnotherDestiny &&
      view.destinyRow.isNotEmpty;

  /// Whether [me] may recruit a Relic right now: it is their turn, they are at
  /// Mastery 10, have not yet recruited, and their two relic options are present.
  bool _canRecruitRelic(_PlayerView me) =>
      widget.client.isMyTurn &&
      me.mastery >= _relicRecruitMastery &&
      !me.relicRecruited &&
      me.relicOptions.isNotEmpty;

  /// Prompt to banish one of the player's hand/discard cards, then send the
  /// follow-up with the engine BanishSource name.
  void _promptBanish(BanishSource source) {
    final me = _view?.me;
    if (me == null) return;
    final candidates = <_TargetCandidate>[];
    if (source == BanishSource.hand || source == BanishSource.handOrDiscard) {
      for (final id in me.hand) {
        candidates.add(_TargetCandidate(_card(id), 'Hand'));
      }
    }
    if (source == BanishSource.discard ||
        source == BanishSource.handOrDiscard) {
      for (final id in me.discard) {
        candidates.add(_TargetCandidate(_card(id), 'Discard'));
      }
    }
    // playedThisTurn-sourced banishes target this turn's plays.
    if (source == BanishSource.playedThisTurn) {
      for (final id in me.playedThisTurn) {
        candidates.add(_TargetCandidate(_card(id), 'Played'));
      }
    }
    _promptTargets(
      title: 'Banish a Card',
      subtitle: 'Remove one from the game',
      candidates: candidates,
      emptyMsg: 'No cards to banish',
      onPick: (t) {
        widget.client.banishCard(t.id, source.name);
        _flash('Banished ${t.card.name}');
      },
    );
  }

  /// Prompt to scrap one center-row card, then send the follow-up.
  void _promptScrap() {
    final view = _view;
    if (view == null) return;
    final candidates = [
      for (final id in view.centerRow) _TargetCandidate(_card(id), 'Center row'),
    ];
    _promptTargets(
      title: 'Scrap from Center Row',
      subtitle: 'Remove one market card from the game',
      candidates: candidates,
      emptyMsg: 'No cards to scrap',
      onPick: (t) {
        widget.client.scrapFromCenterRow(t.id);
        _flash('Scrapped ${t.card.name}');
      },
    );
  }

  /// Prompt to destroy one enemy champion, then send the follow-up (championId +
  /// the owning opponent's id, as the engine requires).
  void _promptDestroyChampion() {
    final view = _view;
    if (view == null) return;
    final candidates = <_TargetCandidate>[];
    for (final p in view.players) {
      if (p.id == view.meId || p.eliminated) continue;
      for (final champ in p.champions) {
        // Owner carried on the candidate (ids repeat across opponents).
        candidates.add(_TargetCandidate(_card(champ.id), p.name, ownerId: p.id));
      }
    }
    _promptTargets(
      title: 'Destroy a Champion',
      subtitle: 'Destroy a target enemy champion',
      candidates: candidates,
      emptyMsg: 'No enemy champions to destroy',
      onPick: (t) {
        widget.client.destroyChampion(t.id, t.ownerId ?? '');
        _flash('Destroyed ${t.card.name}');
      },
    );
  }

  /// Prompt to return one card from the player's own discard pile to hand, then
  /// send the follow-up. The server validates the effect's filter.
  void _promptReturnFromDiscard() {
    final me = _view?.me;
    if (me == null) return;
    final candidates = [
      for (final id in me.discard) _TargetCandidate(_card(id), 'Discard'),
    ];
    _promptTargets(
      title: 'Return a Card',
      subtitle: 'Return one from your discard pile to hand',
      candidates: candidates,
      emptyMsg: 'Your discard pile is empty',
      onPick: (t) {
        widget.client.returnFromDiscard(t.id);
        _flash('Returned ${t.card.name}');
      },
    );
  }

  /// Shared target-picker: shows [candidates] as card previews in the choice
  /// modal and invokes [onPick] with the chosen card. No-ops (with an info
  /// flash) when there are no candidates.
  void _promptTargets({
    required String title,
    required String subtitle,
    required List<_TargetCandidate> candidates,
    required String emptyMsg,
    required void Function(_TargetCandidate candidate) onPick,
  }) {
    if (candidates.isEmpty) {
      _flash(emptyMsg);
      return;
    }
    showChoiceModal(
      context,
      title: title,
      subtitle: subtitle,
      options: [
        for (final t in candidates)
          ChoiceOption(
            label: t.card.name.isEmpty ? t.card.id : t.card.name,
            detail: t.zone,
            cardPreview: GameCardWidget(card: t.card, width: 130),
          ),
      ],
    ).then((index) {
      if (index == null) return;
      onPick(candidates[index]);
    });
  }

  // ---- Destiny / Relic ----------------------------------------------------

  /// Open the shared choice modal over the face-up Destiny row; the chosen
  /// Destiny is claimed via [GameClient.claimDestiny]. Eligibility is gated by
  /// the caller ([_canClaimDestiny]); the server re-validates.
  void _openDestinyModal(_GameView view) {
    final rowIds = view.destinyRow;
    if (rowIds.isEmpty) return;
    final cards = [for (final id in rowIds) _card(id)];
    showChoiceModal(
      context,
      title: 'Claim a Destiny',
      subtitle: 'Mastery 5+ — claim one for free',
      options: [
        for (final c in cards)
          ChoiceOption(
            label: c.name.isEmpty ? c.id : c.name,
            cardPreview: GameCardWidget(card: c, width: 150),
          ),
      ],
    ).then((index) {
      if (index == null) return;
      final chosen = cards[index];
      widget.client.claimDestiny(chosen.id);
      _flash('Claimed ${chosen.name}');
    });
  }

  /// Open the shared choice modal over the player's two set-aside Relic options;
  /// the chosen Relic is recruited via [GameClient.recruitRelic] (the other is
  /// banished server-side). Gated by [_canRecruitRelic].
  void _openRelicModal(_PlayerView me) {
    final optionIds = me.relicOptions;
    if (optionIds.isEmpty) return;
    final cards = [for (final id in optionIds) _card(id)];
    showChoiceModal(
      context,
      title: 'Recruit a Relic',
      subtitle: 'Mastery 10 — keep one, banish the other',
      options: [
        for (final c in cards)
          ChoiceOption(
            label: c.name.isEmpty ? c.id : c.name,
            cardPreview: GameCardWidget(card: c, width: 150),
          ),
      ],
    ).then((index) {
      if (index == null) return;
      final chosen = cards[index];
      widget.client.recruitRelic(chosen.id);
      _flash('Recruited ${chosen.name}');
    });
  }

  /// A hand-card drag has begun (long-press) — hint where to drop it.
  void _onHandDragStarted(CardModel card) {
    _flash('Drop ${card.name} on the play area');
  }

  void _onCenterTap(CardModel card) {
    final animator = BoardAnimator.of(context);
    final factionColor = FactionColors.getPrimary(card.faction);
    widget.client.buyCard(card.id);
    _flash('Recruiting ${card.name}…');
    if (!animator.isNoop) {
      // Recruited card flies from the market to the discard pile, and a fresh
      // card flies from the deck into the freed market slot (refill).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        animator.flyCard(
          fromKey: _centerRowKey,
          toKey: _discardAnchorKey,
          factionColor: factionColor,
          endScale: 0.5,
        );
        animator.flyCard(
          fromKey: _deckAnchorKey,
          toKey: _centerRowKey,
          factionColor: GameTheme.gold,
          endScale: 1.0,
        );
      });
    }
  }

  void _onFastPlayMercenary(CardModel card) {
    widget.client.fastPlayMercenary(card.id);
    _flash('Fast-playing ${card.name}…');
  }

  /// Open the market card-detail popup for [card] (SELECT it). Offers Recruit
  /// (buy → discard) and, for Mercenaries only, Fast Play (pay + play now, then
  /// removed). Reached by TAPPING a market card; dragging a card to the play
  /// field recruits it directly instead.
  void _openMarketDetail(List<CardModel> centerCards, CardModel card) {
    final myTurn = widget.client.isMyTurn;
    final gems = _view?.me.gemPool ?? 0;
    final i = centerCards.indexWhere((x) => x.id == card.id);
    _zoom(
      centerCards,
      i < 0 ? 0 : i,
      actionFor: (c) => CardDetailAction(
        label: 'Recruit',
        enabled: myTurn && gems >= c.cost,
        onPressed: () => _onCenterTap(c),
      ),
      secondaryActionFor: (c) {
        if (c.cardType != CardType.mercenary) return null;
        return CardDetailAction(
          label: 'Fast Play',
          enabled: myTurn && gems >= c.cost,
          onPressed: () => _onFastPlayMercenary(c),
        );
      },
    );
  }

  void _onMyChampionTap(CardModel champ) {
    widget.client.activateChampion(champ.id);
    _flash('Activated ${champ.name}');
    // Activating a champion re-resolves its play effects, which may include a
    // deferred target picker (banish / return / destroy) — queue it too.
    _queueDeferredSelection(champ, champ.playEffects);
  }

  void _onExhaustChampion(CardModel champ) {
    widget.client.useActivatedAbility(champ.id);
    _flash('Exhausted ${champ.name}');
    // The Exhaust ability's effects can be deferred-selection (e.g. Aedifex's
    // "Put a Champion from your discard pile into your hand" =
    // returnFromDiscard, which needs a card pick). Queue that picker; without it
    // the Exhaust silently does nothing.
    final ability = champ.activatedAbility;
    if (ability != null) _queueDeferredSelection(champ, ability.effects);
  }

  /// "Exhaust All" — the champion-side equivalent of Play All. Fires the Exhaust
  /// ability of every champion that HAS one and isn't already exhausted, in
  /// board order. Abilities with no target resolve immediately; the FIRST one
  /// that needs a target selection queues its picker (the pending-selection slot
  /// holds one at a time — the player can re-tap remaining champions after).
  void _onExhaustAll(_GameView view) {
    final me = view.me;
    var fired = 0;
    for (final champ in me.champions) {
      if (champ.exhausted) continue;
      final card = _card(champ.id);
      final ability = card.activatedAbility;
      if (ability == null) continue;
      widget.client.useActivatedAbility(champ.id);
      fired++;
      // Queue the deferred picker only for the first ability that needs one, so
      // multiple target prompts don't overwrite each other's pending slot.
      if (_pendingSelection == null) {
        _queueDeferredSelection(card, ability.effects);
      }
    }
    if (fired > 0) _flash('Exhausted $fired champion${fired == 1 ? '' : 's'}');
  }

  /// Count of my champions that can still be Exhausted this turn (have an
  /// activated ability and aren't exhausted) — drives the button's Exhaust phase.
  int _exhaustableCount(_GameView view) {
    var n = 0;
    for (final champ in view.me.champions) {
      if (!champ.exhausted && _card(champ.id).activatedAbility != null) n++;
    }
    return n;
  }

  /// Open the zoom modal for one of MY champions, offering its two distinct
  /// actions: "Activate" (free, re-resolves play effects, once/turn) and —
  /// only when the card has an Exhaust-gated [CardModel.activatedAbility] —
  /// "Exhaust" (disabled once the champion is exhausted). Only enabled on your
  /// turn.
  void _zoomMyChampion(List<_ChampionView> champs, _ChampionView champ) {
    final cards = [for (final c in champs) _card(c.id)];
    final byId = {for (final c in champs) c.id: c};
    final index = champs.indexWhere((c) => c.id == champ.id);
    final myTurn = widget.client.isMyTurn;
    _zoom(
      cards,
      index < 0 ? 0 : index,
      actionFor: (card) {
        // "Activate" re-resolves the champion's PLAY effects (a free once-per-
        // turn re-trigger). A champion with no play effects (e.g. Aedifex, whose
        // only ability is Exhaust-gated) has nothing to Activate — hide it so the
        // modal shows just the Exhaust action, not a useless button.
        if (card.playEffects.isEmpty) return null;
        final view = byId[card.id];
        return CardDetailAction(
          label: 'Activate',
          enabled: myTurn && (view == null || !view.activated),
          onPressed: () => _onMyChampionTap(card),
        );
      },
      secondaryActionFor: (card) {
        if (card.activatedAbility == null) return null;
        final view = byId[card.id];
        return CardDetailAction(
          label: 'Exhaust',
          enabled: myTurn && (view == null || !view.exhausted),
          onPressed: () => _onExhaustChampion(card),
        );
      },
    );
  }

  void _onOpponentChampionTap(CardModel champ, String ownerId) {
    widget.client.attackChampion(champ.id, ownerId);
    _flash('Attacking ${champ.name}');
  }

  void _onAttackPlayer(_PlayerView opponent, int power) {
    widget.client.attackPlayer(opponent.id, power);
    _flash('Dealt $power to ${opponent.name}');
  }

  void _onFocus() {
    final animator = BoardAnimator.of(context);
    widget.client.focus();
    _flash('Focus: spent 1 gem → +1 mastery');
    if (!animator.isNoop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        animator.flyResource(
          fromKey: _gemAnchorKey,
          toKey: _masteryAnchorKey,
          icon: ResourceIcon.mastery,
        );
      });
    }
  }

  /// Build the redacted condition context for [me] (the recipient's own slice),
  /// so the client-side evaluator can compute the yellow "bonus active" glow.
  RedactedConditionContext _conditionContext(_PlayerView me) {
    return RedactedConditionContext(
      cards: _cards,
      handIds: me.hand,
      playedThisTurnIds: me.playedThisTurn,
      discardIds: me.discard,
      championIds: [for (final c in me.champions) c.id],
      mastery: me.mastery,
      unblockedDamageThisTurn: me.unblockedDamageThisTurn,
    );
  }

  // ---- Destinies tray -----------------------------------------------------

  /// Open the Destinies tray over the recipient's claimed Destinies. Each row's
  /// Use action sends `useDestinyAbility`; greying mirrors the redacted
  /// exhausted set + whose turn it is + the ability's payable cost (we can only
  /// fully validate server-side, but disable obvious non-uses here).
  void _openDestinyTray(_PlayerView me) {
    final myTurn = widget.client.isMyTurn;
    final entries = <DestinyEntry>[];
    for (final id in me.claimedDestinies) {
      final card = _card(id);
      final ability = card.activatedAbility;
      final exhausted = me.exhaustedDestinies.contains(id);
      // Cost-payability check from public scalars (gems / mastery / health).
      var costOk = true;
      if (ability != null) {
        final cost = ability.cost;
        if (me.gemPool < cost.gems) costOk = false;
        if (me.mastery < cost.mastery) costOk = false;
        if (cost.health > 0 && me.health <= cost.health) costOk = false;
      }
      entries.add(DestinyEntry(
        card: card,
        canUse: myTurn && ability != null && !exhausted && costOk,
        exhausted: exhausted,
      ));
    }
    if (entries.isEmpty) return;
    showDestinyTray(
      context,
      entries: entries,
      onUse: (destinyId) {
        widget.client.useDestinyAbility(destinyId);
        _flash('Used Destiny ability');
      },
    );
  }

  // ---- zoomed card detail -------------------------------------------------

  /// Open the official-style zoomed card-detail modal over [cards], starting at
  /// [index], paging through the list with the side arrows. [actionFor] supplies
  /// an optional context action (e.g. Recruit for an affordable market card).
  void _zoom(
    List<CardModel> cards,
    int index, {
    CardDetailAction? Function(CardModel card)? actionFor,
    CardDetailAction? Function(CardModel card)? secondaryActionFor,
  }) {
    if (cards.isEmpty) return;
    showCardDetailModal(
      context,
      cards: cards,
      initialIndex: index.clamp(0, cards.length - 1),
      actionFor: actionFor,
      secondaryActionFor: secondaryActionFor,
    );
  }

  /// Zoom a single card (no paging) — used from the pile viewers.
  void _zoomOne(CardModel card) => _zoom([card], 0);

  // ---- pile viewers -------------------------------------------------------

  /// Show the recipient's discard pile — public info, so full card content.
  void _showDiscard(_PlayerView me) {
    final cards = [for (final id in me.discard) _card(id)];
    _showPileSheet(
      title: 'Your discard pile (${cards.length})',
      cards: cards,
      emptyNote: 'Your discard pile is empty.',
    );
  }

  /// Show the scrollable action log (newest first) so a player can review what
  /// happened — e.g. remind themselves what they did last turn.
  void _showLog(_GameView view) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E2236),
      isScrollControlled: true,
      builder: (ctx) {
        final entries = view.actionLog.reversed.toList(); // newest first
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Game log',
                    style: TextStyle(
                        color: BoardChrome.goldText,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No actions yet.',
                        style: TextStyle(color: Colors.white60)),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.6),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        final turn = e['turn'] as int? ?? 0;
                        final who = view.nameFor(e['playerId'] as String?);
                        final msg = e['message'] as String? ?? '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 34,
                                child: Text('T$turn',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 11)),
                              ),
                              Expanded(
                                child: Text(
                                  who.isEmpty ? msg : '$who $msg',
                                  style: const TextStyle(
                                      color: Color(0xFFE8EEF4),
                                      fontSize: 13,
                                      height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('CLOSE',
                        style: TextStyle(color: Color(0xFF5FD0E6))),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Show what's left in YOUR draw pile — the CONTENTS, sorted alphabetically.
  /// The server sends the contents already sorted (so no draw ORDER leaks; the
  /// anti-scry/shuffle rule is preserved), and we present them A→Z so you can
  /// quickly scan what you still might draw.
  void _showDrawPile(_PlayerView me) {
    final cards = [for (final id in me.drawPileContents) _card(id)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _showPileSheet(
      title: 'Your draw pile (${me.drawPileCount})',
      cards: cards,
      emptyNote: me.drawPileCount == 0
          ? 'Your draw pile is empty.'
          : 'These ${me.drawPileCount} cards are still in your draw pile '
              '(shown A→Z — the draw ORDER stays hidden).',
    );
  }

  void _showPileSheet({
    required String title,
    required List<CardModel> cards,
    required String emptyNote,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E2236),
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: BoardChrome.goldText,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      emptyNote,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 13, height: 1.3),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                    ),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (int i = 0; i < cards.length; i++)
                            GameCardWidget(
                              key: ValueKey('pile_${cards[i].id}'),
                              card: cards[i],
                              width: 96,
                              // Tap a pile card to zoom it (page the whole pile).
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _zoom(cards, i);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('CLOSE',
                        style: TextStyle(color: Color(0xFF5FD0E6))),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final state = client.gameState;

    return Scaffold(
      body: BoardAnimatorScope(
        child: Stack(
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
                        if (view.winType == 'mastery' && !_shardWinShown) {
                          final winner = view.players
                              .where((p) => p.id == view.winnerId)
                              .firstOrNull;
                          return ShardWinOverlay(
                            winnerName: winner?.name ?? 'A player',
                            isLocalWinner: view.winnerId == view.meId,
                            onDone: () =>
                                setState(() => _shardWinShown = true),
                          );
                        }
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
          // Dynamic action-playback ticker: newly-arrived public log entries fade
          // in one at a time near the top so a player can WATCH the opponent's
          // turn unfold. Only while a game is in progress.
          if (state != null && !(_GameView.parse(state, client.playerId).isGameOver))
            Positioned(
              top: 4,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: ActionPlaybackOverlay(
                  entries:
                      _playbackEntries(_GameView.parse(state, client.playerId)),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _board(GameClient client, _GameView view, double screenWidth) {
    final me = view.me;
    final opponent = view.firstOpponent;
    final myTurn = client.isMyTurn;
    // Client-side condition context for the "bonus active now" yellow glow.
    // Only the recipient's own perspective glows (own hand / market cards).
    final condCtx = _conditionContext(me);
    bool conditionsMet(CardModel card) =>
        redactedConditionsSatisfied(card, condCtx);
    // Guard status isn't in the redacted state per champion — resolve each
    // opponent champion id to its card and check the model's hasGuard flag.
    final opponentHasGuard =
        view.opponentChampionIds.any((id) => _card(id).hasGuard);
    final canAttackPlayer =
        myTurn && me.powerPool > 0 && opponent != null && !opponentHasGuard;

    // Hand gestures: tap = zoom (card detail, with a Play action so cards can
    // be played in a deliberate order from the zoomed view); long-press =
    // begin drag-to-play (drop on the play field). Off-turn, Play is hidden.
    void zoomHand(CardModel c) {
      final hand = [for (final id in me.hand) _card(id)];
      final i = hand.indexWhere((x) => x.id == c.id);
      _zoom(
        hand,
        i < 0 ? 0 : i,
        actionFor: myTurn
            ? (card) => CardDetailAction(
                  label: 'Play',
                  onPressed: () => _playHandCard(card),
                )
            : null,
      );
    }

    return ScrollableBoard(
      header: [
        // ---- Top bar: Lobby button + opponent pill + turn banner ----------
        _NetworkTopBar(
          opponent: opponent,
          myTurn: myTurn,
          // Pop back to the lobby WITHOUT disconnecting, so the player can
          // switch to another of their games. The socket stays open; the lobby
          // listens to the same client and its Rejoin re-enters this game.
          onBackToLobby: () => Navigator.of(context).maybePop(),
          onShowLog: () => _showLog(view),
        ),

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
        // Gesture model: TAP a card → SELECT it (open the detail popup with
        // Recruit, plus Fast Play for mercenaries). DRAG a card into the play
        // field → recruit it (mirrors drag-from-hand = play). See the popup
        // wiring below and the market DragTarget on the play field.
        Builder(builder: (context) {
          final centerCards = [for (final id in view.centerRow) _card(id)];
          return KeyedSubtree(
            key: _centerRowKey,
            child: _NetworkCenterRow(
              cards: centerCards,
              canAfford: (c) => myTurn && me.gemPool >= c.cost,
              onTapCard: (c) => _openMarketDetail(centerCards, c),
              onLongPressCard: (c) => _openMarketDetail(centerCards, c),
              // Long-press begins a drag; dropping on the play field recruits it.
              onDragStarted: myTurn ? (_) {} : null,
              conditionsMet: conditionsMet,
              screenWidth: screenWidth,
            ),
          );
        }),
      ],

      // ---- Play field ----------------------------------------------------
      // Two overlaid DragTargets with DISTINCT payload types so drops never
      // cross-fire:
      //   * outer DragTarget<_MarketCardDrag> — a MARKET card dragged here is
      //     RECRUITED (drag-to-recruit).
      //   * inner DragTarget<CardModel>       — a HAND card dragged here is
      //     PLAYED (drag-to-play).
      field: DragTarget<_MarketCardDrag>(
        onWillAcceptWithDetails: (_) => myTurn,
        onAcceptWithDetails: (details) => _onCenterTap(details.data.card),
        builder: (context, marketCandidate, _) {
          return DragTarget<CardModel>(
            onWillAcceptWithDetails: (_) => myTurn,
            onAcceptWithDetails: (details) => _playHandCard(details.data),
            builder: (context, candidate, rejected) {
              return KeyedSubtree(
                key: _playAreaKey,
                child: _NetworkPlayField(
                opponentChampions: opponent?.champions ?? const [],
                opponentPlayedThisTurn: opponent?.playedThisTurn ?? const [],
                opponentName: opponent?.name,
                opponentId: opponent?.id,
                cardFor: _card,
                canAttackChampions: myTurn && me.powerPool > 0,
                onAttackChampion: _onOpponentChampionTap,
                onZoomCard: _zoomOne,
                myChampions: me.champions,
                playedThisTurn: me.playedThisTurn,
                onActivateChampion: myTurn ? _onMyChampionTap : null,
                onZoomMyChampion: (champ) =>
                    _zoomMyChampion(me.champions, champ),
                actionMessage: _actionMessage,
                screenWidth: screenWidth,
                isDropTarget:
                    candidate.isNotEmpty || marketCandidate.isNotEmpty,
              ),
              );
            },
          );
        },
      ),

      footer: [
        // ---- Bottom zone: End Turn + chips + hand + Play All --------------
        // Hand gestures: tap = zoom (card detail), long-press = begin
        // drag-to-play (drop on the play field above).
        _NetworkBottomZone(
          me: me,
          deckFaction: _dominantFaction(me),
          screenWidth: screenWidth,
          hand: [for (final id in me.hand) _card(id)],
          enabled: myTurn,
          onCardTap: zoomHand,
          onCardLongPress: zoomHand,
          onDragPlayStarted: _onHandDragStarted,
          onEndTurn: myTurn ? client.endTurn : null,
          // Undo is gated on the server-sent canUndo flag (your turn AND a
          // same-turn snapshot exists); null disables the button.
          onUndo: client.canUndo ? client.undo : null,
          onPlayAll: myTurn && me.hand.isNotEmpty ? client.playAllCards : null,
          exhaustableCount: myTurn ? _exhaustableCount(view) : 0,
          onExhaustAll: myTurn ? () => _onExhaustAll(view) : null,
          onAttack: canAttackPlayer
              ? () => _onAttackPlayer(opponent, me.powerPool)
              : null,
          hasGuards: opponentHasGuard,
          onTapDraw: () => _showDrawPile(me),
          onTapDiscard: () => _showDiscard(me),
          onFocus: (myTurn && !me.focusedThisTurn && me.gemPool >= 1)
              ? _onFocus
              : null,
          // Destiny / Relic acquisition — only present when eligible (mirrors
          // the local board). The server re-validates on send.
          onClaimDestiny:
              _canClaimDestiny(view, me) ? () => _openDestinyModal(view) : null,
          onRecruitRelic:
              _canRecruitRelic(me) ? () => _openRelicModal(me) : null,
          onOpenDestinyTray: me.claimedDestinies.isNotEmpty
              ? () => _openDestinyTray(me)
              : null,
          conditionsMet: conditionsMet,
          gemAnchorKey: _gemAnchorKey,
          powerAnchorKey: _powerAnchorKey,
          masteryAnchorKey: _masteryAnchorKey,
          deckAnchorKey: _deckAnchorKey,
          discardAnchorKey: _discardAnchorKey,
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
    required this.destinyRow,
    required this.currentPlayerIndex,
    required this.turnNumber,
    required this.isGameOver,
    required this.winnerId,
    required this.winType,
    required this.actionLog,
  });

  final List<_PlayerView> players;
  final String meId;
  final List<String> centerRow;

  /// Ids of the shared face-up Destiny row (claimable at Mastery 5+). Empty when
  /// no Destiny supply is in play. The cards are in the state's `cards` dict.
  final List<String> destinyRow;
  final int currentPlayerIndex;
  final int turnNumber;
  final bool isGameOver;
  final String? winnerId;

  /// HOW the game was won: 'mastery' / 'elimination' / 'draw' (null in progress).
  final String? winType;

  /// Public action log (recent tail), each entry {turn, playerId?, message}.
  final List<Map<String, dynamic>> actionLog;

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
      destinyRow: (state['destinyRow'] as List? ?? const []).cast<String>(),
      currentPlayerIndex: (state['currentPlayerIndex'] as int?) ?? 0,
      turnNumber: (state['turnNumber'] as int?) ?? 1,
      isGameOver: state['isGameOver'] == true,
      winnerId: state['winnerId'] as String?,
      winType: state['winType'] as String?,
      actionLog: [
        for (final e in (state['actionLog'] as List? ?? const []))
          (e as Map).cast<String, dynamic>(),
      ],
    );
  }

  /// Display name for a player id, from this view's players (falls back to id).
  String nameFor(String? playerId) {
    if (playerId == null) return '';
    for (final p in players) {
      if (p.id == playerId) return p.name;
    }
    return playerId;
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
    required this.focusedThisTurn,
    required this.hand,
    required this.handCount,
    required this.drawPileCount,
    required this.drawPileContents,
    required this.discard,
    required this.champions,
    required this.playedThisTurn,
    required this.claimedDestinies,
    required this.exhaustedDestinies,
    required this.canClaimAnotherDestiny,
    required this.relicOptions,
    required this.relicRecruited,
    required this.unblockedDamageThisTurn,
  });

  final String id;
  final String name;
  final int health;
  final int mastery;
  final int gemPool;
  final int powerPool;
  final bool eliminated;

  /// Whether this player has used their once-per-turn Focus action.
  final bool focusedThisTurn;

  /// Unblocked damage this player has dealt to opponents this turn (redacted
  /// scalar). Used by the client-side `unblockedDamageAtLeast` condition.
  final int unblockedDamageThisTurn;

  /// Ids of Destinies this player has claimed (public, face-up beside them).
  final List<String> claimedDestinies;

  /// Ids of claimed Destinies whose ability was already used this turn (greys
  /// the Destinies tray's Use action). Mirrors the per-champion exhausted flag.
  final List<String> exhaustedDestinies;

  /// Server-computed: whether this player may still claim a Destiny this game
  /// (under the per-game allowance). Combine with mastery + a non-empty row.
  final bool canClaimAnotherDestiny;

  /// This player's two set-aside Relic options — ONLY populated in the owner's
  /// own redacted view (empty for opponents; relic choices are private).
  final List<String> relicOptions;

  /// Whether this player has already recruited (or forgone) their Relic.
  final bool relicRecruited;

  /// Full ids ONLY for the recipient; empty for opponents (hidden info).
  final List<String> hand;

  /// Card count — always available, even when [hand] is hidden.
  final int handCount;
  final int drawPileCount;

  /// The recipient's OWN draw-pile card ids, server-sorted (contents visible,
  /// order hidden). Empty for opponents.
  final List<String> drawPileContents;

  /// Discard pile card ids — public info (discards are face-up).
  final List<String> discard;
  int get discardCount => discard.length;
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
      focusedThisTurn: p['focusedThisTurn'] == true,
      unblockedDamageThisTurn: (p['unblockedDamageThisTurn'] as int?) ?? 0,
      hand: hand,
      handCount: (p['handCount'] as int?) ?? hand.length,
      drawPileCount: (p['drawPileCount'] as int?) ?? 0,
      drawPileContents:
          (p['drawPileContents'] as List?)?.cast<String>() ?? const <String>[],
      discard: (p['discardPile'] as List?)?.cast<String>() ?? const <String>[],
      champions: [
        for (final c in (p['championsInPlay'] as List? ?? const []).cast<Map>())
          _ChampionView.parse(c),
      ],
      playedThisTurn:
          (p['playedThisTurn'] as List?)?.cast<String>() ?? const <String>[],
      claimedDestinies:
          (p['claimedDestinies'] as List?)?.cast<String>() ?? const <String>[],
      exhaustedDestinies:
          (p['exhaustedDestinies'] as List?)?.cast<String>() ??
              const <String>[],
      canClaimAnotherDestiny: p['canClaimAnotherDestiny'] == true,
      relicOptions:
          (p['relicOptions'] as List?)?.cast<String>() ?? const <String>[],
      relicRecruited: p['relicRecruited'] == true,
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

/// One selectable target in a deferred-selection picker — a resolved card plus a
/// short zone label (Hand / Discard / Center row / owner name).
class _TargetCandidate {
  _TargetCandidate(this.card, this.zone, {this.ownerId});
  final CardModel card;
  final String zone;

  /// For enemy-champion targets: which opponent OWNS this champion. Carried on
  /// the candidate (not an id-keyed map) because champion ids are card-TYPE ids
  /// that can repeat across opponents in 3-4 player games.
  final String? ownerId;
  String get id => card.id;
}

// ===========================================================================
// Sub-widgets (mirror game_screen.dart chrome, redacted-state driven)
// ===========================================================================

/// Top bar — centered opponent pill (HP/mastery/gems) + a turn badge.
class _NetworkTopBar extends StatelessWidget {
  const _NetworkTopBar({
    required this.opponent,
    required this.myTurn,
    required this.onBackToLobby,
    required this.onShowLog,
  });

  final _PlayerView? opponent;
  final bool myTurn;

  /// Pop back to the lobby without tearing down the connection.
  final VoidCallback onBackToLobby;

  /// Open the scrollable game log.
  final VoidCallback onShowLog;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Left controls — back-to-lobby (switch games) + game log.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: onBackToLobby,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFBFD8E8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.meeting_room, size: 16),
                      label: const Text('Lobby',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    TextButton.icon(
                      onPressed: onShowLog,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFBFD8E8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.receipt_long, size: 16),
                      label: const Text('Log',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    // Fullscreen toggle — web only (no-op/hidden on native).
                    if (Fullscreen.instance.isSupported)
                      const _FullscreenButton(),
                  ],
                ),
              ),
            ),
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

/// A web-only fullscreen toggle for the top bar. Shows enter/exit-fullscreen
/// icons and flips the browser Fullscreen state. Hidden on native (the parent
/// only builds it when `Fullscreen.instance.isSupported`).
class _FullscreenButton extends StatefulWidget {
  const _FullscreenButton();

  @override
  State<_FullscreenButton> createState() => _FullscreenButtonState();
}

class _FullscreenButtonState extends State<_FullscreenButton> {
  @override
  Widget build(BuildContext context) {
    final full = Fullscreen.instance.isFullscreen;
    return TextButton.icon(
      onPressed: () {
        Fullscreen.instance.toggle();
        // Rebuild after the browser applies the change so the icon updates.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFBFD8E8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(full ? Icons.fullscreen_exit : Icons.fullscreen, size: 16),
      label: Text(full ? 'Exit' : 'Fullscreen',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
        AnimatedCounter(
          value: value,
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
        AnimatedCounter(
          value: value,
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

/// Drag payload for a market card being dragged toward the play field to be
/// recruited. A DISTINCT type from a hand-card drag (raw [CardModel]) so the
/// play field's two DragTargets never cross-fire: a market drag only triggers
/// the recruit target, a hand drag only the play target.
class _MarketCardDrag {
  const _MarketCardDrag(this.card);
  final CardModel card;
}

/// Center row — 6 market cards, sized to fit the row width (mirrors
/// game_screen.dart's _CenterRow).
class _NetworkCenterRow extends StatelessWidget {
  const _NetworkCenterRow({
    required this.cards,
    required this.canAfford,
    required this.onTapCard,
    required this.onLongPressCard,
    required this.screenWidth,
    this.onDragStarted,
    this.conditionsMet,
  });

  final List<CardModel> cards;
  final bool Function(CardModel) canAfford;
  final void Function(CardModel) onTapCard;
  final void Function(CardModel) onLongPressCard;

  /// Fired when a market card begins being dragged (long-press). Null disables
  /// dragging (off-turn). Dropping on the play field recruits the card.
  final void Function(CardModel)? onDragStarted;
  final double screenWidth;

  /// Returns true for a market card whose conditional bonus is active now (paints
  /// a yellow glow). Null = never glow.
  final bool Function(CardModel)? conditionsMet;

  @override
  Widget build(BuildContext context) {
    // On a narrow phone held in PORTRAIT, six cards in a single row are
    // uncomfortably small. Re-flow the market into TWO ROWS OF THREE so each
    // card is sized off screenWidth/3 (noticeably bigger). Landscape / tablet /
    // desktop keep the single-row layout unchanged.
    final isPortraitPhone = Responsive.isMobile(screenWidth) &&
        MediaQuery.of(context).orientation == Orientation.portrait;

    if (isPortraitPhone) {
      return _buildPortraitGrid(context);
    }
    return _buildSingleRow(context);
  }

  /// Default single-row market: six cards across (landscape / tablet / desktop).
  Widget _buildSingleRow(BuildContext context) {
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
            for (final card in cards) _marketCard(card, cardWidth),
          ],
        ),
      ),
    );
  }

  /// Mobile-portrait market: two rows of three, each card sized off
  /// screenWidth/3 so the cards are large and readable.
  Widget _buildPortraitGrid(BuildContext context) {
    const perRow = 3;
    const hPad = 8.0; // outer horizontal padding on each side
    const gap = 8.0; // gap between cards in a row
    final usable = (screenWidth - hPad * 2).clamp(0.0, Responsive.maxContentWidth);
    // Three cards + two inter-card gaps per row.
    final slot = (usable - gap * (perRow - 1)) / perRow;
    final cardWidth = slot.clamp(64.0, 180.0);

    // Split the (up to 6) cards into rows of three.
    final rows = <List<CardModel>>[];
    for (var i = 0; i < cards.length; i += perRow) {
      rows.add(cards.sublist(
          i, (i + perRow).clamp(0, cards.length)));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: hPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: gap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < rows[r].length; c++) ...[
                  if (c > 0) const SizedBox(width: gap),
                  _marketCard(rows[r][c], cardWidth),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _marketCard(CardModel card, double cardWidth) =>
      _MaybeDraggableMarketCard(
        card: card,
        cardWidth: cardWidth,
        canDrag: onDragStarted != null,
        isHighlighted: canAfford(card),
        conditionsMet: conditionsMet?.call(card) ?? false,
        onTap: () => onTapCard(card),
        onLongPress: () => onLongPressCard(card),
        onDragStarted: () => onDragStarted?.call(card),
      );
}

/// A market card that is TAP-to-select and (on your turn) LONG-PRESS-to-drag
/// (drop on the play field → recruit). Mirrors the hand's [_DraggableHandCard]:
/// when draggable, the long-press begins the drag, so the card's own onLongPress
/// popup is suppressed (tap still opens the popup).
class _MaybeDraggableMarketCard extends StatelessWidget {
  const _MaybeDraggableMarketCard({
    required this.card,
    required this.cardWidth,
    required this.canDrag,
    required this.isHighlighted,
    required this.conditionsMet,
    required this.onTap,
    required this.onLongPress,
    required this.onDragStarted,
  });

  final CardModel card;
  final double cardWidth;
  final bool canDrag;
  final bool isHighlighted;
  final bool conditionsMet;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDragStarted;

  @override
  Widget build(BuildContext context) {
    final resting = GameCardWidget(
      key: ValueKey(card.id),
      card: card,
      onTap: onTap,
      // Tap opens the popup (Recruit / Fast Play). A plain Draggable starts the
      // drag on pointer MOVEMENT, so a stationary tap still fires onTap and a
      // long-press still opens the popup — no hold delay to begin dragging.
      onLongPress: onLongPress,
      isHighlighted: isHighlighted,
      conditionsMet: conditionsMet,
      width: cardWidth,
    );

    if (!canDrag) return resting;

    final feedback = Material(
      color: Colors.transparent,
      child: Transform.scale(
        scale: 1.1,
        child: GameCardWidget(
          card: card,
          isHighlighted: true,
          showCost: false,
          width: cardWidth,
        ),
      ),
    );

    return Draggable<_MarketCardDrag>(
      data: _MarketCardDrag(card),
      dragAnchorStrategy: childDragAnchorStrategy,
      onDragStarted: onDragStarted,
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.3, child: resting),
      child: resting,
    );
  }
}

/// Play field — opponent champions (top) + my champions / played cards.
class _NetworkPlayField extends StatelessWidget {
  const _NetworkPlayField({
    required this.opponentChampions,
    required this.opponentPlayedThisTurn,
    required this.opponentName,
    required this.opponentId,
    required this.cardFor,
    required this.canAttackChampions,
    required this.onAttackChampion,
    required this.onZoomCard,
    required this.myChampions,
    required this.playedThisTurn,
    required this.onActivateChampion,
    required this.onZoomMyChampion,
    required this.actionMessage,
    required this.screenWidth,
    this.isDropTarget = false,
  });

  final List<_ChampionView> opponentChampions;

  /// Card ids the opponent has played THIS turn (public info) — rendered in an
  /// opponent play area so you can follow their turn live.
  final List<String> opponentPlayedThisTurn;
  final String? opponentName;
  final String? opponentId;
  final CardModel Function(String id) cardFor;
  final bool canAttackChampions;
  final void Function(CardModel champ, String ownerId) onAttackChampion;

  /// Long-press a champion / played card → zoom it.
  final void Function(CardModel) onZoomCard;
  final List<_ChampionView> myChampions;
  final List<String> playedThisTurn;
  final void Function(CardModel)? onActivateChampion;

  /// Long-press one of MY champions → open the champion zoom (Activate +
  /// conditional Exhaust), carrying its exhausted/activated status.
  final void Function(_ChampionView) onZoomMyChampion;
  final String? actionMessage;
  final double screenWidth;

  /// True while a hand card is being dragged over this play field (drag-to-play
  /// hover) — paints a subtle drop-zone highlight.
  final bool isDropTarget;

  @override
  Widget build(BuildContext context) {
    final cardWidth = Responsive.compactCardWidth(screenWidth);
    final champHeight = cardWidth * (130 / 90) + 4;
    // In mobile-portrait the play field is squeezed (the market takes two rows
    // and the hand is prioritised). Drop the flexible Spacer for a fixed gap and
    // make the content vertically scrollable so it never overflows its box.
    final isPortraitPhone = Responsive.isMobile(screenWidth) &&
        MediaQuery.of(context).orientation == Orientation.portrait;

    final playColumn = Column(
      mainAxisSize: isPortraitPhone ? MainAxisSize.min : MainAxisSize.max,
      children: [
            // Opponent champions row (just under the center row).
            if (opponentChampions.isNotEmpty && opponentId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: champHeight,
                  width: double.infinity,
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final champ in opponentChampions)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: AnimatedZoneList.wrap(
                                id: champ.id,
                                child: _ChampionTile(
                                  card: cardFor(champ.id),
                                  champ: champ,
                                  width: cardWidth,
                                  isHighlighted: canAttackChampions,
                                  // Tap attacks when you can; otherwise it falls
                                  // back to zoom so any card is always
                                  // inspectable, even when you can't act on it.
                                  onTap: canAttackChampions
                                      ? () => onAttackChampion(
                                          cardFor(champ.id), opponentId!)
                                      : () => onZoomCard(cardFor(champ.id)),
                                  onLongPress: () =>
                                      onZoomCard(cardFor(champ.id)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Opponent play area — cards they've played this turn (public).
            // Mirrors your own played-this-turn row, so you can follow their
            // turn live as the server broadcasts each action.
            if (opponentPlayedThisTurn.isNotEmpty && opponentId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${opponentName ?? 'Opponent'} played this turn',
                        style: const TextStyle(
                          color: Color(0xFFBFD8E8),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: champHeight,
                      width: double.infinity,
                      child: Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final id in opponentPlayedThisTurn)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: AnimatedZoneList.wrap(
                                    id: id,
                                    child: GameCardWidget(
                                      card: cardFor(id),
                                      compact: true,
                                      showCost: false,
                                      width: cardWidth,
                                      onTap: () => onZoomCard(cardFor(id)),
                                      onLongPress: () => onZoomCard(cardFor(id)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (isPortraitPhone)
              const SizedBox(height: 6)
            else
              const Spacer(),
            // My champions + played-this-turn row, just above the hand. Centered
            // (like the official client) so it sits in the middle of the play
            // field rather than hugging the left edge over the End Turn column.
            if (myChampions.isNotEmpty || playedThisTurn.isNotEmpty)
              SizedBox(
                height: champHeight,
                width: double.infinity,
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Champions live in a labelled "tray" that visually sets
                        // them aside as persistent, board-resident cards.
                        if (myChampions.isNotEmpty)
                          _ChampionsTray(
                            height: champHeight,
                            children: [
                              for (final champ in myChampions)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: AnimatedZoneList.wrap(
                                    id: champ.id,
                                    child: Stack(
                                      children: [
                                        GameCardWidget(
                                          card: cardFor(champ.id),
                                          compact: true,
                                          showCost: false,
                                          width: cardWidth,
                                          isHighlighted: !champ.activated,
                                          // Tap ALWAYS opens the zoom window
                                          // (with Activate/Exhaust actions) — no
                                          // long-press needed. Activating /
                                          // playing is done by dragging the card
                                          // into the play area, or via the zoom
                                          // window's buttons.
                                          onTap: () => onZoomMyChampion(champ),
                                          onLongPress: () =>
                                              onZoomMyChampion(champ),
                                        ),
                                        if (champ.activated)
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
                                              child: const Icon(Icons.check,
                                                  size: 10, color: Colors.white),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        if (myChampions.isNotEmpty && playedThisTurn.isNotEmpty)
                          const SizedBox(width: 8),
                        for (final id in playedThisTurn)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: AnimatedZoneList.wrap(
                              id: id,
                              child: GameCardWidget(
                                card: cardFor(id),
                                compact: true,
                                showCost: false,
                                width: cardWidth,
                                onTap: () => onZoomCard(cardFor(id)),
                                onLongPress: () => onZoomCard(cardFor(id)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );

    return Stack(
      children: [
        // Drop-zone highlight while a card hovers over the play area.
        if (isDropTarget)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: BoardChrome.tealHighlight.withValues(alpha: 0.8),
                    width: 2,
                  ),
                  color: BoardChrome.tealHighlight.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
        // In portrait, let the (top-aligned) content scroll if the squeezed play
        // field is shorter than the champion rows — never overflow. In the wide
        // layout the Spacer-based column fills the box exactly (unchanged).
        if (isPortraitPhone)
          Positioned.fill(
            child: SingleChildScrollView(child: playColumn),
          )
        else
          playColumn,
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

/// An opponent champion tile — the card plus small status badges so you can see
/// when the opponent taps a champion (exhausted) or fires its activated ability
/// (activated). Mirrors the activated checkmark used on your own champions.
class _ChampionTile extends StatelessWidget {
  const _ChampionTile({
    required this.card,
    required this.champ,
    required this.width,
    required this.isHighlighted,
    required this.onTap,
    required this.onLongPress,
  });

  final CardModel card;
  final _ChampionView champ;
  final double width;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Exhausted (tapped) champions are dimmed, matching tabletop intuition.
        Opacity(
          opacity: champ.exhausted ? 0.55 : 1.0,
          child: GameCardWidget(
            card: card,
            compact: true,
            width: width,
            isHighlighted: isHighlighted,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
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
              child: const Icon(Icons.check, size: 10, color: Colors.white),
            ),
          ),
        if (champ.exhausted)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.bedtime,
                  size: 10, color: Color(0xFFE8C45A)),
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
    required this.deckFaction,
    required this.screenWidth,
    required this.hand,
    required this.enabled,
    required this.onCardTap,
    required this.onCardLongPress,
    required this.onDragPlayStarted,
    required this.onEndTurn,
    required this.onUndo,
    required this.onPlayAll,
    required this.exhaustableCount,
    required this.onExhaustAll,
    required this.onAttack,
    required this.hasGuards,
    required this.onTapDraw,
    required this.onTapDiscard,
    required this.onFocus,
    required this.onClaimDestiny,
    required this.onRecruitRelic,
    required this.onOpenDestinyTray,
    required this.conditionsMet,
    this.gemAnchorKey,
    this.powerAnchorKey,
    this.masteryAnchorKey,
    this.deckAnchorKey,
    this.discardAnchorKey,
  });

  /// Fly-animation anchors for the player's resource counters and piles.
  final GlobalKey? gemAnchorKey;
  final GlobalKey? powerAnchorKey;
  final GlobalKey? masteryAnchorKey;
  final GlobalKey? deckAnchorKey;
  final GlobalKey? discardAnchorKey;

  final _PlayerView me;

  /// The player's dominant faction — drives the colour of the flame backdrop
  /// behind the draw pile. [Faction.none] = neutral grey (all-starter deck).
  final Faction deckFaction;
  final double screenWidth;
  final List<CardModel> hand;
  final bool enabled;
  final void Function(CardModel) onCardTap;
  final void Function(CardModel) onCardLongPress;

  /// Returns true for a hand card whose conditional bonus is active now (yellow
  /// glow). Null = never glow.
  final bool Function(CardModel)? conditionsMet;

  /// Fired when a hand card starts being dragged out (long-press) toward the
  /// play area. Only relevant when [enabled] (your turn).
  final void Function(CardModel) onDragPlayStarted;
  final VoidCallback? onEndTurn;

  /// Undo last action this turn. Null when unavailable (off-turn / no history).
  final VoidCallback? onUndo;
  final VoidCallback? onPlayAll;

  /// Count of champions still Exhaustable this turn — surfaces the Exhaust phase.
  final int exhaustableCount;

  /// Exhaust ALL ready champions (the champion-side Play All). Null off-turn.
  final VoidCallback? onExhaustAll;
  final VoidCallback? onAttack;
  final bool hasGuards;
  final VoidCallback onTapDraw;
  final VoidCallback onTapDiscard;

  /// Character Focus (1 gem → 1 mastery). Null when unavailable this turn.
  final VoidCallback? onFocus;

  /// Open the Destiny-claim modal (Mastery 5). Null when ineligible — then no
  /// Destiny entry point shows.
  final VoidCallback? onClaimDestiny;

  /// Open the Relic-recruit modal (Mastery 10). Null when ineligible.
  final VoidCallback? onRecruitRelic;

  /// Open the Destinies tray (claimed-Destiny abilities). Null when the player
  /// has no claimed Destinies, so no Destinies button shows.
  final VoidCallback? onOpenDestinyTray;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(screenWidth);
    // Mobile-portrait gets a re-flowed, space-efficient layout that stacks the
    // controls above a full-width hand so the player's cards are prominent.
    final isPortraitPhone = isMobile &&
        MediaQuery.of(context).orientation == Orientation.portrait;

    final child =
        isPortraitPhone ? _buildPortrait(context) : _buildWide(context, isMobile);

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
      padding: EdgeInsets.fromLTRB(8, 2, 8, isPortraitPhone ? 4 : 6),
      child: child,
    );
  }

  /// Default landscape / tablet / desktop bottom zone: a left control column,
  /// the power diamond, the hand fan, and a right control column.
  Widget _buildWide(BuildContext context, bool isMobile) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left column: resource chips + Focus/acquisition pills, with the DRAW
          // pile anchored at the BOTTOM-LEFT (Undo removed; End Turn folded into
          // the morphing primary button on the right).
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  KeyedSubtree(
                    key: masteryAnchorKey,
                    child: _StatChip(
                        icon: ResourceIcon.mastery,
                        value: me.mastery,
                        fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  KeyedSubtree(
                    key: gemAnchorKey,
                    child: _StatChip(
                        icon: ResourceIcon.gem,
                        value: me.gemPool,
                        fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Focus: spend 1 gem → +1 mastery, once per turn.
              _FocusButton(onPressed: onFocus),
              // Destinies tray — the "second Focus button" for claimed Destiny
              // abilities. Only shows when at least one Destiny is claimed.
              if (onOpenDestinyTray != null) ...[
                const SizedBox(height: 4),
                _AcquirePill(
                  icon: Icons.bolt,
                  label: 'Destinies',
                  onPressed: onOpenDestinyTray,
                ),
              ],
              // Destiny / Relic acquisition pills — only appear when eligible.
              if (onClaimDestiny != null) ...[
                const SizedBox(height: 4),
                _AcquirePill(
                  icon: Icons.auto_awesome,
                  label: 'Destiny',
                  onPressed: onClaimDestiny,
                ),
              ],
              if (onRecruitRelic != null) ...[
                const SizedBox(height: 4),
                _AcquirePill(
                  icon: Icons.diamond,
                  label: 'Relic',
                  onPressed: onRecruitRelic,
                ),
              ],
              const SizedBox(height: 4),
              KeyedSubtree(
                key: deckAnchorKey,
                child: FactionFlameBackdrop(
                  faction: deckFaction,
                  child: _PileHex(
                    count: me.drawPileCount,
                    style: _PileStyle.draw,
                    onTap: onTapDraw,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Power diamond.
          KeyedSubtree(
            key: powerAnchorKey,
            child: _ValueDiamond(value: me.powerPool),
          ),
          const SizedBox(width: 4),
          // Center: hand fan. Tap = zoom (always), long-press = begin
          // drag-to-play (only on your turn — off-turn, drag is disabled and
          // long-press falls back to zoom).
          Expanded(
            child: CardFan(
              cards: hand,
              onCardTap: onCardTap,
              onCardLongPress: onCardLongPress,
              onDragStarted: onDragPlayStarted,
              draggable: enabled,
              selectedCardId: null,
              conditionsMet: conditionsMet,
            ),
          ),
          const SizedBox(width: 4),
          // Right column: the single morphing primary button (Play All → Attack
          // → End Turn) with the DISCARD pile anchored at the BOTTOM-RIGHT.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (hasGuards && me.powerPool > 0 && hand.isEmpty)
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
              _PrimaryActionButton(
                handCount: hand.length,
                exhaustableCount: exhaustableCount,
                powerPool: me.powerPool,
                hasGuards: hasGuards,
                onPlayAll: onPlayAll,
                onExhaustAll: onExhaustAll,
                onAttack: onAttack,
                onEndTurn: onEndTurn,
                width: isMobile ? 96 : 132,
                height: isMobile ? 56 : 80,
                fontSize: isMobile ? 18 : 26,
              ),
              const SizedBox(height: 4),
              KeyedSubtree(
                key: discardAnchorKey,
                child: _PileHex(
                  count: me.discardCount,
                  style: _PileStyle.discard,
                  onTap: onTapDiscard,
                ),
              ),
            ],
          ),
        ],
      );
  }

  /// Mobile-portrait bottom zone. Controls are compacted into two slim rows at
  /// the top (action buttons + resource chips), then the hand fan spans the full
  /// width flanked by the piles, so the player's HAND gets the most room.
  Widget _buildPortrait(BuildContext context) {
    // Row 1 (resource chips + power + Focus + acquisition pills), all in one
    // compact, wrapping row.
    final statusRow = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _StatChip(icon: ResourceIcon.health, value: me.health, fontSize: 13),
        KeyedSubtree(
          key: masteryAnchorKey,
          child: _StatChip(
              icon: ResourceIcon.mastery, value: me.mastery, fontSize: 13),
        ),
        KeyedSubtree(
          key: gemAnchorKey,
          child:
              _StatChip(icon: ResourceIcon.gem, value: me.gemPool, fontSize: 13),
        ),
        KeyedSubtree(
          key: powerAnchorKey,
          child: _StatChip(
              icon: ResourceIcon.power, value: me.powerPool, fontSize: 13),
        ),
        _FocusButton(onPressed: onFocus),
        if (onOpenDestinyTray != null)
          _AcquirePill(
            icon: Icons.bolt,
            label: 'Destinies',
            onPressed: onOpenDestinyTray,
          ),
        if (onClaimDestiny != null)
          _AcquirePill(
            icon: Icons.auto_awesome,
            label: 'Destiny',
            onPressed: onClaimDestiny,
          ),
        if (onRecruitRelic != null)
          _AcquirePill(
            icon: Icons.diamond,
            label: 'Relic',
            onPressed: onRecruitRelic,
          ),
      ],
    );

    // Row 3: draw pile | hand fan (expanded, full width) | Play All + discard.
    final handRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        KeyedSubtree(
          key: deckAnchorKey,
          child: FactionFlameBackdrop(
            faction: deckFaction,
            width: 66,
            height: 90,
            child: _PileHex(
              count: me.drawPileCount,
              style: _PileStyle.draw,
              onTap: onTapDraw,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: CardFan(
            cards: hand,
            onCardTap: onCardTap,
            onCardLongPress: onCardLongPress,
            onDragStarted: onDragPlayStarted,
            draggable: enabled,
            selectedCardId: null,
            conditionsMet: conditionsMet,
          ),
        ),
        const SizedBox(width: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PrimaryActionButton(
              handCount: hand.length,
              exhaustableCount: exhaustableCount,
              powerPool: me.powerPool,
              hasGuards: hasGuards,
              onPlayAll: onPlayAll,
              onExhaustAll: onExhaustAll,
              onAttack: onAttack,
              onEndTurn: onEndTurn,
              width: 84,
              height: 46,
              fontSize: 15,
            ),
            const SizedBox(height: 4),
            KeyedSubtree(
              key: discardAnchorKey,
              child: _PileHex(
                count: me.discardCount,
                style: _PileStyle.discard,
                onTap: onTapDiscard,
              ),
            ),
          ],
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        statusRow,
        const SizedBox(height: 4),
        handRow,
      ],
    );
  }
}

/// Small "Focus" pill — spend 1 gem to gain 1 mastery (once per turn). Greyed
/// out when unavailable (not your turn / already focused / no gems).
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

/// A small gold acquisition pill (Destiny / Relic) shown beneath Focus when the
/// player is eligible to claim/recruit. Opens the shared choice modal. Mirrors
/// the local board's `_AcquireButton`.
class _AcquirePill extends StatelessWidget {
  const _AcquirePill({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8C45A), Color(0xFFB8902F)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: BoardChrome.goldRim.withValues(alpha: 0.9), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: BoardChrome.goldText.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF2A1C00)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF2A1C00),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The single morphing PRIMARY action button that walks the player through the
/// turn in order: **Play All** (cards in hand) → **Exhaust** (un-exhausted
/// champions with abilities remain — the champion-side equivalent of Play All)
/// → **Attack (N)** (power available, opponent not fully guard-blocked) → **End
/// Turn**. Recruiting from the market and attacking champions stay free at any
/// time via their own taps — this button only ever advances the MAIN sequence.
///
/// Each phase's callback is supplied by the board (null when unavailable). The
/// button picks the first applicable phase and renders its label/colour, so the
/// player always sees exactly the next step.
class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.handCount,
    required this.exhaustableCount,
    required this.powerPool,
    required this.hasGuards,
    required this.onPlayAll,
    required this.onExhaustAll,
    required this.onAttack,
    required this.onEndTurn,
    required this.width,
    required this.height,
    required this.fontSize,
  });

  final int handCount;

  /// How many champions can still be Exhausted this turn (have an activated
  /// ability and aren't exhausted). > 0 surfaces the Exhaust phase.
  final int exhaustableCount;
  final int powerPool;

  /// True when every living opponent's face is behind a guard (so a face attack
  /// is impossible even with power — the button skips to End Turn).
  final bool hasGuards;

  final VoidCallback? onPlayAll;
  final VoidCallback? onExhaustAll;
  final VoidCallback? onAttack;
  final VoidCallback? onEndTurn;
  final double width;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Phase 1: cards still in hand → Play All.
    if (handCount > 0 && onPlayAll != null) {
      return BeveledButton(
        label: 'Play All',
        onPressed: onPlayAll,
        style: BeveledStyle.green,
        width: width,
        height: height,
        fontSize: fontSize,
      );
    }
    // Phase 2: hand empty, champions still ready to Exhaust → Exhaust (the
    // champion-side "play all").
    if (handCount == 0 && exhaustableCount > 0 && onExhaustAll != null) {
      return BeveledButton(
        label: 'Exhaust',
        onPressed: onExhaustAll,
        style: BeveledStyle.green,
        width: width,
        height: height,
        fontSize: fontSize,
      );
    }
    // Phase 3: hand empty, power available, a face is attackable → Attack.
    if (handCount == 0 && powerPool > 0 && !hasGuards && onAttack != null) {
      return BeveledButton(
        label: 'Attack ($powerPool)',
        onPressed: onAttack,
        style: BeveledStyle.green,
        width: width,
        height: height,
        fontSize: fontSize,
      );
    }
    // Phase 4: nothing left to do in sequence → End Turn.
    return BeveledButton(
      label: 'End Turn',
      onPressed: onEndTurn,
      width: width,
      height: height,
      fontSize: fontSize,
    );
  }
}

/// A light bordered "tray" that visually groups the player's champions and
/// labels them "Champions", setting them apart from the turn's transient plays.
/// The label is a small pill riding the top-left of the border so the tray adds
/// no vertical height beyond its card row.
class _ChampionsTray extends StatelessWidget {
  const _ChampionsTray({required this.children, required this.height});

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(6, 5, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: children),
          // Floating label pill on the top-left border.
          Positioned(
            top: -13,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF102A40),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: const Text(
                'Champions',
                style: TextStyle(
                  color: Color(0xFFBFD8E8),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PileStyle { draw, discard }

class _PileHex extends StatelessWidget {
  const _PileHex({required this.count, required this.style, this.onTap});
  final int count;
  final _PileStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDraw = style == _PileStyle.draw;
    final colors = isDraw
        ? const [Color(0xFF2FA85B), Color(0xFF16622F)]
        : const [Color(0xFF9A4A2E), Color(0xFF5A2415)];
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
              ),
            ),
            // A tiny affordance hint that the pile is tappable.
            Icon(
              isDraw ? Icons.style : Icons.layers,
              size: 11,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
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
