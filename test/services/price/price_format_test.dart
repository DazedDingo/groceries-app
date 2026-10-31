import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/auto_match.dart';
import 'package:groceries_app/models/price_link.dart';
import 'package:groceries_app/services/price/price_compare.dart';
import 'package:groceries_app/services/price/price_format.dart';

import 'price_test_support.dart';

PriceProduct prod(
  String id,
  double price, {
  PriceStore store = PriceStore.asda,
  PackQuantity? q,
}) => PriceProduct(
  store: store,
  id: id,
  name: 'Product $id',
  price: price,
  quantity: q,
  fetchedAt: fixtureFetched,
);

PriceLink linkOf(
  String key, {
  List<PriceProduct> asda = const [],
  List<PriceProduct> costco = const [],
}) => PriceLink(
  itemKey: key,
  asda: asda,
  costco: costco,
  updatedAt: fixtureFetched,
);

void main() {
  group('formatUnitCost', () {
    test('grams -> £/kg', () {
      final p = prod('a', 1.5, q: const PackQuantity(grams: 500));
      expect(formatUnitCost(p, CompareBasis.grams), '£3.00/kg');
    });

    test('millilitres -> £/L', () {
      final p = prod('a', 23, q: const PackQuantity(millilitres: 5000));
      expect(formatUnitCost(p, CompareBasis.millilitres), '£4.60/L');
    });

    test('count units under £1 -> pence', () {
      final bags = prod(
        'a',
        2.4,
        q: const PackQuantity(count: 80, countUnit: 'bag'),
      );
      expect(formatUnitCost(bags, CompareBasis.bag), '3p/bag');
      final cheap = prod(
        'b',
        1.5,
        q: const PackQuantity(count: 240, countUnit: 'bag'),
      );
      expect(formatUnitCost(cheap, CompareBasis.bag), '0.6p/bag');
      final mid = prod(
        'c',
        6,
        q: const PackQuantity(count: 12, countUnit: 'wash'),
      );
      expect(formatUnitCost(mid, CompareBasis.wash), '50p/wash');
    });

    test('count units at or above £1 -> pounds', () {
      final p = prod(
        'a',
        15,
        q: const PackQuantity(count: 10, countUnit: 'wash'),
      );
      expect(formatUnitCost(p, CompareBasis.wash), '£1.50/wash');
    });

    test('just under £1 rounds up to £1.00 rather than 100p', () {
      final p = prod(
        'a',
        9.996,
        q: const PackQuantity(count: 10, countUnit: 'roll'),
      );
      expect(formatUnitCost(p, CompareBasis.roll), '£1.00/roll');
    });

    test('generic count uses unit; unknown basis gives null', () {
      final p = prod('a', 3, q: const PackQuantity(count: 6));
      expect(formatUnitCost(p, CompareBasis.count), '50p/unit');
      expect(formatUnitCost(p, CompareBasis.grams), isNull);
      expect(formatUnitCost(prod('b', 3), CompareBasis.grams), isNull);
    });
  });

  group('displayBasis', () {
    test('prefers specific count units, then weight, volume, count', () {
      expect(
        displayBasis(
          prod('a', 1, q: const PackQuantity(count: 4, countUnit: 'roll')),
        ),
        CompareBasis.roll,
      );
      expect(
        displayBasis(prod('a', 1, q: const PackQuantity(grams: 100))),
        CompareBasis.grams,
      );
      expect(
        displayBasis(prod('a', 1, q: const PackQuantity(millilitres: 100))),
        CompareBasis.millilitres,
      );
      expect(displayBasis(prod('a', 1)), isNull);
    });
  });

  test('formatPounds / formatPackPrice / formatUpdatedAgo', () {
    expect(formatPounds(6), '£6.00');
    expect(formatPounds(-1.5), '-£1.50');
    final p = prod('a', 3.99);
    expect(formatPackPrice(p, 1), '£3.99');
    expect(formatPackPrice(p, 2), '2 × £3.99 = £7.98');
    final now = DateTime(2026, 10, 31, 12);
    expect(formatUpdatedAgo(now, now), 'Updated just now');
    expect(
      formatUpdatedAgo(now.subtract(const Duration(minutes: 5)), now),
      'Updated 5 min ago',
    );
    expect(
      formatUpdatedAgo(now.subtract(const Duration(hours: 2)), now),
      'Updated 2 h ago',
    );
  });

  group('describeRecommendation', () {
    // Asda 1kg £5; Costco 5kg £22 -> Costco saves £3 per kg-equivalent.
    final asda = prod('a', 5, q: const PackQuantity(grams: 1000));
    final costco = prod(
      'c',
      22,
      store: PriceStore.costco,
      q: const PackQuantity(grams: 5000),
    );

    test('saving smaller than the fee -> asda only, explains why', () {
      final r = compareBasket([
        CompareLine(
          itemName: 'rice',
          link: linkOf('rice', asda: [asda], costco: [costco]),
        ),
      ]);
      expect(r.recommendation, Recommendation.asdaOnly);
      final t = describeRecommendation(r, const PriceFees());
      expect(t.headline, 'Just order from Asda');
      expect(t.why, contains('Costco would save only £3.00'));
      expect(t.why, contains('£5.99 delivery'));
    });

    test('no costco matches', () {
      final r = compareBasket([
        CompareLine(
          itemName: 'rice',
          link: linkOf('rice', asda: [asda]),
        ),
      ]);
      final t = describeRecommendation(r, const PriceFees());
      expect(t.headline, 'Just order from Asda');
      expect(t.why, 'No Costco matches for your list.');
    });

    test('big saving -> split with no extra why', () {
      final r = compareBasket([
        CompareLine(
          itemName: 'rice',
          qty: 3,
          link: linkOf('rice', asda: [asda], costco: [costco]),
        ),
      ], fees: const PriceFees(costcoDelivery: 1));
      final t = describeRecommendation(r, const PriceFees(costcoDelivery: 1));
      expect(t.headline, 'Order from both');
      expect(t.why, isNull);
    });

    test('forced by costco-only lines', () {
      final r = compareBasket([
        CompareLine(
          itemName: 'bulk',
          link: linkOf('bulk', costco: [costco]),
        ),
      ]);
      final t = describeRecommendation(r, const PriceFees());
      expect(t.headline, 'Order from both');
      expect(t.why, contains('only sold at Costco'));
    });

    test('nothing priced', () {
      final r = compareBasket([CompareLine(itemName: 'x', link: linkOf('x'))]);
      expect(
        describeRecommendation(r, const PriceFees()).headline,
        'Nothing priced yet',
      );
    });
  });

  group('costco saving / unpriced reasons', () {
    test('formatCostcoSaving', () {
      final asda = prod('a', 5, q: const PackQuantity(grams: 1000));
      final costco = prod(
        'c',
        22,
        store: PriceStore.costco,
        q: const PackQuantity(grams: 5000),
      );
      final l = compareLine(
        CompareLine(
          itemName: 'rice',
          link: linkOf('rice', asda: [asda], costco: [costco]),
        ),
      );
      expect(formatCostcoSaving(l), 'saves £3.00 vs 5 × Asda £5.00');
      final none = compareLine(
        CompareLine(
          itemName: 'rice',
          link: linkOf('rice', asda: [asda]),
        ),
      );
      expect(formatCostcoSaving(none), isNull);
    });

    test('unpricedReason', () {
      final unlinked = compareLine(
        CompareLine(itemName: 'x', link: linkOf('x')),
      );
      expect(unpricedReason(unlinked, null), 'No Asda match · no Costco match');
      final auto = AutoMatchResult(
        link: linkOf('x'),
        asdaConfidence: MatchConfidence.none,
        costcoConfidence: MatchConfidence.none,
        costcoRejectReason: 'no ambient pack',
      );
      expect(unpricedReason(unlinked, auto), 'No Asda match · no ambient pack');
      final unavailable = compareLine(
        CompareLine(
          itemName: 'x',
          link: PriceLink(
            itemKey: 'x',
            asdaUnavailable: true,
            costcoUnavailable: true,
            updatedAt: fixtureFetched,
          ),
        ),
      );
      expect(unpricedReason(unavailable, null), 'Marked as not available');
    });
  });
}
