import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/costco_parser.dart';

final _fetched = DateTime.utc(2026, 10, 31, 12);

Map<String, dynamic> _fixture() =>
    jsonDecode(
          File('test/fixtures/price/costco_search.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, dynamic> _product({
  String code = '1',
  String name = 'Thing, 2 x 500g',
  num? price = 5.0,
  bool membership = false,
  bool business = false,
  bool? purchasable = true,
  String? stock = 'inStock',
}) => {
  'code': code,
  'name': name,
  'price': price == null ? null : {'value': price},
  'membershipRestrictionApplied': membership,
  'businessDelivery': business,
  'purchasable': ?purchasable,
  'stock': {'stockLevelStatus': ?stock},
  'potentialPromotions': [],
  'url': '/x/p/$code',
};

List<PriceProduct> _term(Map<String, dynamic> f, String term) =>
    parseCostcoSearch(f[term] as Map<String, dynamic>, fetchedAt: _fetched);

void main() {
  final fixture = _fixture();

  group('fixtures', () {
    test('every term parses; prices positive; urls absolute', () {
      for (final term in fixture.keys) {
        final out = _term(fixture, term);
        for (final p in out) {
          expect(p.store, PriceStore.costco);
          expect(p.brand, '');
          expect(p.price, greaterThan(0));
          expect(p.url, startsWith('https://www.costco.co.uk/'));
          expect(p.inStock, isTrue);
          expect(p.wasPrice, isNull);
        }
      }
      expect(_term(fixture, 'kitchen roll'), isEmpty);
    });

    test('milk term has no Cravendale (business delivery)', () {
      final out = _term(fixture, 'milk');
      expect(out, isNotEmpty);
      expect(out.any((p) => p.name.contains('Cravendale')), isFalse);
    });

    test('Heinz 24 x 415g is 9960 g at £15.29', () {
      final p = _term(
        fixture,
        'baked beans',
      ).firstWhere((p) => p.name.startsWith('Heinz'));
      expect(p.id, '3074');
      expect(p.price, 15.29);
      expect(p.quantity!.grams, 9960);
      expect(p.url, startsWith('https://www.costco.co.uk/Grocery-Household/'));
    });

    test('tea: Yorkshire 600 bags', () {
      final p = _term(fixture, 'tea bags').first;
      expect(p.price, 14.99);
      expect(p.quantity!.count, 600);
      expect(p.quantity!.countUnit, 'bag');
    });

    test('laundry: Persil 95 washes 2565 ml', () {
      final p = _term(
        fixture,
        'washing liquid',
      ).firstWhere((p) => p.name.startsWith('Persil Bio'));
      expect(p.quantity!.count, 95);
      expect(p.quantity!.countUnit, 'wash');
      expect(p.quantity!.millilitres, closeTo(2565, 1e-6));
    });

    test('olive oil: Kirkland 5L £22.99 (no pricePerUnit)', () {
      final p = _term(
        fixture,
        'olive oil',
      ).firstWhere((p) => p.name.startsWith('Kirkland'));
      expect(p.price, 22.99);
      expect(p.quantity!.millilitres, 5000);
    });

    test('dishwasher: Kirkland 115 tablets, Finish 2 x 100', () {
      final out = _term(fixture, 'dishwasher tablets');
      final k = out.firstWhere((p) => p.name.startsWith('Kirkland'));
      expect(k.quantity!.count, 115);
      expect(k.quantity!.countUnit, 'tablet');
      final f = out.firstWhere((p) => p.name.startsWith('Finish Quantum'));
      expect(f.quantity!.count, 200);
      expect(f.quantity!.countUnit, 'tablet');
    });

    test('toilet tissue: Cushelle 24 rolls', () {
      final p = _term(fixture, 'toilet tissue').first;
      expect(p.quantity!.count, 24);
      expect(p.quantity!.countUnit, 'roll');
    });

    test('purchasable=false product (Gudrun chocolates) is dropped', () {
      expect(
        _term(fixture, 'eggs').any((p) => p.name.contains('Gudrun')),
        isFalse,
      );
    });

    test('round trip', () {
      final p = _term(fixture, 'baked beans').first;
      final back = PriceProduct.fromMap(p.toMap());
      expect(back.toMap(), p.toMap());
      expect(back.store, PriceStore.costco);
    });
  });

  group('filtering', () {
    List<PriceProduct> run(List<Map<String, dynamic>> products) =>
        parseCostcoSearch({'products': products}, fetchedAt: _fetched);

    test('membership-restricted, business, unpriced are dropped', () {
      final out = run([
        _product(code: '1'),
        _product(code: '2', membership: true),
        _product(code: '3', business: true),
        _product(code: '4', price: null),
        _product(code: '5', price: 0),
        _product(code: '6', purchasable: false),
      ]);
      expect(out.map((p) => p.id), ['1']);
    });

    test('out of stock is kept but flagged', () {
      final out = run([_product(stock: 'outOfStock')]);
      expect(out.single.inStock, isFalse);
    });

    test('missing products key / empty list', () {
      expect(parseCostcoSearch({}, fetchedAt: _fetched), isEmpty);
      expect(run([]), isEmpty);
    });

    test('name is kept as is and brand is empty', () {
      final p = run([_product(name: 'Heinz Baked Beans, 24 x 415g')]).single;
      expect(p.name, 'Heinz Baked Beans, 24 x 415g');
      expect(p.brand, '');
      expect(p.url, 'https://www.costco.co.uk/x/p/1');
    });
  });
}
