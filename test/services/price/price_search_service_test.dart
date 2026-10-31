import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_link.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/price_compare.dart';
import 'package:groceries_app/services/price/price_search_service.dart';

import 'price_test_support.dart';

const _fees = PriceFees();

void main() {
  late FakeAsdaSearch asda;
  late FakeCostcoSearch costco;
  late DateTime now;
  late PriceSearchService svc;

  setUp(() {
    asda = FakeAsdaSearch();
    costco = FakeCostcoSearch();
    now = DateTime.utc(2026, 10, 31, 12);
    svc = PriceSearchService(asda: asda, costco: costco, clock: () => now);
  });

  Future<List<PriceRunProgress>> run(
    List<String> names, {
    Map<String, PriceLink> confirmed = const {},
    PriceSearchService? service,
  }) => (service ?? svc)
      .run(
        items: [for (final n in names) shoppingItem(n)],
        confirmed: confirmed,
        fees: _fees,
      )
      .toList();

  PriceLink confirmedLink(
    String key, {
    List<PriceProduct> asdaList = const [],
    List<PriceProduct> costcoList = const [],
    bool asdaUnavailable = false,
    bool costcoUnavailable = false,
    LinkMode mode = LinkMode.exact,
  }) => PriceLink(
    itemKey: key,
    mode: mode,
    asda: asdaList,
    costco: costcoList,
    asdaUnavailable: asdaUnavailable,
    costcoUnavailable: costcoUnavailable,
    userConfirmed: true,
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  group('auto path', () {
    test('12 fixture terms produce a split result', () async {
      final events = await run(fixtureTerms.keys.toList());
      final r = events.last.result!;
      expect(r.result.lines, hasLength(12));
      expect(r.result.recommendation, Recommendation.split);
      expect(r.result.splitPlan.costcoLines, isNotEmpty);
      expect(r.result.splitPlan.asdaLines, isNotEmpty);
      expect(r.storeErrors, isEmpty);
      expect(r.auto.keys.toSet(), fixtureTerms.keys.toSet());
      expect(r.effectiveLinks.keys.toSet(), fixtureTerms.keys.toSet());
      expect(
        r.effectiveLinks['olive oil']!.costco,
        isNotEmpty,
        reason: 'olive oil matches Costco',
      );
      expect(r.fees, _fees);
      // Every item searched once per store.
      expect(asda.calls, hasLength(12));
      expect(costco.calls, hasLength(12));
    });

    test('progress is monotonic, ends with a single result event', () async {
      final events = await run(fixtureTerms.keys.toList());
      for (var i = 1; i < events.length; i++) {
        expect(events[i].done, greaterThanOrEqualTo(events[i - 1].done));
      }
      expect(events.first.done, 0);
      expect(events.first.total, 12);
      expect(events.first.currentItem, 'milk');
      expect(events.where((e) => e.result != null), hasLength(1));
      expect(events.last.phase, PriceRunPhase.done);
      expect(events.last.done, 12);
      expect(events[events.length - 2].phase, PriceRunPhase.comparing);
    });

    test('empty list yields a done event with an empty result', () async {
      final events = await run([]);
      expect(events.last.phase, PriceRunPhase.done);
      expect(events.last.result!.result.lines, isEmpty);
      expect(asda.calls, isEmpty);
    });

    test('blank names are ignored', () async {
      final events = await run(['  ', 'milk']);
      expect(events.last.result!.result.lines, hasLength(1));
    });
  });

  group('dedupe', () {
    test(
      'items sharing a key are searched once and quantities summed',
      () async {
        final events = await svc
            .run(
              items: [
                shoppingItem('Milk', qty: 2, id: '1'),
                shoppingItem('  milk ', qty: 3, id: '2'),
                shoppingItem('MILK', qty: 0, id: '3'),
                shoppingItem('cereal', id: '4'),
              ],
              confirmed: const {},
              fees: _fees,
            )
            .toList();
        final lines = events.last.result!.result.lines;
        expect(lines, hasLength(2));
        expect(lines.first.line.itemName, 'Milk');
        expect(lines.first.line.qty, 6, reason: '2 + 3 + (0 counts as 1)');
        expect(asda.calls, hasLength(2));
      },
    );
  });

  group('confirmed links', () {
    Future<PriceProduct> asdaFixtureProduct(String term) async =>
        (await FakeAsdaSearch().search(term)).first;

    test('refreshed by id: price updates, link stays confirmed', () async {
      final fresh = await asdaFixtureProduct('olive oil');
      final old = PriceProduct(
        store: PriceStore.asda,
        id: fresh.id,
        name: fresh.name,
        price: 99,
        quantity: fresh.quantity,
        fetchedAt: DateTime.utc(2025, 1, 1),
        stale: true,
      );
      final events = await run(
        ['olive oil'],
        confirmed: {
          'olive oil': confirmedLink('olive oil', asdaList: [old]),
        },
      );
      final r = events.last.result!;
      final link = r.effectiveLinks['olive oil']!;
      expect(link.userConfirmed, isTrue);
      expect(link.asda.single.price, fresh.price);
      expect(link.asda.single.stale, isFalse);
      expect(link.asda.single.fetchedAt, fresh.fetchedAt);
      expect(link.updatedAt, DateTime.utc(2026, 1, 1));
      // No extra by-name search was needed.
      expect(asda.calls, ['olive oil']);
      // The confirmed pick (not the auto-match) drives the comparison.
      expect(r.result.lines.single.bestAsda!.id, fresh.id);
    });

    test('missing product: one extra search by its name, then stale', () async {
      final gone = PriceProduct(
        store: PriceStore.asda,
        id: 'gone-1',
        name: 'Discontinued Oil 1L',
        price: 4.25,
        quantity: const PackQuantity(millilitres: 1000),
        fetchedAt: DateTime.utc(2025, 1, 1),
      );
      final events = await run(
        ['olive oil'],
        confirmed: {
          'olive oil': confirmedLink('olive oil', asdaList: [gone]),
        },
      );
      expect(asda.calls, ['olive oil', 'Discontinued Oil 1L']);
      final p = events.last.result!.effectiveLinks['olive oil']!.asda.single;
      expect(p.stale, isTrue);
      expect(p.price, 4.25, reason: 'last known price kept');
      expect(p.id, 'gone-1');
      // Still usable in the comparison.
      expect(events.last.result!.result.lines.single.bestAsda!.price, 4.25);
    });

    test('found by the extra name search: refreshed, not stale', () async {
      final fresh = PriceProduct(
        store: PriceStore.asda,
        id: 'x9',
        name: 'Rare Oil 1L',
        price: 3.0,
        quantity: const PackQuantity(millilitres: 1000),
        fetchedAt: now,
      );
      asda.overrides['rare oil 1l'] = [fresh];
      final old = PriceProduct(
        store: PriceStore.asda,
        id: 'x9',
        name: 'Rare Oil 1L',
        price: 8.0,
        quantity: const PackQuantity(millilitres: 1000),
        fetchedAt: DateTime.utc(2025, 1, 1),
      );
      final events = await run(
        ['olive oil'],
        confirmed: {
          'olive oil': confirmedLink('olive oil', asdaList: [old]),
        },
      );
      final p = events.last.result!.effectiveLinks['olive oil']!.asda.single;
      expect(p.price, 3.0);
      expect(p.stale, isFalse);
    });

    test(
      'unavailable flags are honoured and that store is not searched',
      () async {
        final events = await run(
          ['olive oil'],
          confirmed: {
            'olive oil': confirmedLink('olive oil', costcoUnavailable: true),
          },
        );
        final link = events.last.result!.effectiveLinks['olive oil']!;
        expect(link.costcoUnavailable, isTrue);
        expect(link.costco, isEmpty);
        expect(costco.calls, isEmpty);
        expect(asda.calls, ['olive oil']);
        expect(
          events.last.result!.result.lines.single.status,
          isNot(LineStatus.both),
        );
      },
    );

    test('both unavailable: no searches, line is unavailable', () async {
      final events = await run(
        ['olive oil'],
        confirmed: {
          'olive oil': confirmedLink(
            'olive oil',
            asdaUnavailable: true,
            costcoUnavailable: true,
          ),
        },
      );
      expect(asda.calls, isEmpty);
      expect(costco.calls, isEmpty);
      expect(
        events.last.result!.result.lines.single.status,
        LineStatus.unavailable,
      );
      expect(events.last.result!.storeErrors, isEmpty);
    });

    test('confirmed item is still auto-matched for the auto map', () async {
      final events = await run(
        ['olive oil'],
        confirmed: {'olive oil': confirmedLink('olive oil')},
      );
      expect(events.last.result!.auto.containsKey('olive oil'), isTrue);
    });

    test(
      'store down: confirmed products are kept, marked stale, no extra searches',
      () async {
        final fresh = (await FakeAsdaSearch().search('olive oil')).first;
        asda.failWith = asdaTimeout;
        final events = await run(
          ['olive oil'],
          confirmed: {
            'olive oil': confirmedLink('olive oil', asdaList: [fresh]),
          },
        );
        final p = events.last.result!.effectiveLinks['olive oil']!.asda.single;
        expect(p.stale, isTrue);
        expect(p.price, fresh.price);
        expect(asda.calls, ['olive oil'], reason: 'no by-name retry');
        expect(events.last.result!.storeErrors.keys, [PriceStore.asda]);
      },
    );
  });

  group('store failures', () {
    test(
      'Asda failing for every item: storeErrors set, result still produced',
      () async {
        asda.failWith = asdaTimeout;
        final events = await run(fixtureTerms.keys.toList());
        final r = events.last.result!;
        expect(r.storeErrors, {PriceStore.asda: 'Asda timed out'});
        expect(r.result.lines, hasLength(12));
        expect(r.result.lines.every((l) => l.bestAsda == null), isTrue);
        expect(
          r.result.lines.every(
            (l) =>
                l.status == LineStatus.costcoOnly ||
                l.status == LineStatus.unlinked,
          ),
          isTrue,
        );
        expect(
          r.result.lines.where((l) => l.status == LineStatus.costcoOnly),
          isNotEmpty,
        );
        expect(
          asda.calls,
          hasLength(2),
          reason: 'breaker stops after 2 timeouts',
        );
      },
    );

    test('one item failing is a per-item gap, not a store error', () async {
      asda.failWith = asdaTimeout;
      asda.failTerms.add('milk');
      final events = await run(['milk', 'cereal', 'olive oil']);
      final r = events.last.result!;
      expect(r.storeErrors, isEmpty);
      final milk = r.result.lines.first;
      expect(milk.bestAsda, isNull);
      expect(r.result.lines[1].bestAsda, isNotNull);
    });

    test('both stores failing is reported for each', () async {
      asda.failWith = asdaTimeout;
      costco.failWith = Exception('boom');
      final events = await run(['milk', 'cereal']);
      final r = events.last.result!;
      expect(r.storeErrors.keys.toSet(), {PriceStore.asda, PriceStore.costco});
      expect(
        r.result.lines.every((l) => l.status == LineStatus.unlinked),
        isTrue,
      );
      expect(r.storeErrors[PriceStore.costco], contains('boom'));
    });
  });

  group('circuit breaker', () {
    test(
      'Asda is skipped after 2 consecutive failures; error reported at once',
      () async {
        asda.failWith = asdaTimeout;
        final events = await run(fixtureTerms.keys.toList());
        expect(asda.calls, ['milk', 'basmati rice']);
        final r = events.last.result!;
        expect(r.storeErrors[PriceStore.asda], 'Asda timed out');
        expect(r.storeErrors.containsKey(PriceStore.costco), isFalse);
        expect(costco.calls, hasLength(12), reason: 'Costco unaffected');
        expect(r.result.lines.every((l) => l.bestAsda == null), isTrue);
        expect(
          r.result.lines.where((l) => l.status == LineStatus.costcoOnly),
          isNotEmpty,
        );
        // Progress events show the tripped store before the run ends.
        final early = events.where(
          (e) => e.result == null && e.storeErrors.containsKey(PriceStore.asda),
        );
        expect(early, isNotEmpty);
        expect(events.first.storeErrors, isEmpty);
      },
    );

    test('a success resets the consecutive count', () async {
      asda.failWith = asdaTimeout;
      asda.failTerms.addAll({'milk', 'cereal'});
      final events = await run(['milk', 'olive oil', 'cereal', 'tea bags']);
      expect(asda.calls, hasLength(4), reason: 'never 2 failures in a row');
      expect(events.last.result!.storeErrors, isEmpty);
    });

    test(
      'trips even if earlier items succeeded; tripped store is reported',
      () async {
        asda.failWith = asdaTimeout;
        asda.failTerms.addAll({'cereal', 'tea bags'});
        final events = await run(['milk', 'cereal', 'tea bags', 'olive oil']);
        expect(asda.calls, ['milk', 'cereal', 'tea bags']);
        final r = events.last.result!;
        expect(r.storeErrors.keys, [PriceStore.asda]);
        expect(r.result.lines.first.bestAsda, isNotNull);
        expect(r.result.lines.last.bestAsda, isNull);
      },
    );

    test('Costco trips after 3 consecutive failures', () async {
      costco.failWith = Exception('boom');
      final events = await run(fixtureTerms.keys.toList());
      expect(costco.calls, hasLength(3));
      final r = events.last.result!;
      expect(r.storeErrors[PriceStore.costco], contains('boom'));
      expect(r.storeErrors.containsKey(PriceStore.asda), isFalse);
      expect(asda.calls, hasLength(12));
    });

    test('Costco: a success resets the count so it never trips', () async {
      costco.failWith = Exception('boom');
      costco.failTerms.addAll({'milk', 'cereal', 'tea bags', 'baked beans'});
      final events = await run([
        'milk',
        'cereal',
        'olive oil',
        'tea bags',
        'baked beans',
      ]);
      expect(costco.calls, hasLength(5));
      expect(events.last.result!.storeErrors, isEmpty);
    });

    test('tripped Asda blocks by-name retries for confirmed links', () async {
      final fresh = (await FakeAsdaSearch().search('olive oil')).first;
      asda.failWith = asdaTimeout;
      final events = await run(
        ['milk', 'cereal', 'olive oil'],
        confirmed: {
          'olive oil': confirmedLink('olive oil', asdaList: [fresh]),
        },
      );
      expect(asda.calls, ['milk', 'cereal']);
      final p = events.last.result!.effectiveLinks['olive oil']!.asda.single;
      expect(p.stale, isTrue);
    });

    test('breaker state is per run', () async {
      asda.failWith = asdaTimeout;
      await run(['milk', 'cereal', 'olive oil']);
      asda.failWith = null;
      final events = await run(['tea bags', 'kitchen roll']);
      expect(events.last.result!.storeErrors, isEmpty);
      expect(events.last.result!.result.lines.first.bestAsda, isNotNull);
    });
  });

  group('cache', () {
    test(
      'second run within TTL does not search again; expires after TTL',
      () async {
        await run(['milk', 'cereal']);
        expect(asda.calls, hasLength(2));
        expect(costco.calls, hasLength(2));

        now = now.add(const Duration(hours: 5, minutes: 59));
        await run(['milk', 'cereal']);
        expect(asda.calls, hasLength(2));
        expect(costco.calls, hasLength(2));

        now = now.add(const Duration(minutes: 2));
        await run(['milk', 'cereal']);
        expect(asda.calls, hasLength(4));
        expect(costco.calls, hasLength(4));
      },
    );

    test('cache key ignores case and spacing', () async {
      await run(['Milk']);
      await run(['  milk ']);
      expect(asda.calls, hasLength(1));
    });

    test('failures are not cached', () async {
      asda.failWith = asdaTimeout;
      await run(['milk']);
      asda.failWith = null;
      final events = await run(['milk']);
      expect(asda.calls, hasLength(2));
      expect(events.last.result!.result.lines.single.bestAsda, isNotNull);
    });

    test('searchStore shares the cache', () async {
      await svc.searchStore(PriceStore.asda, 'milk');
      await svc.searchStore(PriceStore.asda, 'Milk');
      expect(asda.calls, hasLength(1));
    });

    test('custom TTL', () async {
      final short = PriceSearchService(
        asda: asda,
        costco: costco,
        cacheTtl: const Duration(minutes: 1),
        clock: () => now,
      );
      await run(['milk'], service: short);
      now = now.add(const Duration(minutes: 2));
      await run(['milk'], service: short);
      expect(asda.calls, hasLength(2));
    });
  });

  group('concurrency and cancellation', () {
    test('Asda runs serially, Costco up to 3 at a time', () async {
      var asdaNow = 0, asdaMax = 0, costcoNow = 0, costcoMax = 0;
      asda.gate = () async {
        asdaMax = asdaNow + 1 > asdaMax ? asdaNow + 1 : asdaMax;
        asdaNow++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        asdaNow--;
      };
      costco.gate = () async {
        costcoMax = costcoNow + 1 > costcoMax ? costcoNow + 1 : costcoMax;
        costcoNow++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        costcoNow--;
      };
      await run(fixtureTerms.keys.toList());
      expect(asdaMax, 1);
      expect(costcoMax, inInclusiveRange(2, 3));
    });

    test('cancelling the subscription stops further searches', () async {
      final release = Completer<void>();
      asda.gate = () => release.future;
      final got = <PriceRunProgress>[];
      final first = Completer<void>();
      final sub = svc
          .run(
            items: [for (final t in fixtureTerms.keys) shoppingItem(t)],
            confirmed: const {},
            fees: _fees,
          )
          .listen((e) {
            got.add(e);
            if (!first.isCompleted) first.complete();
          });
      await first.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asda.calls, hasLength(1), reason: 'blocked on the first search');
      await sub.cancel();
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(asda.calls, hasLength(1), reason: 'queued searches never started');
      expect(got.where((e) => e.result != null), isEmpty);
    });

    test(
      'a cancelled run does not poison the cache for the next run',
      () async {
        final release = Completer<void>();
        asda.gate = () => release.future;
        final sub = svc
            .run(
              items: [shoppingItem('milk'), shoppingItem('cereal')],
              confirmed: const {},
              fees: _fees,
            )
            .listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel();
        release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        asda.gate = null;
        final events = await run(['milk', 'cereal']);
        expect(
          events.last.result!.result.lines.every((l) => l.bestAsda != null),
          isTrue,
        );
      },
    );
  });
}
