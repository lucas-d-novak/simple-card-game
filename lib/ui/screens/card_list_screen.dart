import 'package:flutter/material.dart';
import 'package:simple_card_game/data/card_art_map.dart';
import 'package:simple_card_game/data/character_relics.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/card_database_asset.dart';
import 'package:simple_card_game/models/card_type.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/widgets/card_art.dart';

/// A derived faction/group bucket used to GROUP and ORDER the card list.
///
/// The engine's [Faction] enum only models the four playable factions (plus
/// [Faction.none]); "Aion" and "Prism" are NOT factions — they live in the
/// database `group` field with `faction == none`. So the bucket is a DERIVED
/// key: Aion/Prism come from `group`, the four factions from the enum, and the
/// Into-the-Horizon Destiny supply (`group` == 'Destiny'/'DestinyDeck') gets its
/// own [destiny] bucket.
///
/// Two families are hidden from the catalog entirely BEFORE bucketing (see
/// [_isCoopEnemy] / [_isRelic]) and therefore never reach [_bucketOf]:
/// - the co-op/enemy boss & minion groups (`faction == none` with a non-Aion/
///   Prism/Destiny `group` — Vox, Dominatus, Ingeminex, …), and
/// - every Relic card (recruited one-of-two at Mastery 10, not a normal supply).
///
/// Relics are NOT a group: they carry their playable `faction` (or the Aion/
/// Prism group) — so they are filtered by id/type-line, not by bucket. Enum
/// order == display order: Aion, Prism, Order, Undergrowth, Homodeus, Wraethe,
/// Destiny.
enum _Bucket {
  aion,
  prism,
  order,
  undergrowth,
  homodeus,
  wraethe,
  destiny,
}

/// Relic card ids recruited via the Mastery-10 `recruitRelic` supply, taken
/// authoritatively from [characterRelicIds] in `character_relics.dart`. Covers
/// the Homodeus/Order/Undergrowth/Wraethe relics; the Aion/Prism relics carry no
/// mapped Character, so they are caught by the type-line fallback in [_isRelic].
final Set<String> _relicCardIds =
    characterRelicIds.values.expand((ids) => ids).toSet();

/// Matches the word "Relic" as it appears on a card's TYPE line (e.g. "Homodeus
/// Relic - Ally", "Prism Relic - Champion").
final RegExp _relicTypeLine = RegExp(r'\bRelic\b');

/// True if [r] is a Relic card. PRIMARY: its id is in the authoritative
/// [_relicCardIds] set. FALLBACK: its card-TYPE line (the first sentence/line of
/// `rawText`, before any effect text) is flagged a Relic — so a card that merely
/// mentions "relic" in flavor or reward text (e.g. an Ingeminex co-op card) is
/// NOT mistaken for one.
bool _isRelic(CardRecord r) {
  if (_relicCardIds.contains(r.id)) return true;
  final raw = r.rawText;
  if (raw == null) return false;
  var typeLine = raw.split('\n').first;
  final sentenceBreak = typeLine.indexOf('. ');
  if (sentenceBreak >= 0) typeLine = typeLine.substring(0, sentenceBreak);
  return _relicTypeLine.hasMatch(typeLine);
}

/// True for co-op/enemy boss & minion cards: `faction == none` AND a `group`
/// that is neither a playable non-faction supply (Aion/Prism) nor the Destiny
/// supply (Destiny/DestinyDeck). These are hidden from the catalog.
bool _isCoopEnemy(CardRecord r) {
  if (r.model.faction != Faction.none) return false;
  final g = r.group;
  return g != 'Aion' && g != 'Prism' && g != 'Destiny' && g != 'DestinyDeck';
}

_Bucket _bucketOf(CardRecord r) {
  if (r.group == 'Aion') return _Bucket.aion;
  if (r.group == 'Prism') return _Bucket.prism;
  if (r.group == 'Destiny' || r.group == 'DestinyDeck') return _Bucket.destiny;
  switch (r.model.faction) {
    case Faction.order:
      return _Bucket.order;
    case Faction.undergrowth:
      return _Bucket.undergrowth;
    case Faction.homodeus:
      return _Bucket.homodeus;
    case Faction.wraethe:
      return _Bucket.wraethe;
    case Faction.none:
      // Unreachable: every `faction == none` card is either an Aion/Prism/Destiny
      // group (handled above) or a co-op/enemy card filtered out by [_isCoopEnemy]
      // before bucketing.
      throw StateError('Unbucketable faction-none card: ${r.id}');
  }
}

String _bucketLabel(_Bucket b) {
  switch (b) {
    case _Bucket.aion:
      return 'Aion';
    case _Bucket.prism:
      return 'Prism';
    case _Bucket.order:
      return 'Order';
    case _Bucket.undergrowth:
      return 'Undergrowth';
    case _Bucket.homodeus:
      return 'Homodeus';
    case _Bucket.wraethe:
      return 'Wraethe';
    case _Bucket.destiny:
      return 'Destiny';
  }
}

/// Accent colour for a bucket's section header. The four factions reuse their
/// palette; Aion/Prism/Destiny get distinct non-faction accents.
Color _bucketColor(_Bucket b) {
  switch (b) {
    case _Bucket.aion:
      return GameTheme.gemCyan;
    case _Bucket.prism:
      return GameTheme.accent;
    case _Bucket.order:
      return FactionColors.getPrimary(Faction.order);
    case _Bucket.undergrowth:
      return FactionColors.getPrimary(Faction.undergrowth);
    case _Bucket.homodeus:
      return FactionColors.getPrimary(Faction.homodeus);
    case _Bucket.wraethe:
      return FactionColors.getPrimary(Faction.wraethe);
    case _Bucket.destiny:
      return GameTheme.gold;
  }
}

/// A whole scrollable catalog of EVERY card in the authoritative database,
/// grouped by faction/group bucket (see [_Bucket]) and sub-sorted by cost.
/// Includes a live name/text search and a bucket filter.
///
/// Reachable from the setup lobby's CARD LIST button and via `?cards=1`.
class CardListScreen extends StatefulWidget {
  const CardListScreen({super.key});

  @override
  State<CardListScreen> createState() => _CardListScreenState();
}

class _CardListScreenState extends State<CardListScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Loaded database. Null while loading; [_loadError] flips true on failure.
  CardDatabase? _db;
  bool _loadError = false;

  String _search = '';

  /// Active bucket filter; null == "All".
  _Bucket? _filter;

  @override
  void initState() {
    super.initState();
    CardDatabaseAsset.load().then((db) {
      if (mounted) setState(() => _db = db);
    }).catchError((_) {
      if (mounted) setState(() => _loadError = true);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Records passing the current search + filter, grouped by bucket in display
  /// order and sub-sorted by cost ascending (then name for stability). Empty
  /// buckets are omitted entirely.
  List<MapEntry<_Bucket, List<CardRecord>>> _groupedResults(CardDatabase db) {
    final query = _search.trim().toLowerCase();
    final byBucket = <_Bucket, List<CardRecord>>{};
    for (final r in db.records) {
      // Hide co-op/enemy cards and all relics entirely — filtered here, before
      // bucketing and searching, so the list, section grouping and filter
      // dropdown all see the same set.
      if (_isCoopEnemy(r) || _isRelic(r)) continue;
      final bucket = _bucketOf(r);
      if (_filter != null && bucket != _filter) continue;
      if (query.isNotEmpty) {
        final name = r.name.toLowerCase();
        final rawText = r.rawText?.toLowerCase() ?? '';
        if (!name.contains(query) && !rawText.contains(query)) continue;
      }
      byBucket.putIfAbsent(bucket, () => <CardRecord>[]).add(r);
    }
    final result = <MapEntry<_Bucket, List<CardRecord>>>[];
    for (final bucket in _Bucket.values) {
      final cards = byBucket[bucket];
      if (cards == null || cards.isEmpty) continue;
      cards.sort((a, b) {
        final byCost = a.model.cost.compareTo(b.model.cost);
        return byCost != 0 ? byCost : a.name.compareTo(b.name);
      });
      result.add(MapEntry(bucket, cards));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.boardBackground,
      appBar: AppBar(
        backgroundColor: GameTheme.surfaceDark,
        foregroundColor: GameTheme.textPrimary,
        title: const Text(
          'CARD LIST',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: Responsive.maxContentWidth),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Could not load the card database.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GameTheme.textSecondary, fontSize: 15),
          ),
        ),
      );
    }
    final db = _db;
    if (db == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = _groupedResults(db);

    return Column(
      children: [
        _buildControls(),
        Expanded(
          child: grouped.isEmpty
              ? const _EmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    for (final entry in grouped) ...[
                      _BucketHeader(
                        bucket: entry.key,
                        count: entry.value.length,
                      ),
                      for (final record in entry.value)
                        _CardRow(record: record),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          TextField(
            key: const ValueKey('cardListSearchField'),
            controller: _searchController,
            style: const TextStyle(color: GameTheme.textPrimary),
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              hintText: 'Search cards…',
              hintStyle: const TextStyle(color: GameTheme.textSecondary),
              prefixIcon:
                  const Icon(Icons.search, color: GameTheme.textSecondary),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('cardListSearchClear'),
                      icon: const Icon(Icons.clear,
                          color: GameTheme.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                    ),
              filled: true,
              fillColor: GameTheme.surfaceDark,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: GameTheme.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.filter_list,
                  color: GameTheme.textSecondary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: GameTheme.surfaceDark,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: DropdownButton<_Bucket?>(
                    key: const ValueKey('cardListFilter'),
                    value: _filter,
                    isExpanded: true,
                    dropdownColor: GameTheme.surfaceDark,
                    underline: const SizedBox.shrink(),
                    iconEnabledColor: GameTheme.gold,
                    style: const TextStyle(
                      color: GameTheme.textPrimary,
                      fontSize: 14,
                    ),
                    items: <DropdownMenuItem<_Bucket?>>[
                      const DropdownMenuItem<_Bucket?>(
                        value: null,
                        child: Text('All factions'),
                      ),
                      for (final bucket in _Bucket.values)
                        DropdownMenuItem<_Bucket?>(
                          value: bucket,
                          child: Text(_bucketLabel(bucket)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _filter = value),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Message shown when no cards match the current search + filter.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: GameTheme.textSecondary, size: 40),
            SizedBox(height: 12),
            Text(
              'No cards match your search.',
              textAlign: TextAlign.center,
              style: TextStyle(color: GameTheme.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section header naming a bucket and its card count.
class _BucketHeader extends StatelessWidget {
  const _BucketHeader({required this.bucket, required this.count});

  final _Bucket bucket;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = _bucketColor(bucket);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _bucketLabel(bucket).toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: const TextStyle(
              color: GameTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single card entry: art thumbnail, name, type/group subtitle, cost badge.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.record});

  final CardRecord record;

  String get _subtitle {
    final parts = <String>[];
    switch (record.model.cardType) {
      case CardType.champion:
        parts.add('Champion');
      case CardType.mercenary:
        parts.add('Mercenary');
      case CardType.regular:
        break;
    }
    // Show the source group when it adds info beyond the bucket label. The
    // Aion/Prism/Destiny groups match their own bucket header, so listing them
    // again would be redundant (co-op/enemy groups are filtered out of the list
    // entirely, so they never reach here).
    final group = record.group;
    if (group != null &&
        group != 'Aion' &&
        group != 'Prism' &&
        group != 'Destiny' &&
        group != 'DestinyDeck') {
      parts.add(group);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: GameTheme.surfaceDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _Thumb(record: record),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.name,
                  style: const TextStyle(
                    color: GameTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: GameTheme.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CostBadge(cost: record.model.cost),
        ],
      ),
    );
  }
}

/// Small rounded art thumbnail, mirroring the board's art-resolution order
/// (DB `art` path → name→file map → procedural fallback).
class _Thumb extends StatelessWidget {
  const _Thumb({required this.record});

  final CardRecord record;

  @override
  Widget build(BuildContext context) {
    final art = record.art;
    final assetPath = (art != null && art.isNotEmpty)
        ? 'assets/cards/$art'
        : getCardArtAsset(record.name);
    final Widget image = assetPath != null
        ? Image.asset(
            assetPath,
            width: 44,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => CardArt(card: record.model),
          )
        : CardArt(card: record.model);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(width: 44, height: 60, child: image),
    );
  }
}

/// A gold-ringed cost badge.
class _CostBadge extends StatelessWidget {
  const _CostBadge({required this.cost});

  final int cost;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GameTheme.boardBackground,
        shape: BoxShape.circle,
        border: Border.all(color: GameTheme.gold, width: 1.5),
      ),
      child: Text(
        '$cost',
        style: const TextStyle(
          color: GameTheme.gold,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
