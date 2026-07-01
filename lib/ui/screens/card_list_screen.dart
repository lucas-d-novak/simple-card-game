import 'package:flutter/material.dart';
import 'package:simple_card_game/data/database/card_database.dart';
import 'package:simple_card_game/data/database/card_database_asset.dart';
import 'package:simple_card_game/models/card_model.dart';
import 'package:simple_card_game/models/faction.dart';
import 'package:simple_card_game/ui/theme/faction_colors.dart';
import 'package:simple_card_game/ui/theme/game_theme.dart';
import 'package:simple_card_game/ui/theme/responsive.dart';
import 'package:simple_card_game/ui/widgets/card_detail_modal.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// A derived faction/group bucket used to GROUP and ORDER the card list.
///
/// The engine's [Faction] enum only models the four playable factions (plus
/// [Faction.none]); "Aion" and "Prism" are NOT factions — they live in the
/// database `group` field with `faction == none`. So the bucket is a DERIVED
/// key: Aion/Prism come from `group`, the four factions from the enum, and the
/// Into-the-Horizon Destiny supply (`group` == 'Destiny'/'DestinyDeck') gets its
/// own [destiny] bucket.
///
/// Only ONE family is hidden from the catalog entirely BEFORE bucketing (see
/// [_isCoopEnemy]) and therefore never reaches [_bucketOf]:
/// - the co-op/enemy boss & minion groups (`faction == none` with a non-Aion/
///   Prism/Destiny `group` — Vox, Dominatus, Ingeminex, …).
///
/// Relic cards ARE listed (they carry their owning `faction`, or the Aion/Prism
/// `group`, so they bucket naturally): a faction's Mastery-10 relics appear under
/// that faction, sub-sorted by cost like every other card. Relics with no real
/// faction/group (`faction == none`, boss-scoped) are still caught by
/// [_isCoopEnemy]. Enum order == display order: Aion, Prism, Order, Undergrowth,
/// Homodeus, Wraethe, Destiny.
enum _Bucket {
  aion,
  prism,
  order,
  undergrowth,
  homodeus,
  wraethe,
  destiny,
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
      // Hide only co-op/enemy cards — filtered here, before bucketing and
      // searching, so the list, section grouping and filter dropdown all see the
      // same set. Relics are NOT hidden: they carry a real faction/group and so
      // bucket into their owning faction section like any other card.
      if (_isCoopEnemy(r)) continue;
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = _gridColumnCount(constraints);
                    // Available width inside the list's horizontal padding
                    // (12 left + 12 right), minus the inter-tile gutters.
                    const horizontalPadding = 24.0;
                    const gutter = 8.0;
                    final tileWidth = ((constraints.maxWidth -
                                horizontalPadding -
                                gutter * (columns - 1)) /
                            columns)
                        .floorToDouble();
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      children: [
                        for (final entry in grouped) ...[
                          _BucketHeader(
                            bucket: entry.key,
                            count: entry.value.length,
                          ),
                          _CardGrid(
                            records: entry.value,
                            tileWidth: tileWidth,
                            gutter: gutter,
                            onTapCard: _openCardZoom,
                          ),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Responsive column count for the card grid: 3 on narrow / portrait layouts
  /// (mobile portrait) and 5 on landscape or wide layouts (mobile landscape,
  /// tablet, desktop). Driven by the available box — landscape OR a width at/above
  /// the mobile breakpoint gets the wider 5-column grid.
  int _gridColumnCount(BoxConstraints constraints) {
    final landscape = constraints.maxWidth > constraints.maxHeight;
    final wide = constraints.maxWidth >= Responsive.mobileMaxWidth;
    return (landscape || wide) ? 5 : 3;
  }

  /// Opens the SAME zoom/detail view players see in-game (`showCardDetailModal`
  /// from `card_detail_modal.dart`) for the tapped card. [sectionCards] are the
  /// cards in the tapped card's faction section, so the modal's nav chevrons page
  /// through that section. No context action is supplied (the catalog is not a
  /// live game), so the modal shows the card + rules text with no action button.
  void _openCardZoom(List<CardModel> sectionCards, int index) {
    showCardDetailModal(
      context,
      cards: sectionCards,
      initialIndex: index,
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

/// A responsive grid of card icons for one faction section. Each tile is the
/// in-game [GameCardWidget] (its own faction frame + art), so the catalog shows
/// the exact card face players see on the board. Tiles keep the section's
/// cost-sorted order (left-to-right, top-to-bottom). Tapping a tile opens the
/// shared in-game zoom via [onTapCard].
///
/// A [Wrap] lays the fixed-width tiles into as many per row as fit — the caller
/// sizes [tileWidth] from the responsive column count so exactly that many land
/// on each row.
class _CardGrid extends StatelessWidget {
  const _CardGrid({
    required this.records,
    required this.tileWidth,
    required this.gutter,
    required this.onTapCard,
  });

  final List<CardRecord> records;
  final double tileWidth;
  final double gutter;

  /// Called with the section's cards (as [CardModel]s) and the tapped index, so
  /// the zoom modal can page through the whole section.
  final void Function(List<CardModel> sectionCards, int index) onTapCard;

  @override
  Widget build(BuildContext context) {
    final models = [for (final r in records) r.model];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: gutter,
        runSpacing: gutter,
        children: [
          for (var i = 0; i < records.length; i++)
            GameCardWidget(
              key: ValueKey('cardListTile_${records[i].id}'),
              card: models[i],
              width: tileWidth,
              onTap: () => onTapCard(models, i),
            ),
        ],
      ),
    );
  }
}
