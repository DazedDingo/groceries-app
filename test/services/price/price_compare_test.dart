import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_link.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/asda_parser.dart';
import 'package:groceries_app/services/price/costco_parser.dart';
import 'package:groceries_app/services/price/price_compare.dart';

final _t = DateTime.utc(2026, 10, 31, 12);

PriceProduct _p(
  PriceStore store,
  String id,
  double price, {
  PackQuantity? q,
  String? promo,
  bool inStock = true,
}) => PriceProduct(
  store: store,
  id: id,
  name: id,
  price: price,
  quantity: q,
  inStock: inStock,
  promos: promo == null ? const [] : [PricePromo.parse(id: 'p', name: promo)],
  fetchedAt: _t,
);

PriceProduct _asda(
  String id,
  double price, {
  PackQuantity? q,
  String? promo,
  bool inStock = true,
}) => _p(PriceStore.asda, id, price, q: q, promo: promo, inStock: inStock);

PriceProduct _costco(
  String id,
  double price, {
  PackQuantity? q,
  bool inStock = true,
}) => _p(PriceStore.costco, id, price, q: q, inStock: inStock);

PriceLink _link(
  String name, {
  List<PriceProduct> asda = const [],
  List<PriceProduct> costco = const [],
  LinkMode mode = LinkMode.exact,
  bool asdaUnavailable = false,
  bool costcoUnavailable = false,
}) => PriceLink(
  itemKey: PriceLink.keyFor(name),
  mode: mode,
  asda: asda,
  costco: costco,
  asdaUnavailable: asdaUnavailable,
  costcoUnavailable: costcoUnavailable,
  updatedAt: _t,
);

CompareLine _line(String name, PriceLink? link, {int qty = 1}) =>
    CompareLine(itemName: name, qty: qty, link: link);

const _ml1000 = PackQuantity(millilitres: 1000);
const _ml5000 = PackQuantity(millilitres: 5000);
const _g500 = PackQuantity(grams: 500);
const _g3000 = PackQuantity(grams: 3000);

void main() {
  group('chooseBasis', () {
    test('null / empty inputs', () {
      expect(chooseBasis(null, _g500), isNull);
      expect(chooseBasis(_g500, null), isNull);
      expect(chooseBasis(const PackQuantity(), const PackQuantity()), isNull);
    });

    test('shared specific count unit beats grams and ml', () {
      const a = PackQuantity(
        grams: 500,
        millilitres: 1500,
        count: 60,
        countUnit: 'wash',
      );
      const b = PackQuantity(
        grams: 100,
        millilitres: 2565,
        count: 95,
        countUnit: 'wash',
      );
      expect(chooseBasis(a, b), CompareBasis.wash);
    });

    test('each specific unit maps to its own basis', () {
      for (final u in [
        'wash',
        'bag',
        'roll',
        'tablet',
        'pod',
        'capsule',
        'sheet',
      ]) {
        final q = PackQuantity(count: 10, countUnit: u);
        expect(chooseBasis(q, q)!.name, u);
      }
    });

    test('grams, then millilitres', () {
      expect(chooseBasis(_g500, _g3000), CompareBasis.grams);
      expect(chooseBasis(_ml1000, _ml5000), CompareBasis.millilitres);
      expect(
        chooseBasis(
          const PackQuantity(grams: 1, millilitres: 2),
          const PackQuantity(grams: 1, millilitres: 2),
        ),
        CompareBasis.grams,
      );
    });

    test('different specific units fall back to grams', () {
      const a = PackQuantity(grams: 500, count: 4, countUnit: 'roll');
      const b = PackQuantity(grams: 900, count: 6, countUnit: 'bag');
      expect(chooseBasis(a, b), CompareBasis.grams);
    });

    test('generic count when units are equal or one side is each', () {
      const each = PackQuantity(count: 48, countUnit: 'each');
      const serv = PackQuantity(count: 80, countUnit: 'serving');
      expect(chooseBasis(each, each), CompareBasis.count);
      expect(chooseBasis(each, serv), CompareBasis.count);
      expect(chooseBasis(serv, serv), CompareBasis.count);
      expect(
        chooseBasis(
          const PackQuantity(count: 4, countUnit: 'roll'),
          const PackQuantity(count: 4, countUnit: 'bag'),
        ),
        isNull,
      );
    });

    test('mass vs volume only is not comparable', () {
      expect(chooseBasis(_g500, _ml1000), isNull);
    });
  });

  group('amountIn / unitCost', () {
    test('specific unit only matches its own countUnit', () {
      const q = PackQuantity(count: 60, countUnit: 'wash', millilitres: 1500);
      expect(amountIn(q, CompareBasis.wash), 60);
      expect(amountIn(q, CompareBasis.bag), isNull);
      expect(amountIn(q, CompareBasis.millilitres), 1500);
      expect(amountIn(q, CompareBasis.grams), isNull);
      expect(amountIn(q, CompareBasis.count), 60);
    });

    test('unit cost is price / amount; null when unknown', () {
      final p = _asda('a', 3.0, q: const PackQuantity(grams: 1500));
      expect(unitCost(p, CompareBasis.grams), closeTo(0.002, 1e-12));
      expect(unitCost(p, CompareBasis.millilitres), isNull);
      expect(unitCost(_asda('b', 3.0), CompareBasis.grams), isNull);
    });
  });

  group('compareLine statuses', () {
    test('null link -> unlinked', () {
      expect(compareLine(_line('x', null)).status, LineStatus.unlinked);
    });

    test('empty link, no flags -> unlinked', () {
      expect(compareLine(_line('x', _link('x'))).status, LineStatus.unlinked);
    });

    test('both flagged unavailable -> unavailable', () {
      final l = _link('x', asdaUnavailable: true, costcoUnavailable: true);
      expect(compareLine(_line('x', l)).status, LineStatus.unavailable);
    });

    test('products present but their store flagged -> unavailable', () {
      final l = _link('x', asda: [_asda('a', 1)], asdaUnavailable: true);
      expect(compareLine(_line('x', l)).status, LineStatus.unavailable);
    });

    test('asdaOnly / costcoOnly / both', () {
      expect(
        compareLine(_line('x', _link('x', asda: [_asda('a', 1)]))).status,
        LineStatus.asdaOnly,
      );
      expect(
        compareLine(_line('x', _link('x', costco: [_costco('c', 1)]))).status,
        LineStatus.costcoOnly,
      );
      expect(
        compareLine(
          _line(
            'x',
            _link('x', asda: [_asda('a', 1)], costco: [_costco('c', 1)]),
          ),
        ).status,
        LineStatus.both,
      );
    });
  });

  group('compareLine maths', () {
    final oliveAsda = _asda('asda-evoo', 7.5, q: _ml1000);
    final oliveCostco = _costco('kirkland', 22.99, q: _ml5000);

    test('olive oil: per-litre unit costs and saving', () {
      final r = compareLine(
        _line(
          'olive oil',
          _link('olive oil', asda: [oliveAsda], costco: [oliveCostco]),
        ),
      );
      expect(r.basis, CompareBasis.millilitres);
      expect(r.asdaUnitCost! * 1000, closeTo(7.5, 1e-9));
      expect(r.costcoUnitCost! * 1000, closeTo(4.598, 1e-9));
      expect(r.cheaperStore, PriceStore.costco);
      expect(r.asdaEquivalentPacks, 5);
      expect(r.costcoSaving, closeTo(14.51, 1e-9));
    });

    test('qty scales both sides', () {
      final r = compareLine(
        _line(
          'olive oil',
          _link('olive oil', asda: [oliveAsda], costco: [oliveCostco]),
          qty: 2,
        ),
      );
      expect(r.asdaEquivalentPacks, 10);
      expect(r.costcoSaving, closeTo(75 - 45.98, 1e-9));
      expect(r.asdaCost, closeTo(15, 1e-9)); // 2 Asda packs actually wanted
    });

    test('equivalent packs round up', () {
      // 1500 g Costco vs 400 g Asda -> 3.75 -> 4 packs
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            asda: [_asda('a', 1.0, q: const PackQuantity(grams: 400))],
            costco: [_costco('c', 3.0, q: const PackQuantity(grams: 1500))],
          ),
        ),
      );
      expect(r.asdaEquivalentPacks, 4);
      expect(r.costcoSaving, closeTo(1.0, 1e-9));
    });

    test('exact multiples do not round up from float noise', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            asda: [_asda('a', 1.0, q: const PackQuantity(millilitres: 0.1))],
            costco: [
              _costco('c', 3.0, q: const PackQuantity(millilitres: 0.3)),
            ],
          ),
        ),
      );
      expect(r.asdaEquivalentPacks, 3);
    });

    test('Asda multibuy flips the winner', () {
      final costco = _costco(
        'six-pack',
        7.20,
        q: const PackQuantity(grams: 3000),
      );
      final plain = _asda('spag', 1.5, q: _g500);
      final deal = _asda('spag', 1.5, q: _g500, promo: 'Any 2 for £2');

      final without = compareLine(
        _line('spaghetti', _link('spaghetti', asda: [plain], costco: [costco])),
      );
      expect(without.cheaperStore, PriceStore.costco);
      expect(without.costcoSaving, closeTo(9 - 7.2, 1e-9));

      final withDeal = compareLine(
        _line('spaghetti', _link('spaghetti', asda: [deal], costco: [costco])),
      );
      // 6 packs = 3 groups of 2 for £2 = £6, cheaper than Costco's £7.20
      expect(withDeal.asdaEquivalentCost, closeTo(6, 1e-9));
      expect(withDeal.costcoSaving, closeTo(6 - 7.2, 1e-9));
      expect(withDeal.cheaperStore, PriceStore.asda);
      expect(withDeal.asdaUnitCost, closeTo(1.5 / 500, 1e-12)); // list price
      expect(withDeal.asdaEffectiveUnitCost, closeTo(1.0 / 500, 1e-12));
    });

    test('tie -> no cheaper store', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            asda: [_asda('a', 1.0, q: _g500)],
            costco: [_costco('c', 2.0, q: const PackQuantity(grams: 1000))],
          ),
        ),
      );
      expect(r.costcoSaving, closeTo(0, 1e-9));
      expect(r.cheaperStore, isNull);
    });

    test('no shared basis: lowest price each, no saving', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            mode: LinkMode.anyOf,
            asda: [
              _asda('a1', 5.0, q: _g500),
              _asda('a2', 3.0, q: _g500),
            ],
            costco: [
              _costco('c1', 9.0, q: _ml1000),
              _costco('c2', 8.0),
            ],
          ),
        ),
      );
      expect(r.status, LineStatus.both);
      expect(r.basis, isNull);
      expect(r.bestAsda!.id, 'a2');
      expect(r.bestCostco!.id, 'c2');
      expect(r.costcoSaving, isNull);
      expect(r.cheaperStore, isNull);
    });

    test('unknown quantities on one side: no basis', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            asda: [_asda('a', 1.0)],
            costco: [_costco('c', 2.0, q: _g500)],
          ),
        ),
      );
      expect(r.basis, isNull);
      expect(r.costcoSaving, isNull);
    });
  });

  group('best product selection', () {
    test('anyOf picks lowest unit cost per store', () {
      final r = compareLine(
        _line(
          'olive oil',
          _link(
            'olive oil',
            mode: LinkMode.anyOf,
            asda: [
              _asda('250ml', 2.98, q: const PackQuantity(millilitres: 250)),
              _asda('1L', 7.5, q: _ml1000),
              _asda('750ml', 6.98, q: const PackQuantity(millilitres: 750)),
            ],
            costco: [
              _costco('1L', 13.49, q: _ml1000),
              _costco('5L', 22.99, q: _ml5000),
            ],
          ),
        ),
      );
      expect(r.bestAsda!.id, '1L'); // 0.0075/ml vs 0.0093 and 0.0119
      expect(r.bestCostco!.id, '5L');
    });

    test('exact mode only uses the first product', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            mode: LinkMode.exact,
            asda: [
              _asda('first', 9.0, q: _g500),
              _asda('cheaper', 1.0, q: _g500),
            ],
            costco: [_costco('c', 5.0, q: _g3000)],
          ),
        ),
      );
      expect(r.bestAsda!.id, 'first');
    });

    test('in-stock preferred over cheaper out-of-stock', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            mode: LinkMode.anyOf,
            asda: [
              _asda('oos', 1.0, q: _g500, inStock: false),
              _asda('ok', 2.0, q: _g500),
            ],
            costco: [_costco('c', 5.0, q: _g3000)],
          ),
        ),
      );
      expect(r.bestAsda!.id, 'ok');
    });

    test('all out of stock: still compares', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            mode: LinkMode.anyOf,
            asda: [
              _asda('oos1', 2.0, q: _g500, inStock: false),
              _asda('oos2', 1.0, q: _g500, inStock: false),
            ],
          ),
        ),
      );
      expect(r.status, LineStatus.asdaOnly);
      expect(r.bestAsda!.id, 'oos2');
    });

    test('ties on unit cost go to the cheaper pack, then list order', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            mode: LinkMode.anyOf,
            asda: [
              _asda('big', 2.0, q: const PackQuantity(grams: 1000)),
              _asda('small', 1.0, q: _g500),
              _asda('small-dupe', 1.0, q: _g500),
            ],
            costco: [_costco('c', 9.0, q: _g3000)],
          ),
        ),
      );
      expect(r.bestAsda!.id, 'small');
    });

    test('products lacking the basis amount are skipped', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            mode: LinkMode.anyOf,
            asda: [
              _asda('noq', 0.1),
              _asda('q', 3.0, q: _g500),
            ],
            costco: [_costco('c', 9.0, q: _g3000)],
          ),
        ),
      );
      expect(r.bestAsda!.id, 'q');
    });

    test('single store: best on its own best shared basis', () {
      final r = compareLine(
        _line(
          'x',
          _link(
            'x',
            mode: LinkMode.anyOf,
            asda: [
              _asda('small', 1.0, q: _g500),
              _asda('large', 1.5, q: const PackQuantity(grams: 1000)),
            ],
          ),
        ),
      );
      expect(r.bestAsda!.id, 'large');
    });

    group('multibuy-aware pick (qty >= multibuy quantity)', () {
      // Same 500g pack: 'deal' is 1.50 alone but 1.00 each on 2 for £2.
      final plain = _asda('plain', 1.2, q: _g500);
      final deal = _asda('deal', 1.5, q: _g500, promo: 'Any 2 for £2');
      final costco = _costco('big', 9.0, q: _g3000);

      PriceLink link() => _link(
        'x',
        mode: LinkMode.anyOf,
        asda: [plain, deal],
        costco: [costco],
      );

      test('qty 1 ignores the multibuy: list price wins', () {
        final r = compareLine(_line('x', link()));
        expect(r.bestAsda!.id, 'plain');
      });

      test('qty below the multibuy quantity ignores it too', () {
        final r = compareLine(_line('x', link(), qty: 1));
        expect(r.bestAsda!.id, 'plain');
      });

      test('qty at the multibuy quantity uses the effective cost', () {
        final r = compareLine(_line('x', link(), qty: 2));
        expect(r.bestAsda!.id, 'deal'); // 2 for £2 = 1.00 each < 1.20
      });

      test('qty above the multibuy quantity still uses the deal', () {
        final r = compareLine(_line('x', link(), qty: 3));
        // 3 packs: deal = 2.00 + 1.50 = 3.50 (1.17 each) vs plain 3.60.
        expect(r.bestAsda!.id, 'deal');
      });

      test('a multibuy dearer than singles is capped at the single price', () {
        final bad = _asda('bad', 1.5, q: _g500, promo: 'Any 2 for £4');
        final r = compareLine(
          _line(
            'x',
            _link('x', mode: LinkMode.anyOf, asda: [plain, bad]),
            qty: 2,
          ),
        );
        expect(r.bestAsda!.id, 'plain'); // bad is 1.50 each, not 2.00
      });

      test('applies to an Asda-only line as well', () {
        final r = compareLine(
          _line(
            'x',
            _link('x', mode: LinkMode.anyOf, asda: [plain, deal]),
            qty: 2,
          ),
        );
        expect(r.status, LineStatus.asdaOnly);
        expect(r.bestAsda!.id, 'deal');
        expect(r.asdaCost, closeTo(2.0, 1e-9));
      });

      test('Costco side is unaffected by multibuy parsing', () {
        final c1 = _costco('c-plain', 9.0, q: _g3000);
        final r = compareLine(
          _line(
            'x',
            _link('x', mode: LinkMode.anyOf, asda: [plain], costco: [c1]),
            qty: 2,
          ),
        );
        expect(r.bestCostco!.id, 'c-plain');
      });
    });
  });

  group('real products from fixtures', () {
    final asdaJson =
        jsonDecode(
              File(
                'test/fixtures/price/asda_algolia_queries.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final costcoJson =
        jsonDecode(
              File('test/fixtures/price/costco_search.json').readAsStringSync(),
            )
            as Map<String, dynamic>;

    List<PriceProduct> asdaTerm(String t) =>
        parseAsdaAlgolia(asdaJson[t] as Map<String, dynamic>, fetchedAt: _t);
    List<PriceProduct> costcoTerm(String t) =>
        parseCostcoSearch(costcoJson[t] as Map<String, dynamic>, fetchedAt: _t);

    test('tea compares per bag: Costco 600 beats Taylors 160 rollback', () {
      final taylors = asdaTerm(
        'tea bags',
      ).firstWhere((p) => p.name.contains('Taylors of Harrogate 160'));
      final yorkshire = costcoTerm('tea bags').first;
      final r = compareLine(
        _line(
          'tea bags',
          _link('tea bags', asda: [taylors], costco: [yorkshire]),
        ),
      );
      expect(r.basis, CompareBasis.bag);
      expect(r.asdaUnitCost, closeTo(4.5 / 160, 1e-12));
      expect(r.costcoUnitCost, closeTo(14.99 / 600, 1e-12));
      expect(r.cheaperStore, PriceStore.costco);
      expect(r.asdaEquivalentPacks, 4); // 600/160 = 3.75
      expect(r.costcoSaving, closeTo(18.0 - 14.99, 1e-9));
    });

    test('dishwasher tablets: Asda 40 x 14g beats Kirkland 115 per tablet', () {
      final asda = asdaTerm('dishwasher tablets').first;
      final kirkland = costcoTerm(
        'dishwasher tablets',
      ).firstWhere((p) => p.name.startsWith('Kirkland'));
      final r = compareLine(
        _line(
          'dishwasher tablets',
          _link('d', asda: [asda], costco: [kirkland]),
        ),
      );
      expect(r.basis, CompareBasis.tablet);
      expect(r.asdaUnitCost, closeTo(3.5 / 40, 1e-12));
      expect(r.cheaperStore, PriceStore.asda);
    });

    test('loo roll: Costco Cushelle 24 beats Andrex per roll', () {
      final andrex = asdaTerm(
        'toilet roll',
      ).firstWhere((p) => p.name.contains('Standard Rolls 8 Rolls'));
      final cushelle = costcoTerm('toilet tissue').first;
      final r = compareLine(
        _line('toilet roll', _link('t', asda: [andrex], costco: [cushelle])),
      );
      expect(r.basis, CompareBasis.roll);
      expect(r.cheaperStore, PriceStore.costco);
    });
  });

  group('laundry', () {
    test('compares per wash, not per litre', () {
      // Per litre Asda is cheaper (4/L vs 6/L) but per wash Costco is.
      final asda = _asda(
        'asda-liquid',
        6.0,
        q: const PackQuantity(millilitres: 1500, count: 30, countUnit: 'wash'),
      );
      final costco = _costco(
        'costco-liquid',
        12.0,
        q: const PackQuantity(millilitres: 2000, count: 100, countUnit: 'wash'),
      );
      final r = compareLine(
        _line('laundry liquid', _link('l', asda: [asda], costco: [costco])),
      );
      expect(r.basis, CompareBasis.wash);
      expect(r.asdaUnitCost, closeTo(0.2, 1e-12));
      expect(r.costcoUnitCost, closeTo(0.12, 1e-12));
      expect(r.cheaperStore, PriceStore.costco);
      expect(r.asdaEquivalentPacks, 4); // 100 washes / 30
      expect(r.costcoSaving, closeTo(24 - 12, 1e-9));
    });
  });

  group('compareBasket recommendation', () {
    CompareLine olive({int qty = 1}) => _line(
      'olive oil',
      _link(
        'olive oil',
        asda: [_asda('asda-evoo', 7.5, q: _ml1000)],
        costco: [_costco('kirkland', 22.99, q: _ml5000)],
      ),
      qty: qty,
    );

    test('olive oil: split recommended', () {
      final r = compareBasket([olive()]);
      expect(r.recommendation, Recommendation.split);
      expect(r.splitNetSaving, closeTo(14.51 - 5.99, 1e-9));
      expect(r.splitPlan.costcoLines, hasLength(1));
      expect(r.splitPlan.asdaLines, isEmpty);
      expect(r.splitPlan.costcoSpend, closeTo(22.99, 1e-9));
      expect(r.splitPlan.asdaFee, 0);
      expect(r.splitPlan.costcoFee, 5.99);
      expect(r.asdaOnlyTotal, closeTo(7.5 + 6, 1e-9));
      expect(
        r.summary,
        'Order 1 item from Costco: saves £14.51, minus £5.99 delivery = £8.52',
      );
    });

    test('tiny saving below the delivery fee -> asdaOnly', () {
      final line = _line(
        'beans',
        _link(
          'beans',
          asda: [_asda('a', 1.0, q: _g500)],
          costco: [_costco('c', 5.0, q: _g3000)], // equiv 6 packs = 6.00
        ),
      );
      final r = compareBasket([line]);
      expect(r.recommendation, Recommendation.asdaOnly);
      expect(r.splitNetSaving, lessThan(0));
      expect(r.splitPlan.costcoLines, isEmpty);
      expect(r.splitPlan.costcoFee, 0);
      expect(r.splitPlan.asdaLines, hasLength(1));
      expect(r.summary, contains('Order everything from Asda'));
      expect(r.summary, contains('£1.00'));
    });

    test('several small savings that add up past the fee -> split', () {
      CompareLine small(String n) => _line(
        n,
        _link(
          n,
          asda: [_asda('a-$n', 1.0, q: _g500)],
          costco: [_costco('c-$n', 4.0, q: _g3000)], // saves £2.00 each
        ),
      );
      final r = compareBasket([small('a'), small('b'), small('c'), small('d')]);
      expect(r.recommendation, Recommendation.split);
      expect(r.splitNetSaving, closeTo(8 - 5.99, 1e-9));
      expect(r.splitPlan.costcoLines, hasLength(4));
      expect(
        r.summary,
        'Order 4 items from Costco: saves £8.00, minus £5.99 delivery = £2.01',
      );
    });

    test('lines that cost more at Costco stay at Asda', () {
      final loser = _line(
        'pasta',
        _link(
          'pasta',
          asda: [_asda('a-p', 0.75, q: _g500)],
          costco: [_costco('c-p', 7.99, q: _g3000)],
        ),
      );
      final r = compareBasket([olive(), loser]);
      expect(r.recommendation, Recommendation.split);
      expect(r.splitPlan.costcoLines.map((l) => l.line.itemName), [
        'olive oil',
      ]);
      expect(r.splitPlan.asdaLines.map((l) => l.line.itemName), ['pasta']);
      expect(r.splitPlan.asdaSpend, closeTo(0.75, 1e-9));
      expect(r.splitPlan.asdaFee, 6.0);
      expect(r.splitPlan.fees, closeTo(11.99, 1e-9));
      expect(r.splitPlan.total, closeTo(0.75 + 22.99 + 11.99, 1e-9));
      expect(r.asdaOnlyTotal, closeTo(7.5 + 0.75 + 6, 1e-9));
    });

    test('fresh item with costcoUnavailable is an Asda-only line', () {
      final milk = _line(
        'milk',
        _link(
          'milk',
          asda: [_asda('milk', 1.4, q: _ml1000)],
          costco: [_costco('whatever', 1, q: _ml1000)],
          costcoUnavailable: true,
        ),
      );
      final r = compareBasket([milk]);
      expect(r.lines.single.status, LineStatus.asdaOnly);
      expect(r.recommendation, Recommendation.asdaOnly);
      expect(r.asdaOnlyTotal, closeTo(1.4 + 6, 1e-9));
      expect(r.splitPlan.asdaLines, hasLength(1));
      expect(r.summary, 'Order everything from Asda.');
    });

    test('unlinked and unavailable lines are excluded and counted', () {
      final r = compareBasket([
        olive(),
        _line('mystery', null),
        _line('other', _link('other')),
        _line(
          'gone',
          _link('gone', asdaUnavailable: true, costcoUnavailable: true),
        ),
      ]);
      expect(r.unlinkedCount, 2);
      expect(r.unavailableCount, 1);
      expect(r.lines, hasLength(4));
      expect(r.asdaOnlyTotal, closeTo(7.5 + 6, 1e-9));
      expect(r.splitPlan.costcoLines, hasLength(1));
    });

    test('costco-only line forces a split and says why', () {
      final only = _line(
        'kirkland sauce',
        _link('k', costco: [_costco('c', 3.0, q: _g500)]),
      );
      final r = compareBasket([only]);
      expect(r.recommendation, Recommendation.split);
      expect(r.forcedByCostcoOnly, isTrue);
      expect(r.missingAtAsda.single.line.itemName, 'kirkland sauce');
      expect(r.asdaOnlyTotal, 0);
      expect(r.splitPlan.costcoLines, hasLength(1));
      expect(r.splitPlan.asdaFee, 0);
      expect(r.splitNetSaving, closeTo(-5.99, 1e-9));
      expect(r.summary, contains('1 not available at Asda'));
      expect(r.summary, contains('= -£5.99'));
    });

    test('with a costco-only line, any positive saving also moves', () {
      final only = _line(
        'kirkland sauce',
        _link('k', costco: [_costco('c', 3.0, q: _g500)]),
      );
      final tiny = _line(
        'beans',
        _link(
          'beans',
          asda: [_asda('a', 1.0, q: _g500)],
          costco: [_costco('c2', 5.5, q: _g3000)], // saves £0.50
        ),
      );
      final r = compareBasket([only, tiny]);
      expect(r.splitPlan.costcoLines, hasLength(2));
      expect(r.splitNetSaving, closeTo(0.5 - 5.99, 1e-9));
      expect(r.splitPlan.asdaLines, isEmpty);
    });

    test('qty applies to Asda cost in totals', () {
      final r = compareBasket([
        _line('x', _link('x', asda: [_asda('a', 2.0, q: _g500)]), qty: 3),
      ]);
      expect(r.asdaOnlyItems, closeTo(6, 1e-9));
      expect(r.asdaOnlyTotal, closeTo(12, 1e-9));
    });

    test('asda multibuy is applied to Asda totals', () {
      final r = compareBasket([
        _line(
          'x',
          _link(
            'x',
            asda: [_asda('a', 0.75, q: _g500, promo: 'Any 2 for £1.20')],
          ),
          qty: 3,
        ),
      ]);
      expect(r.asdaOnlyItems, closeTo(1.2 + 0.75, 1e-9));
    });

    test('custom fees', () {
      final r = compareBasket([
        olive(),
      ], fees: const PriceFees(asdaDelivery: 4, costcoDelivery: 20));
      expect(r.asdaOnlyTotal, closeTo(11.5, 1e-9));
      expect(r.splitNetSaving, closeTo(14.51 - 20, 1e-9));
      expect(r.recommendation, Recommendation.asdaOnly);
      expect(r.summary, contains('£20.00 delivery'));
    });

    test('empty basket', () {
      final r = compareBasket(const []);
      expect(r.recommendation, Recommendation.asdaOnly);
      expect(r.asdaOnlyTotal, 0);
      expect(r.splitPlan.total, 0);
      expect(r.summary, 'Nothing to compare yet.');
    });

    test('only unlinked lines', () {
      final r = compareBasket([_line('a', null), _line('b', null)]);
      expect(r.unlinkedCount, 2);
      expect(r.asdaOnlyTotal, 0);
      expect(r.summary, 'Nothing to compare yet.');
    });

    test('multibuy winner flip changes the recommendation', () {
      final costco = _costco('six', 7.20, q: _g3000);
      CompareLine spag(String? promo) => _line(
        'spaghetti',
        _link(
          'spaghetti',
          asda: [_asda('s', 1.5, q: _g500, promo: promo)],
          costco: [costco],
        ),
      );
      // Saving without the deal is 1.80, below the fee either way, so use
      // several lines to push it over only when there is no multibuy.
      final noDeal = compareBasket([
        spag(null),
        spag(null),
        spag(null),
        spag(null),
      ]);
      final deal = compareBasket([
        spag('Any 2 for £2'),
        spag('Any 2 for £2'),
        spag('Any 2 for £2'),
        spag('Any 2 for £2'),
      ]);
      expect(noDeal.recommendation, Recommendation.split);
      expect(deal.recommendation, Recommendation.asdaOnly);
    });
  });
}
