import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/providers/household_provider.dart';
import 'package:groceries_app/providers/items_provider.dart';
import 'package:groceries_app/providers/price_provider.dart';
import 'package:groceries_app/services/price/price_compare.dart';
import 'package:groceries_app/services/price/price_search_service.dart';
import 'package:groceries_app/services/price/price_links_service.dart';

import '../services/price/price_test_support.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FakeAsdaSearch asda;
  late FakeCostcoSearch costco;
  late ProviderContainer container;

  ProviderContainer makeContainer(List<ShoppingItem> items) {
    final c = ProviderContainer(
      overrides: [
        householdIdProvider.overrideWith((ref) async => 'h1'),
        itemsProvider.overrideWith((ref) => Stream.value(items)),
        priceLinksServiceProvider.overrideWithValue(PriceLinksService(db: db)),
        asdaSearchProvider.overrideWithValue(asda),
        costcoSearchProvider.overrideWithValue(costco),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    asda = FakeAsdaSearch();
    costco = FakeCostcoSearch();
  });

  PriceCompareController ctrl() =>
      container.read(priceCompareControllerProvider.notifier);
  PriceCompareState st() => container.read(priceCompareControllerProvider);

  Future<void> prime() async {
    // Let the items stream deliver its value.
    await container.read(itemsProvider.future);
  }

  test('compare() fetches, compares and stores the result', () async {
    container = makeContainer([
      shoppingItem('olive oil'),
      shoppingItem('milk', qty: 2),
    ]);
    await prime();
    expect(st().running, isFalse);
    expect(st().last, isNull);

    await ctrl().compare();

    expect(st().running, isFalse);
    expect(st().error, isNull);
    expect(st().last, isNotNull);
    expect(st().lastRunAt, isNotNull);
    expect(st().progress!.phase, PriceRunPhase.done);
    expect(st().last!.result.lines, hasLength(2));
    expect(asda.calls, hasLength(2));
  });

  test('compare() surfaces a store outage in storeErrors, no error', () async {
    asda.failWith = asdaTimeout;
    container = makeContainer([shoppingItem('olive oil')]);
    await prime();
    await ctrl().compare();
    expect(st().error, isNull);
    expect(st().last!.storeErrors.keys, [PriceStore.asda]);
  });

  test('confirmMatch persists and recomputes without new searches', () async {
    container = makeContainer([
      shoppingItem('olive oil'),
      shoppingItem('milk'),
    ]);
    await prime();
    await ctrl().compare();
    final callsAfterRun = asda.calls.length + costco.calls.length;
    final before = st().last!;
    final autoOil = before.effectiveLinks['olive oil']!;
    expect(before.result.lines.first.bestCostco, isNotNull);

    // Pick a specific Asda product only, and say Costco doesn't sell it.
    final pick = (await FakeAsdaSearch().search('olive oil')).last;
    await ctrl().confirmMatch(
      'olive oil',
      asda: [pick],
      costcoUnavailable: true,
    );

    // Persisted, flagged confirmed.
    final doc = await db.doc('households/h1/config/priceLinks').get();
    final saved = (doc.data()!['links'] as Map)['olive oil'] as Map;
    expect(saved['userConfirmed'], isTrue);
    expect(saved['costcoUnavailable'], isTrue);
    expect((saved['asda'] as List).single['id'], pick.id);

    // Recomputed locally.
    final after = st().last!;
    final line = after.result.lines.first;
    expect(line.bestAsda!.id, pick.id);
    expect(line.bestCostco, isNull);
    expect(line.status, LineStatus.asdaOnly);
    expect(after.effectiveLinks['olive oil']!.userConfirmed, isTrue);
    expect(after.effectiveLinks['olive oil'], isNot(same(autoOil)));
    // Untouched item unchanged.
    expect(after.effectiveLinks['milk'], same(before.effectiveLinks['milk']));
    expect(after.auto, same(before.auto));
    expect(st().error, isNull);

    // No new searches.
    expect(asda.calls.length + costco.calls.length, callsAfterRun);

    // The confirmed link now flows through the links provider.
    final links = await container.read(priceLinksProvider.future);
    expect(links.keys, ['olive oil']);
  });

  test(
    'resetMatch removes the stored link and restores the auto-match',
    () async {
      container = makeContainer([shoppingItem('olive oil')]);
      await prime();
      await ctrl().compare();
      final autoLink = st().last!.auto['olive oil']!.link;
      final calls = asda.calls.length + costco.calls.length;

      await ctrl().confirmMatch(
        'olive oil',
        asdaUnavailable: true,
        costcoUnavailable: true,
      );
      expect(st().last!.result.lines.single.status, LineStatus.unavailable);

      await ctrl().resetMatch('olive oil');
      final doc = await db.doc('households/h1/config/priceLinks').get();
      expect((doc.data()!['links'] as Map), isEmpty);
      expect(st().last!.effectiveLinks['olive oil'], same(autoLink));
      expect(st().last!.result.lines.single.status, LineStatus.both);
      expect(asda.calls.length + costco.calls.length, calls);
    },
  );

  test('confirmMatch before any run still saves', () async {
    container = makeContainer([shoppingItem('milk')]);
    await prime();
    await ctrl().confirmMatch('milk', costcoUnavailable: true);
    expect(st().last, isNull);
    expect(st().error, isNull);
    final links = await container.read(priceLinksProvider.future);
    expect(links['milk']!.costcoUnavailable, isTrue);
  });

  test('next compare() uses the confirmed link and saved fees', () async {
    container = makeContainer([shoppingItem('olive oil')]);
    await prime();
    await PriceLinksService(
      db: db,
    ).saveSettings('h1', const PriceFees(asdaDelivery: 1, costcoDelivery: 2));
    final pick = (await FakeAsdaSearch().search('olive oil')).last;
    await ctrl().confirmMatch(
      'olive oil',
      asda: [pick],
      costcoUnavailable: true,
    );
    await ctrl().compare();
    final r = st().last!;
    expect(r.fees.asdaDelivery, 1);
    expect(r.fees.costcoDelivery, 2);
    expect(r.result.lines.single.bestAsda!.id, pick.id);
    expect(costco.calls, isEmpty, reason: 'unavailable store skipped');
  });

  test('compare() while running is ignored', () async {
    container = makeContainer([shoppingItem('milk')]);
    await prime();
    final a = ctrl().compare();
    final b = ctrl().compare();
    await Future.wait([a, b]);
    expect(asda.calls, hasLength(1));
  });
}
