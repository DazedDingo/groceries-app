import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/asda_parser.dart';

final _fetched = DateTime.utc(2026, 10, 31, 12);

Map<String, dynamic> _fixture() =>
    jsonDecode(
          File(
            'test/fixtures/price/asda_algolia_queries.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, dynamic> _hit({
  String cin = '1',
  String brand = 'ASDA',
  String name = 'Thing 500g',
  String status = 'A',
  Map<String, dynamic>? stock = const {'4647': 5},
  Map<String, dynamic>? prices,
  String salesType = 'Each',
  String packSize = '500G',
  List<Map<String, dynamic>>? promos,
}) => {
  'CIN': cin,
  'BRAND': brand,
  'NAME': name,
  'STATUS': status,
  'SALES_TYPE': salesType,
  'PACK_SIZE': packSize,
  'STOCK': ?stock,
  'PRIMARY_TAXONOMY': {'SHELF_NAME': 'Shelf'},
  'PRICES': {
    'EN':
        prices ??
        {'PRICE': 1.0, 'OFFER': 'List', 'PRICEPERUOMFORMATTED': '£2.00/KG'},
  },
  'PROMOS': ?(promos == null ? null : {'EN': promos}),
};

PriceProduct _find(List<PriceProduct> l, String contains) =>
    l.firstWhere((p) => p.name.contains(contains));

void main() {
  final fixture = _fixture();

  group('fixtures', () {
    test('all 12 terms parse to non-empty lists with positive prices', () {
      expect(fixture.length, 12);
      for (final entry in fixture.entries) {
        final out = parseAsdaAlgolia(
          entry.value as Map<String, dynamic>,
          fetchedAt: _fetched,
        );
        expect(out, isNotEmpty, reason: entry.key);
        for (final p in out) {
          expect(p.store, PriceStore.asda);
          expect(p.price, greaterThan(0), reason: '${entry.key}: ${p.name}');
          expect(p.id, isNotEmpty);
          expect(p.name, isNotEmpty);
          expect(p.fetchedAt, _fetched);
          expect(p.url, 'https://www.asda.com/groceries/product/${p.id}');
          if (p.wasPrice != null) expect(p.wasPrice, greaterThan(p.price));
        }
      }
    });

    test('every fixture product with a size has a quantity', () {
      var total = 0;
      var withQty = 0;
      for (final v in fixture.values) {
        for (final p in parseAsdaAlgolia(
          v as Map<String, dynamic>,
          fetchedAt: _fetched,
        )) {
          total++;
          if (p.quantity != null) withQty++;
        }
      }
      expect(total, 72);
      // Only the bare "Blitz Household Towel 2PK/1 ROLL" style lines may lack
      // a quantity.
      expect(withQty, greaterThanOrEqualTo(70));
    });

    test('Taylors 160 tea bags: rollback 4.50, was 6.17', () {
      final p = _find(
        parseAsdaAlgolia(
          fixture['tea bags'] as Map<String, dynamic>,
          fetchedAt: _fetched,
        ),
        '160 Tea Bags 500g',
      );
      expect(p.brand, 'Taylors of Harrogate');
      expect(p.name, 'Taylors of Harrogate 160 Tea Bags 500g');
      expect(p.price, 4.5);
      expect(p.wasPrice, 6.17);
      expect(p.offer, 'Rollback');
      expect(p.quantity!.count, 160);
      expect(p.quantity!.countUnit, 'bag');
      expect(p.quantity!.grams, 500);
      expect(p.storeUnitPriceText, isNotNull);
    });

    test('Napolina spaghetti 500g has the Any 2 for £2 multibuy', () {
      final p = _find(
        parseAsdaAlgolia(
          fixture['spaghetti'] as Map<String, dynamic>,
          fetchedAt: _fetched,
        ),
        'Napolina Spaghetti 500g',
      );
      expect(p.promos, hasLength(1));
      expect(p.promos.single.name, 'Any 2 for £2');
      expect(p.multiBuy!.quantity, 2);
      expect(p.multiBuy!.total, 2);
      expect(p.promos.single.endsAt, isNotNull);
    });

    test('brand is not duplicated when NAME already starts with it', () {
      final milk = parseAsdaAlgolia(
        fixture['milk'] as Map<String, dynamic>,
        fetchedAt: _fetched,
      );
      expect(milk.first.name, 'ASDA British Milk Semi Skimmed 2 Pints');
      expect(milk.first.quantity!.millilitres, closeTo(1136.522, 1e-3));
      final all = fixture.values.expand(
        (v) => parseAsdaAlgolia(v as Map<String, dynamic>, fetchedAt: _fetched),
      );
      for (final p in all) {
        if (p.brand.isNotEmpty) {
          expect(
            p.name.toLowerCase().startsWith(p.brand.toLowerCase()),
            isTrue,
            reason: p.name,
          );
          expect(
            p.name.toLowerCase().startsWith(
              '${p.brand.toLowerCase()} ${p.brand.toLowerCase()}',
            ),
            isFalse,
            reason: p.name,
          );
        }
      }
    });

    test('Dropped with equal WASPRICE has no was price or offer', () {
      final p = _find(
        parseAsdaAlgolia(
          fixture['olive oil'] as Map<String, dynamic>,
          fetchedAt: _fetched,
        ),
        'Extra Virgin Olive Oil 1 Litre',
      );
      expect(p.price, 7.5);
      expect(p.wasPrice, isNull);
      expect(p.offer, isNull);
    });

    test('Dropped with a higher WASPRICE gets a Was label', () {
      final p = _find(
        parseAsdaAlgolia(
          fixture['milk'] as Map<String, dynamic>,
          fetchedAt: _fetched,
        ),
        '6 x 1 Litre',
      );
      expect(p.wasPrice, 6.14);
      expect(p.offer, 'Was £6.14');
    });

    test('List price has no offer', () {
      final p = _find(
        parseAsdaAlgolia(
          fixture['basmati rice'] as Map<String, dynamic>,
          fetchedAt: _fetched,
        ),
        'Microwave Pure Basmati',
      );
      expect(p.offer, isNull);
      expect(p.wasPrice, isNull);
      expect(p.shelf, isNotNull);
      expect(p.inStock, isTrue);
    });
  });

  group('shapes and edge cases', () {
    test('single-index {hits:[...]} shape', () {
      final out = parseAsdaAlgolia({
        'hits': [_hit()],
      }, fetchedAt: _fetched);
      expect(out, hasLength(1));
    });

    test('multi-query shape ignores other indexes', () {
      final out = parseAsdaAlgolia({
        'results': [
          {
            'index': 'OTHER',
            'hits': [_hit(cin: '9')],
          },
          {
            'index': 'ASDA_PRODUCTS',
            'hits': [_hit(cin: '1')],
          },
        ],
      }, fetchedAt: _fetched);
      expect(out.map((p) => p.id), ['1']);
    });

    test('empty / unknown shapes give an empty list', () {
      expect(parseAsdaAlgolia({}, fetchedAt: _fetched), isEmpty);
      expect(parseAsdaAlgolia({'results': []}, fetchedAt: _fetched), isEmpty);
    });

    test('STATUS other than A is ignored', () {
      final out = parseAsdaAlgolia({
        'hits': [_hit(cin: '1'), _hit(cin: '2', status: 'D')],
      }, fetchedAt: _fetched);
      expect(out.map((p) => p.id), ['1']);
    });

    test('inStock: any store with stock > 0, missing STOCK is true', () {
      List<PriceProduct> run(Map<String, dynamic>? stock) => parseAsdaAlgolia({
        'hits': [_hit(stock: stock)],
      }, fetchedAt: _fetched);
      expect(run({'1': 0, '2': 3}).single.inStock, isTrue);
      expect(run({'1': 0, '2': 0}).single.inStock, isFalse);
      expect(run(null).single.inStock, isTrue);
    });

    test('non-positive or missing price is skipped', () {
      final out = parseAsdaAlgolia({
        'hits': [
          _hit(cin: '1', prices: {'PRICE': 0, 'OFFER': 'List'}),
          _hit(cin: '2', prices: {'OFFER': 'List'}),
          _hit(cin: '3'),
        ],
      }, fetchedAt: _fetched);
      expect(out.map((p) => p.id), ['3']);
    });

    test('expired promos are dropped; unknown promos keep their name', () {
      final out = parseAsdaAlgolia({
        'hits': [
          _hit(
            promos: [
              {
                'ID': 'a',
                'NAME': 'Any 2 for £1',
                'END_DATE':
                    DateTime.utc(2026, 1, 1).millisecondsSinceEpoch / 1000,
              },
              {
                'ID': 'b',
                'NAME': 'Clubcard thing',
                'END_DATE':
                    DateTime.utc(2027, 1, 1).millisecondsSinceEpoch / 1000,
              },
            ],
          ),
        ],
      }, fetchedAt: _fetched);
      final p = out.single;
      expect(p.promos.map((x) => x.id), ['b']);
      expect(p.promos.single.multiBuy, isNull);
      expect(p.multiBuy, isNull);
    });

    test('weight-priced lines get no quantity', () {
      final p = parseAsdaAlgolia({
        'hits': [_hit(salesType: 'Weight')],
      }, fetchedAt: _fetched).single;
      expect(p.quantity, isNull);
    });

    test('toMap/fromMap round trip', () {
      final p = _find(
        parseAsdaAlgolia(
          fixture['tea bags'] as Map<String, dynamic>,
          fetchedAt: _fetched,
        ),
        '160 Tea Bags 500g',
      );
      final back = PriceProduct.fromMap(p.toMap());
      expect(back.toMap(), p.toMap());
      expect(back.quantity, p.quantity);
      expect(back.fetchedAt.toUtc(), _fetched);
      final sp = _find(
        parseAsdaAlgolia(
          fixture['spaghetti'] as Map<String, dynamic>,
          fetchedAt: _fetched,
        ),
        'Napolina Spaghetti 500g',
      );
      final sb = PriceProduct.fromMap(sp.toMap());
      expect(sb.multiBuy, sp.multiBuy);
      expect(
        sb.promos.single.endsAt!.toUtc(),
        sp.promos.single.endsAt!.toUtc(),
      );
    });
  });
}
