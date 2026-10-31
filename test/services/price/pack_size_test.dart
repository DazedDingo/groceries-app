import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/pack_size.dart';

class _Case {
  final String text;
  final String? field;
  final double? grams;
  final double? ml;
  final double? count;
  final String? unit;
  const _Case(
    this.text, {
    this.field,
    this.grams,
    this.ml,
    this.count,
    this.unit,
  });
}

void main() {
  const pint = 568.261;

  final cases = <_Case>[
    // Costco names
    const _Case('Heinz Baked Beans, 24 x 415g', grams: 9960),
    const _Case('Tilda Pure Basmati Rice, 6 x 250g', grams: 1500),
    const _Case('Valfrutta Chopped Tomatoes, 12 x 400g', grams: 4800),
    const _Case('Hellmann\'s Real Squeezy Mayonnaise, 2 x 750ml', ml: 1500),
    const _Case('Plenish Organic Oat Milk, 8 x 1L', ml: 8000),
    const _Case('Quaker Oat So Simple Original, 60 x 27g', grams: 1620),
    const _Case('Kenco Latte Coffee, 1kg', grams: 1000),
    const _Case('Skippy Smooth Peanut Butter, 1.13kg', grams: 1130),
    const _Case(
      'Kirkland Signature Spanish Extra Virgin Olive Oil, 5L',
      ml: 5000,
    ),
    const _Case('Evan Williams Egg Nog, 70cl', ml: 700),
    const _Case('Gudrun Belgian Chocolates Bag, 427g in 2 Options', grams: 427),
    const _Case(
      'Taylors of Harrogate Yorkshire Tea, 600 Tea Bags',
      count: 600,
      unit: 'bag',
    ),
    const _Case(
      'Twinings English Breakfast Tea Bags, 300 Pack',
      count: 300,
      unit: 'bag',
    ),
    const _Case('Tetley 1 Cup Tea Bags, 1100 Pack', count: 1100, unit: 'bag'),
    const _Case(
      'Kirkland Signature Green Tea Matcha Blend, 100 Tea Bags',
      count: 100,
      unit: 'bag',
    ),
    const _Case(
      'Persil Bio Laundry Liquid, 95 Washes (2.565L)',
      ml: 2565,
      count: 95,
      unit: 'wash',
    ),
    const _Case(
      'Ariel Laundry Liquid, 172 Wash, 4.988L',
      ml: 4988,
      count: 172,
      unit: 'wash',
    ),
    const _Case(
      'Surf Tropical Lily Laundry Liquid, 95 Wash',
      count: 95,
      unit: 'wash',
    ),
    const _Case(
      'Cushelle Quilted 3-Ply Toilet Tissue, 24 Pack (157 Sheets)',
      count: 24,
      unit: 'roll',
    ),
    const _Case(
      'Kirkland Signature Ultra Shine Dishwasher Pacs, 115 Count',
      count: 115,
      unit: 'tablet',
    ),
    const _Case(
      'Finish Quantum All in One Lemon Dishwasher Tablets, 2 x 100 Pack',
      count: 200,
      unit: 'tablet',
    ),
    const _Case('Crystale Dishwasher Salt, 4 x 2kg', grams: 8000),
    const _Case(
      'Finish Dishwasher Fresh Rinse And Shine Aid, 2 x 800ml',
      ml: 1600,
    ),
    const _Case(
      'Bloo Self Active Toilet Rim Blocks, 3 x 3 Pack',
      count: 9,
      unit: 'each',
    ),
    const _Case(
      'Costa Tassimo Americano Coffee Pods, 80 Servings',
      count: 80,
      unit: 'serving',
    ),
    const _Case(
      'Barista Coffee Espresso Shot Hazelnut, 40 capsules',
      count: 40,
      unit: 'capsule',
    ),
    const _Case(
      'Shen Dan Boiled Salted Duck Eggs x 12',
      count: 12,
      unit: 'each',
    ),
    // Plain strings from the brief
    const _Case('500g', grams: 500),
    const _Case('1.5L', ml: 1500),
    const _Case('1 Litre', ml: 1000),
    const _Case('2 Pints', ml: 2 * pint),
    const _Case('60 Washes', count: 60, unit: 'wash'),
    const _Case('8 Rolls', count: 8, unit: 'roll'),
    const _Case('8PK', count: 8, unit: 'each'),
    const _Case('24 Pack', count: 24, unit: 'each'),
    const _Case('48 Pack', count: 48, unit: 'each'),
    const _Case('115 Count', count: 115, unit: 'each'),
    const _Case('2 x 100', count: 200, unit: 'each'),
    const _Case('6 x 250g', grams: 1500),
    const _Case('12 x 400g', grams: 4800),
    const _Case('4 Durable Kitchen Towels Rolls', count: 4, unit: 'roll'),
    // Asda: name + PACK_SIZE
    const _Case(
      'British Milk Semi Skimmed 2 Pints',
      field: '2 PINT',
      ml: 2 * pint,
    ),
    const _Case(
      'Long Life Semi Skimmed Milk 6 x 1 Litre',
      field: '6X1L',
      ml: 6000,
    ),
    const _Case(
      'Tilda Pure Original Basmati Rice 500g',
      field: '500G',
      grams: 500,
    ),
    const _Case(
      'Boil in the Bag Basmati White Rice 4 x 125g (500g)',
      field: '500G',
      grams: 500,
    ),
    const _Case('Baked Beans 4 x 410g', field: '4X410G', grams: 1640),
    const _Case(
      '160 Tea Bags 500g',
      field: '160PK',
      grams: 500,
      count: 160,
      unit: 'bag',
    ),
    const _Case(
      'Everyday 240 Tea Bags 696g',
      field: '240PK',
      grams: 696,
      count: 240,
      unit: 'bag',
    ),
    const _Case(
      'Sensitive Non-Bio Laundry Liquid 60 Washes',
      field: '1.5L',
      ml: 1500,
      count: 60,
      unit: 'wash',
    ),
    const _Case(
      'Non Bio Liquid Detergent 53 washes (1.431 L)',
      field: '1.431L',
      ml: 1431,
      count: 53,
      unit: 'wash',
    ),
    const _Case(
      'All in 1 Citrus Dishwasher Tablets 40 x 14g (560g)',
      field: '40PK',
      grams: 560,
      count: 40,
      unit: 'tablet',
    ),
    const _Case(
      'Ultimate All in 1 Citrus Dishwasher Tablets 40 x 12.5g (500g)',
      field: '40PK',
      grams: 500,
      count: 40,
      unit: 'tablet',
    ),
    const _Case(
      'Quantum All In One Dishwasher Tablets  Fresh - 36 Tabs',
      field: '36PK',
      count: 36,
      unit: 'tablet',
    ),
    const _Case(
      'Original Power  Dishwasher Tablets, Lemon, 84 Capsules',
      field: '84PK',
      count: 84,
      unit: 'tablet',
    ),
    const _Case(
      'Skin Protect Toilet Tissue Standard Rolls 8 Rolls',
      field: '8PK',
      count: 8,
      unit: 'roll',
    ),
    const _Case(
      'So Soft 12 Long-Lasting Rolls',
      field: '12R',
      count: 12,
      unit: 'roll',
    ),
    const _Case(
      'Complete Clean Toilet Tissue 12 MEGA Rolls 50% More sheets',
      field: '12PK',
      count: 12,
      unit: 'roll',
    ),
    // Count only in PACK_SIZE
    const _Case(
      '4 Super Absorbent Power Towels Rolls',
      field: '4 ROLL',
      count: 4,
      unit: 'roll',
    ),
    const _Case('Blitz Household Towel', field: '2PK', count: 2, unit: 'roll'),
    const _Case('Cereal 48 Pack', field: '48PK', count: 48, unit: 'each'),
    const _Case('Corn Flakes 670g', field: '670', grams: 670),
    const _Case(
      'Mutti Finely Chopped Tomatoes 4x400g',
      field: '4X400G',
      grams: 1600,
    ),
  ];

  group('parsePackQuantity table', () {
    for (final c in cases) {
      test('${c.text}${c.field == null ? '' : ' [${c.field}]'}', () {
        final q = parsePackQuantity(c.text, packSizeField: c.field);
        expect(q, isNotNull);
        if (c.grams == null) {
          expect(q!.grams, isNull);
        } else {
          expect(q!.grams, closeTo(c.grams!, 1e-3));
        }
        if (c.ml == null) {
          expect(q.millilitres, isNull);
        } else {
          expect(q.millilitres, closeTo(c.ml!, 1e-3));
        }
        expect(q.count, c.count);
        expect(q.countUnit, c.unit);
      });
    }

    test('table has at least 30 cases', () {
      expect(cases.length, greaterThanOrEqualTo(30));
    });
  });

  group('parsePackQuantity null and edge cases', () {
    test('nothing parses -> null', () {
      expect(parsePackQuantity('Blitz Household Towel'), isNull);
      expect(parsePackQuantity(''), isNull);
      expect(parsePackQuantity('Kellogg\'s Special K'), isNull);
    });

    test('bare numeric PACK_SIZE is not a quantity', () {
      expect(parsePackQuantity('Corn Flakes', packSizeField: '670'), isNull);
    });

    test('blank PACK_SIZE is ignored', () {
      expect(parsePackQuantity('Rice 1kg', packSizeField: '  ')!.grams, 1000);
    });

    test('PACK_SIZE wins for weight over the name', () {
      final q = parsePackQuantity('Thing 400g', packSizeField: '500G');
      expect(q!.grams, 500);
    });

    test('word "Long-Lasting" is not litres', () {
      final q = parsePackQuantity('So Soft 12 Long-Lasting Rolls');
      expect(q!.millilitres, isNull);
      expect(q.count, 12);
    });

    test('PackQuantity map round trip', () {
      const q = PackQuantity(
        grams: 500,
        millilitres: 12.5,
        count: 160,
        countUnit: 'bag',
      );
      expect(PackQuantity.fromMap(q.toMap()), q);
    });
  });
}
