import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/models/price_link.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/providers/household_provider.dart';
import 'package:groceries_app/providers/items_provider.dart';
import 'package:groceries_app/providers/price_provider.dart';
import 'package:groceries_app/screens/shopping_list/compare_prices_screen.dart';
import 'package:groceries_app/services/price/auto_match.dart';
import 'package:groceries_app/services/price/price_compare.dart';
import 'package:groceries_app/services/price/price_fetch_exception.dart';
import 'package:groceries_app/services/price/price_links_service.dart';
import 'package:groceries_app/services/price/price_search_service.dart';

import '../../services/price/price_test_support.dart';

/// A controller that starts with a ready-made state (no fetch).
class _Seeded extends PriceCompareController {
  _Seeded(super.ref, PriceCompareState seed) {
    state = seed;
  }
}

final _now = DateTime(2026, 10, 31, 12);

void main() {
  late FakeFirebaseFirestore db;
  late FakeAsdaSearch asda;
  late FakeCostcoSearch costco;
  late ProviderContainer container;

  setUp(() {
    db = FakeFirebaseFirestore();
    asda = FakeAsdaSearch();
    costco = FakeCostcoSearch();
  });

  PriceCompareState st() => container.read(priceCompareControllerProvider);
  int searches() => asda.calls.length + costco.calls.length;

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<ShoppingItem> items,
    PriceCompareState? seed,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => ComparePricesScreen(clock: () => _now),
        ),
        GoRoute(
          path: '/settings/price-lab',
          builder: (_, __) => const Scaffold(body: Text('PRICE LAB PAGE')),
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        householdIdProvider.overrideWith((ref) async => 'h1'),
        itemsProvider.overrideWith((ref) => Stream.value(items)),
        priceLinksServiceProvider.overrideWithValue(PriceLinksService(db: db)),
        asdaSearchProvider.overrideWithValue(asda),
        costcoSearchProvider.overrideWithValue(costco),
        if (seed != null)
          priceCompareControllerProvider.overrideWith(
            (ref) => _Seeded(ref, seed),
          ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData.dark(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }
  }

  List<ShoppingItem> fixtureBasket() => [
    for (final t in fixtureTerms.keys) shoppingItem(t),
  ];

  PriceProduct prod(
    String id,
    double price, {
    PriceStore store = PriceStore.asda,
    PackQuantity? q,
    bool stale = false,
    String? offer,
  }) => PriceProduct(
    store: store,
    id: id,
    name: 'Product $id',
    price: price,
    quantity: q,
    offer: offer,
    stale: stale,
    fetchedAt: fixtureFetched,
  );

  PriceLink linkOf(
    String key, {
    List<PriceProduct> asda = const [],
    List<PriceProduct> costco = const [],
    bool confirmed = false,
  }) => PriceLink(
    itemKey: key,
    asda: asda,
    costco: costco,
    userConfirmed: confirmed,
    updatedAt: fixtureFetched,
  );

  PriceRunResult runOf(
    List<CompareLine> lines, {
    Map<String, AutoMatchResult> auto = const {},
    Map<PriceStore, String> storeErrors = const {},
  }) => PriceRunResult(
    result: compareBasket(lines),
    auto: auto,
    storeErrors: storeErrors,
    effectiveLinks: {for (final l in lines) l.link!.itemKey: l.link!},
    fees: const PriceFees(),
  );

  PriceCompareState seedOf(PriceRunResult r, Duration age) =>
      PriceCompareState(last: r, lastRunAt: _now.subtract(age));

  Finder row(String key) => find.byKey(ValueKey('compare-row-$key'));

  group('running', () {
    testWidgets('auto-runs when there is no result and shows progress', (
      tester,
    ) async {
      final gate = Completer<void>();
      asda.gate = () => gate.future;
      await pumpScreen(tester, items: fixtureBasket(), settle: false);

      expect(st().running, isTrue);
      expect(find.byKey(const ValueKey('compare-progress')), findsOneWidget);
      expect(find.textContaining('Checking prices… 0/12 · '), findsOneWidget);
      // Refresh is disabled while running.
      final refresh = tester.widget<IconButton>(
        find.byKey(const ValueKey('compare-refresh')),
      );
      expect(refresh.onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(st().running, isFalse);
      expect(st().last, isNotNull);
      expect(find.byKey(const ValueKey('compare-progress')), findsNothing);
      expect(find.text('Order from both'), findsOneWidget);
      expect(find.text('Updated just now'), findsOneWidget);
    });

    testWidgets('a fresh result is shown without re-running', (tester) async {
      final run = runOf([
        CompareLine(
          itemName: 'milk',
          link: linkOf('milk', asda: [prod('m', 1.5)]),
        ),
      ]);
      await pumpScreen(
        tester,
        items: [shoppingItem('milk')],
        seed: seedOf(run, const Duration(minutes: 10)),
      );
      expect(searches(), 0);
      expect(find.text('Updated 10 min ago'), findsOneWidget);
      expect(row('milk'), findsOneWidget);
    });

    testWidgets('a result older than 6h triggers a re-run', (tester) async {
      final run = runOf([
        CompareLine(
          itemName: 'milk',
          link: linkOf('milk', asda: [prod('m', 1.5)]),
        ),
      ]);
      await pumpScreen(
        tester,
        items: [shoppingItem('milk')],
        seed: seedOf(run, const Duration(hours: 7)),
      );
      expect(searches(), greaterThan(0));
      expect(st().running, isFalse);
    });

    testWidgets('refresh button re-runs the comparison', (tester) async {
      final run = runOf([
        CompareLine(
          itemName: 'milk',
          link: linkOf('milk', asda: [prod('m', 1.5)]),
        ),
      ]);
      await pumpScreen(
        tester,
        items: [shoppingItem('milk')],
        seed: seedOf(run, const Duration(minutes: 1)),
      );
      expect(searches(), 0);
      await tester.tap(find.byKey(const ValueKey('compare-refresh')));
      await tester.pumpAndSettle();
      expect(searches(), greaterThan(0));
    });

    testWidgets('empty shopping list shows the empty state, no run', (
      tester,
    ) async {
      await pumpScreen(tester, items: const []);
      expect(
        find.text('Add items to your list to compare prices'),
        findsOneWidget,
      );
      expect(searches(), 0);
      expect(st().last, isNull);
      final refresh = tester.widget<IconButton>(
        find.byKey(const ValueKey('compare-refresh')),
      );
      expect(refresh.onPressed, isNull);
    });
  });

  group('result', () {
    testWidgets('split from the fixture basket', (tester) async {
      await pumpScreen(tester, items: fixtureBasket());
      expect(st().last!.result.recommendation, Recommendation.split);

      expect(find.text('Order from both'), findsOneWidget);
      expect(find.textContaining('Costco · 3 items · £'), findsOneWidget);
      expect(find.textContaining('+ £5.99 delivery'), findsOneWidget);
      expect(find.textContaining('Asda · 9 items · £'), findsOneWidget);
      expect(find.textContaining('+ £6.00 delivery'), findsOneWidget);
      expect(find.text('Net saving £12.23'), findsOneWidget);
      expect(
        find.textContaining('Order 3 items from Costco: saves £18.22'),
        findsOneWidget,
      );

      expect(find.text('From Costco (3)'), findsOneWidget);
      expect(find.text('From Asda (9)'), findsOneWidget);
      expect(find.textContaining("Couldn't price"), findsNothing);
      for (final name in ['olive oil', 'toilet roll', 'chopped tomatoes']) {
        expect(row(name), findsOneWidget);
      }
      for (final name in ['milk', 'cereal', 'tea bags', 'kitchen roll']) {
        expect(row(name), findsOneWidget);
      }
      // Costco row detail.
      expect(find.text('saves £12.01 vs 5 × Asda £7.00'), findsOneWidget);
      expect(find.textContaining('£4.60/L'), findsOneWidget);
    });

    testWidgets('asda only', (tester) async {
      await pumpScreen(
        tester,
        items: [shoppingItem('milk'), shoppingItem('kitchen roll')],
      );
      expect(st().last!.result.recommendation, Recommendation.asdaOnly);
      expect(find.text('Just order from Asda'), findsOneWidget);
      expect(find.textContaining('Asda · 2 items · £'), findsOneWidget);
      expect(find.text('From Asda (2)'), findsOneWidget);
      expect(find.textContaining('From Costco'), findsNothing);
      expect(
        find.textContaining(
          RegExp(
            'Costco would save only|No Costco matches|'
            'Costco is not cheaper',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('row details, chips and the unpriced section', (tester) async {
      final rice = linkOf(
        'rice',
        asda: [prod('a', 5, q: const PackQuantity(grams: 1000))],
        costco: [
          prod(
            'c',
            22,
            store: PriceStore.costco,
            q: const PackQuantity(grams: 5000),
          ),
        ],
        confirmed: true,
      );
      final milk = linkOf(
        'milk',
        asda: [
          prod(
            'm',
            1.5,
            stale: true,
            offer: 'Rollback',
            q: const PackQuantity(millilitres: 2000),
          ),
        ],
      );
      final run = runOf(
        [
          CompareLine(itemName: 'rice', qty: 3, link: rice),
          CompareLine(itemName: 'milk', link: milk),
          CompareLine(itemName: 'mystery', link: linkOf('mystery')),
        ],
        auto: {
          'milk': AutoMatchResult(
            link: milk,
            asdaConfidence: MatchConfidence.low,
            costcoConfidence: MatchConfidence.none,
          ),
        },
      );
      await pumpScreen(
        tester,
        items: [shoppingItem('rice')],
        seed: seedOf(run, const Duration(minutes: 1)),
      );

      expect(find.text('Order from both'), findsOneWidget);
      expect(find.text('1 item couldn\'t be priced'), findsOneWidget);
      expect(find.text('From Costco (1)'), findsOneWidget);
      expect(find.text('From Asda (1)'), findsOneWidget);
      expect(find.text("Couldn't price (1)"), findsOneWidget);

      expect(find.text('rice × 3'), findsOneWidget);
      expect(find.text('3 × £22.00 = £66.00 · £4.40/kg'), findsOneWidget);
      expect(find.text('saves £9.00 vs 15 × Asda £5.00'), findsOneWidget);
      expect(find.text('your pick'), findsOneWidget);

      expect(find.text('£1.50 · £0.75/L'), findsOneWidget);
      expect(find.text('Rollback'), findsOneWidget);
      expect(find.text('may be out of date'), findsOneWidget);
      expect(find.text('check match'), findsOneWidget);

      expect(find.text('No Asda match · no Costco match'), findsOneWidget);
    });
  });

  group('store errors', () {
    testWidgets('asda error banner offers the Price lab and navigates', (
      tester,
    ) async {
      asda.failWith = asdaTimeout;
      await pumpScreen(tester, items: [shoppingItem('olive oil')]);
      expect(st().last!.storeErrors.keys, [PriceStore.asda]);

      expect(find.byKey(const ValueKey('store-error-asda')), findsOneWidget);
      expect(
        find.textContaining("Asda didn't respond. Open the Price lab once"),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('open-price-lab')));
      await tester.pumpAndSettle();
      expect(find.text('PRICE LAB PAGE'), findsOneWidget);
    });

    testWidgets('costco error banner has no Price lab button', (tester) async {
      costco.failWith = const PriceFetchException(
        PriceStore.costco,
        'Costco timed out',
      );
      await pumpScreen(tester, items: [shoppingItem('olive oil')]);
      expect(find.byKey(const ValueKey('store-error-costco')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-price-lab')), findsNothing);
    });
  });

  group('delivery fees', () {
    testWidgets('validates, saves and recomputes without new searches', (
      tester,
    ) async {
      await pumpScreen(tester, items: fixtureBasket());
      final calls = searches();
      expect(find.textContaining('+ £5.99 delivery'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('compare-fees')));
      await tester.pumpAndSettle();
      expect(find.text('Delivery fees'), findsOneWidget);
      // Prefilled with the current fees.
      expect(find.widgetWithText(TextFormField, '6.00'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '5.99'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('fee-asda')), 'abc');
      await tester.enterText(find.byKey(const ValueKey('fee-costco')), '60');
      await tester.tap(find.byKey(const ValueKey('fee-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount'), findsOneWidget);
      expect(find.text('Between £0 and £50'), findsOneWidget);
      expect(find.text('Delivery fees'), findsOneWidget);
      expect(
        (await db.doc('households/h1/config/priceSettings').get()).exists,
        isFalse,
      );

      await tester.enterText(find.byKey(const ValueKey('fee-asda')), '3');
      await tester.enterText(find.byKey(const ValueKey('fee-costco')), '1,5');
      await tester.tap(find.byKey(const ValueKey('fee-save')));
      await tester.pumpAndSettle();

      expect(find.text('Delivery fees'), findsNothing);
      final saved = (await db.doc('households/h1/config/priceSettings').get())
          .data()!;
      expect(saved['asdaDelivery'], 3);
      expect(saved['costcoDelivery'], 1.5);
      expect(find.textContaining('+ £1.50 delivery'), findsOneWidget);
      expect(find.textContaining('+ £3.00 delivery'), findsOneWidget);
      expect(find.textContaining('+ £5.99 delivery'), findsNothing);
      expect(st().last!.fees.costcoDelivery, 1.5);
      expect(searches(), calls);
    });

    testWidgets('cancel leaves fees untouched', (tester) async {
      await pumpScreen(tester, items: fixtureBasket());
      await tester.tap(find.byKey(const ValueKey('compare-fees')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('+ £5.99 delivery'), findsOneWidget);
      expect(
        (await db.doc('households/h1/config/priceSettings').get()).exists,
        isFalse,
      );
    });
  });

  group('match sheet', () {
    Finder tiles() => find.byType(CheckboxListTile);
    List<CheckboxListTile> tileWidgets(WidgetTester t) =>
        t.widgetList<CheckboxListTile>(tiles()).toList();
    Set<String> checkedNames(WidgetTester t) => {
      for (final w in tileWidgets(t))
        if (w.value ?? false) (w.title! as Text).data!,
    };

    Future<void> openOil(WidgetTester tester) async {
      await tester.tap(row('olive oil'));
      await tester.pumpAndSettle();
    }

    Future<void> saveSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('match-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('opens with the current Asda picks pre-checked', (
      tester,
    ) async {
      await pumpScreen(tester, items: [shoppingItem('olive oil')]);
      final link = st().last!.effectiveLinks['olive oil']!;
      await openOil(tester);

      expect(
        find.byKey(const ValueKey('match-store-segments')),
        findsOneWidget,
      );
      expect(find.text('Not sold here'), findsOneWidget);
      expect(find.text('Search for something else'), findsOneWidget);
      expect(link.asda, isNotEmpty);
      expect(checkedNames(tester), {for (final p in link.asda) p.name});
      expect(tileWidgets(tester).length, greaterThan(link.asda.length - 1));
      // Not user-confirmed yet: no reset button.
      expect(find.byKey(const ValueKey('match-reset')), findsNothing);
    });

    testWidgets('switching segment shows the Costco picks', (tester) async {
      await pumpScreen(tester, items: [shoppingItem('olive oil')]);
      final link = st().last!.effectiveLinks['olive oil']!;
      await openOil(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('match-store-segments')),
          matching: find.text('Costco'),
        ),
      );
      await tester.pumpAndSettle();
      expect(checkedNames(tester), {for (final p in link.costco) p.name});
    });

    testWidgets('picking one product saves an exact link', (tester) async {
      await pumpScreen(tester, items: [shoppingItem('olive oil')]);
      final link = st().last!.effectiveLinks['olive oil']!;
      await openOil(tester);

      // Uncheck everything, then check exactly one other product.
      for (final t in tileWidgets(tester).where((w) => w.value ?? false)) {
        await tester.tap(
          find.widgetWithText(CheckboxListTile, (t.title! as Text).data!),
        );
      }
      await tester.pump();
      final other = tileWidgets(tester).firstWhere(
        (w) => !link.asda.any((p) => p.name == (w.title! as Text).data),
      );
      final otherName = (other.title! as Text).data!;
      await tester.tap(find.widgetWithText(CheckboxListTile, otherName));
      await tester.pump();
      expect(checkedNames(tester), {otherName});
      // Costco's own auto picks would make the link any-of; drop that store.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('match-store-segments')),
          matching: find.text('Costco'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('match-unavailable-costco')));
      await tester.pump();
      await saveSheet(tester);

      expect(find.byType(CheckboxListTile), findsNothing, reason: 'closed');
      final saved = st().last!.effectiveLinks['olive oil']!;
      expect(saved.userConfirmed, isTrue);
      expect(saved.mode, LinkMode.exact);
      expect(saved.asda.single.name, otherName);
      expect(saved.asdaUnavailable, isFalse);
      // Persisted.
      final doc = await db.doc('households/h1/config/priceLinks').get();
      final stored = (doc.data()!['links'] as Map)['olive oil'] as Map;
      expect(stored['userConfirmed'], isTrue);
      expect(stored['mode'], 'exact');
      // The row now says it's the user's pick.
      expect(find.text('your pick'), findsOneWidget);
    });

    testWidgets('checking several products saves an any-of link', (
      tester,
    ) async {
      await pumpScreen(tester, items: [shoppingItem('olive oil')]);
      final link = st().last!.effectiveLinks['olive oil']!;
      await openOil(tester);
      final extra = tileWidgets(tester).firstWhere((w) => !(w.value ?? false));
      await tester.tap(
        find.widgetWithText(CheckboxListTile, (extra.title! as Text).data!),
      );
      await tester.pump();
      await saveSheet(tester);

      final saved = st().last!.effectiveLinks['olive oil']!;
      expect(saved.mode, LinkMode.anyOf);
      expect(saved.asda.length, link.asda.length + 1);
    });

    testWidgets('"Not sold here" maps to the unavailable flag', (tester) async {
      await pumpScreen(tester, items: [shoppingItem('olive oil')]);
      await openOil(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('match-store-segments')),
          matching: find.text('Costco'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('match-unavailable-costco')));
      await tester.pump();
      await saveSheet(tester);

      final saved = st().last!.effectiveLinks['olive oil']!;
      expect(saved.costcoUnavailable, isTrue);
      expect(saved.costco, isEmpty);
      expect(saved.asdaUnavailable, isFalse);
      expect(saved.asda, isNotEmpty);
      expect(st().last!.result.lines.single.status, LineStatus.asdaOnly);
    });

    testWidgets('reset only shows for confirmed links and restores auto', (
      tester,
    ) async {
      await pumpScreen(tester, items: [shoppingItem('olive oil')]);
      final auto = st().last!.auto['olive oil']!.link;
      await openOil(tester);
      expect(find.byKey(const ValueKey('match-reset')), findsNothing);
      await saveSheet(tester);
      expect(st().last!.effectiveLinks['olive oil']!.userConfirmed, isTrue);

      await openOil(tester);
      expect(find.byKey(const ValueKey('match-reset')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('match-reset')));
      await tester.pumpAndSettle();

      final doc = await db.doc('households/h1/config/priceLinks').get();
      expect(doc.data()!['links'], isEmpty);
      expect(st().last!.effectiveLinks['olive oil'], same(auto));
      expect(find.text('your pick'), findsNothing);
    });

    testWidgets('search for something else re-queries the store', (
      tester,
    ) async {
      await pumpScreen(tester, items: [shoppingItem('olive oil')]);
      await openOil(tester);
      final before = asda.calls.length;
      await tester.tap(find.text('Search for something else'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'milk');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(asda.calls.length, before + 1);
      expect(asda.calls.last, 'milk');
      expect(find.textContaining('milk', findRichText: true), findsWidgets);
    });
  });
}
