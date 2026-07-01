import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/data/card_art_map.dart';
import 'package:simple_card_game/ui/screens/card_list_screen.dart';
import 'package:simple_card_game/ui/widgets/card_detail_modal.dart';
import 'package:simple_card_game/ui/widgets/game_card_widget.dart';

/// A narrow / portrait viewport (mobile portrait) → expects a 3-column grid.
const _narrowPortrait = Size(402, 800);

/// A wide / landscape viewport (desktop / mobile landscape) → 5-column grid.
const _wideLandscape = Size(1000, 600);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Warm the rootBundle asset cache (rootBundle caches loadString by key) so
    // the screen's initState DB load resolves deterministically in every test,
    // rather than racing the fake-async clock differently run to run.
    await rootBundle.loadString('assets/card_db/cards.json');
  });

  // The grid's inter-tile gutter + the ListView's horizontal padding, kept in
  // sync with card_list_screen.dart so the expected tile width can be derived
  // from the measured list width (rather than hard-coding a device size).
  const gutter = 8.0;
  const horizontalPadding = 24.0;

  double expectedTileWidth(double listWidth, int columns) =>
      ((listWidth - horizontalPadding - gutter * (columns - 1)) / columns)
          .floorToDouble();

  Future<void> pumpList(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: CardListScreen()));
    // The screen loads the card database in initState via a real-async
    // rootBundle read, which the test's fake-async clock can't advance (and
    // load() doesn't cache, so warming a separate copy doesn't complete the
    // widget's own future). Drive the widget's load to completion on the real
    // event loop, pumping between turns, until the grid populates — bounded so
    // a genuine failure still terminates rather than hangs. We avoid
    // pumpAndSettle: the grid tiles load real JPEG art (real async that never
    // resolves under fake-async), which would make pumpAndSettle spin forever.
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.byType(GameCardWidget).evaluate().isNotEmpty) break;
    }
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('cardListSearchField')),
      text,
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders cards as a GameCardWidget grid, not a text list',
      (tester) async {
    await pumpList(tester, size: _narrowPortrait);
    // The catalog now renders card faces (icons), so there should be many tiles.
    expect(find.byType(GameCardWidget), findsWidgets);
  });

  testWidgets('narrow / portrait layout lays cards out in 3 columns',
      (tester) async {
    await pumpList(tester, size: _narrowPortrait);

    final listWidth = tester.getSize(find.byType(ListView)).width;
    final tileWidth = tester.getSize(find.byType(GameCardWidget).first).width;

    // The tile width matches a 3-column division of the list width...
    expect(tileWidth, expectedTileWidth(listWidth, 3));
    // ...and NOT a 5-column division (proving it chose 3, not 5).
    expect(tileWidth, isNot(expectedTileWidth(listWidth, 5)));
  });

  testWidgets('wide / landscape layout lays cards out in 5 columns',
      (tester) async {
    await pumpList(tester, size: _wideLandscape);

    final listWidth = tester.getSize(find.byType(ListView)).width;
    final tileWidth = tester.getSize(find.byType(GameCardWidget).first).width;

    expect(tileWidth, expectedTileWidth(listWidth, 5));
    expect(tileWidth, isNot(expectedTileWidth(listWidth, 3)));
  });

  testWidgets('tapping a card icon opens the in-game zoom detail modal',
      (tester) async {
    await pumpList(tester, size: _wideLandscape);

    final tileFinder = find.byType(GameCardWidget).first;
    final tappedId = (tester.widget<GameCardWidget>(tileFinder)).card.id;

    await tester.tap(tileFinder);
    // Advance past the modal's fixed 140ms open transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The SAME widget the board uses (CardDetailModal), showing the tapped card.
    expect(find.byType(CardDetailModal), findsOneWidget);
    expect(find.byKey(ValueKey('detail_$tappedId')), findsOneWidget);
  });

  testWidgets('search still filters the grid and preserves faction grouping',
      (tester) async {
    await pumpList(tester, size: _narrowPortrait);

    await search(tester, 'skirmisher');

    // Only Wraethe Skirmisher matches → exactly one tile, under the WRAETHE
    // section header (grouping preserved).
    expect(find.byType(GameCardWidget), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cardListTile_wraethe_skirmisher')),
      findsOneWidget,
    );
    expect(find.text('WRAETHE'), findsOneWidget);
  });

  testWidgets('faction relics are now listed under their faction (not hidden)',
      (tester) async {
    await pumpList(tester, size: _narrowPortrait);

    // "The World Piercer" is a Wraethe Relic (faction: wraethe). Previously all
    // relics were hidden; it must now appear in the Wraethe section.
    await search(tester, 'piercer');

    expect(
      find.byKey(const ValueKey('cardListTile_the_world_piercer')),
      findsOneWidget,
    );
    expect(find.text('WRAETHE'), findsOneWidget);
  });

  testWidgets('Wraethe Skirmisher art resolves to its asset in the grid',
      (tester) async {
    await pumpList(tester, size: _narrowPortrait);
    await search(tester, 'skirmisher');

    // The tile renders the DB-art asset (assets/cards/wraethe_skirmisher.jpg)
    // rather than falling back to procedural art.
    final artFinder = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName ==
              'assets/cards/wraethe_skirmisher.jpg',
    );
    expect(artFinder, findsOneWidget);
  });

  test('getCardArtAsset resolves Wraethe Skirmisher by name (fallback map fix)',
      () {
    // The name-based fallback now knows wraethe_skirmisher.jpg, so a card named
    // "Wraethe Skirmisher" resolves even without an explicit DB art path.
    expect(
      getCardArtAsset('Wraethe Skirmisher'),
      'assets/cards/wraethe_skirmisher.jpg',
    );
  });
}
