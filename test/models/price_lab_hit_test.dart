import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_lab_hit.dart';

void main() {
  group('parsePriceText', () {
    test('pounds', () {
      expect(parsePriceText('£1.25'), 1.25);
      expect(parsePriceText('£1'), 1.0);
      expect(parsePriceText('£0.50'), 0.5);
      expect(parsePriceText('£1,299.00'), 1299.0);
      expect(parsePriceText('Now £2.10'), 2.10);
    });

    test('pence', () {
      expect(parsePriceText('85p'), 0.85);
      expect(parsePriceText('5p'), 0.05);
      expect(parsePriceText('99P'), 0.99);
    });

    test('plain numbers (JSON-LD style)', () {
      expect(parsePriceText('1.25'), 1.25);
      expect(parsePriceText(' 3 '), 3.0);
    });

    test('null, empty and garbage give null', () {
      expect(parsePriceText(null), isNull);
      expect(parsePriceText(''), isNull);
      expect(parsePriceText('free'), isNull);
      expect(parsePriceText('abc p'), isNull);
    });
  });

  group('PriceLabHit.fromJson', () {
    test('full item', () {
      final h = PriceLabHit.fromJson({
        'source': 'dom',
        'name': 'Asda Milk 2L',
        'price': '£1.25',
        'unitPrice': '62.5p/l',
        'promo': 'Rollback',
        'url': 'https://www.asda.com/groceries/product/123',
        'raw': 'blah',
      });
      expect(h.name, 'Asda Milk 2L');
      expect(h.price, 1.25);
      expect(h.priceText, '£1.25');
      expect(h.unitPriceText, '62.5p/l');
      expect(h.promoText, 'Rollback');
      expect(h.url, contains('/product/'));
      expect(h.source, 'dom');
    });

    test('numeric price from JSON-LD', () {
      final h = PriceLabHit.fromJson({'name': 'x', 'price': 1.5});
      expect(h.price, 1.5);
      expect(h.priceText, '1.5');
    });

    test('missing fields', () {
      final h = PriceLabHit.fromJson({});
      expect(h.name, isNull);
      expect(h.price, isNull);
      expect(h.priceText, isNull);
      expect(h.url, isNull);
    });

    test('odd types and blank strings do not throw', () {
      final h = PriceLabHit.fromJson({
        'name': 42,
        'price': <String>['x'],
        'promo': '  ',
        'url': null,
      });
      expect(h.name, '42');
      expect(h.price, isNull);
      expect(h.promoText, isNull);
    });

    test('listFromJson skips non-maps and tolerates non-lists', () {
      final hits = PriceLabHit.listFromJson([
        {'name': 'a', 'price': '85p'},
        'junk',
        null,
        {'name': 'b'},
      ]);
      expect(hits.length, 2);
      expect(hits.first.price, 0.85);
      expect(PriceLabHit.listFromJson(null), isEmpty);
      expect(PriceLabHit.listFromJson('nope'), isEmpty);
    });

    test('toJson round trips key fields', () {
      final h = PriceLabHit.fromJson({'name': 'a', 'price': '£2'});
      final j = h.toJson();
      expect(j['name'], 'a');
      expect(j['price'], 2.0);
    });
  });
}
