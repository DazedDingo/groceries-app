import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_link.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/asda_parser.dart';
import 'package:groceries_app/services/price/auto_match.dart';
import 'package:groceries_app/services/price/costco_parser.dart';
import 'package:groceries_app/services/price/price_compare.dart';

final _fetched = DateTime.utc(2026, 10, 31, 12);

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

final Map<String, dynamic> _asdaFixture = _json(
  'test/fixtures/price/asda_algolia_queries.json',
);
final Map<String, dynamic> _costcoFixture = _json(
  'test/fixtures/price/costco_search.json',
);

List<PriceProduct> _asdaTerm(String term) => _asdaFixture.containsKey(term)
    ? parseAsdaAlgolia(
        _asdaFixture[term] as Map<String, dynamic>,
        fetchedAt: _fetched,
      )
    : const [];

List<PriceProduct> _costcoTerm(String term) => _costcoFixture.containsKey(term)
    ? parseCostcoSearch(
        _costcoFixture[term] as Map<String, dynamic>,
        fetchedAt: _fetched,
      )
    : const [];

AutoMatchResult _match(String item, {String? asdaKey, String? costcoKey}) =>
    autoMatch(
      item,
      asda: _asdaTerm(asdaKey ?? item),
      costco: _costcoTerm(costcoKey ?? item),
      now: _fetched,
    );

List<String> _names(List<PriceProduct> l) => l.map((p) => p.name).toList();

// Asda search term -> Costco fixture key for the same item.
const _costcoKeyFor = {
  'milk': 'milk',
  'basmati rice': 'basmati rice',
  'toilet roll': 'toilet tissue',
  'kitchen roll': 'kitchen roll',
  'spaghetti': 'pasta',
  'baked beans': 'baked beans',
  'chopped tomatoes': 'chopped tomatoes',
  'tea bags': 'tea bags',
  'olive oil': 'olive oil',
  'laundry liquid': 'washing liquid',
  'dishwasher tablets': 'dishwasher tablets',
  'cereal': 'cereal',
};

PriceProduct _prod(
  PriceStore store,
  String id,
  String name,
  double price, {
  String brand = '',
  PackQuantity? q,
  String? shelf,
  String? aisle,
  String? dept,
  bool inStock = true,
}) => PriceProduct(
  store: store,
  id: id,
  brand: brand,
  name: name,
  price: price,
  quantity: q,
  shelf: shelf,
  aisle: aisle,
  dept: dept,
  inStock: inStock,
  fetchedAt: _fetched,
);

void main() {
  group('fixtures: Asda side', () {
    test('milk: semi skimmed shelf only, sized like the 2 pint anchor', () {
      final r = _match('milk');
      expect(r.asdaConfidence, MatchConfidence.high);
      expect(_names(r.link.asda), [
        'ASDA British Milk Semi Skimmed 2 Pints',
        'Cravendale Arla  Filtered Fresh Semi Skimmed Milk 1L Fresher for Longer',
      ]);
      expect(r.link.asda.every((p) => p.shelf == 'Semi Skimmed Milk'), isTrue);
      expect(r.link.mode, LinkMode.anyOf);
    });

    test('semi-skimmed variants are one token (hyphen, spacing)', () {
      for (final item in ['semi skimmed milk', 'semi-skimmed milk']) {
        final r = _match(item, asdaKey: 'milk', costcoKey: 'milk');
        expect(r.link.asda.first.name, contains('Semi Skimmed'), reason: item);
      }
      final skim = _match('skimmed milk', asdaKey: 'milk', costcoKey: 'milk');
      expect(skim.link.asda.single.name, contains('Skimmed 2 Pints'));
      expect(skim.link.asda.single.name, isNot(contains('Semi')));
    });

    test('toilet roll / loo roll land on the Asda toilet roll shelf', () {
      for (final item in ['toilet roll', 'loo roll', 'toilet tissue']) {
        final r = _match(item, asdaKey: 'toilet roll');
        expect(r.asdaConfidence, MatchConfidence.high, reason: item);
        expect(r.link.asda, isNotEmpty);
        expect(r.link.asda.first.name, contains('Toilet Tissue'));
        expect(
          r.link.asda.every((p) => p.shelf!.contains('Toilet Roll')),
          isTrue,
          reason: item,
        );
      }
    });

    test('kitchen roll / kitchen towel: Asda kitchen roll shelf', () {
      for (final item in ['kitchen roll', 'kitchen towel']) {
        final r = _match(item, asdaKey: 'kitchen roll');
        expect(r.link.asda.map((p) => p.shelf).toSet(), {
          'View All Kitchen Roll',
        });
        expect(r.link.asda.length, 2); // 4 roll anchor, 2 roll is 0.5x
      }
    });

    test('pack size filter drops far-off sizes (dishwasher 84 capsules)', () {
      final r = _match('dishwasher tablets');
      expect(r.link.asda.first.name, contains('ASDA All in 1 Citrus'));
      final names = _names(r.link.asda);
      expect(names.any((n) => n.contains('84 Capsules')), isFalse); // 2.1x
      expect(names.any((n) => n.contains('49 Capsules')), isTrue);
      expect(names.any((n) => n.contains('36 Tabs')), isTrue);
    });

    test('laundry liquid drops the 24 wash Surf (0.4x of 60 washes)', () {
      final r = _match('laundry liquid');
      final names = _names(r.link.asda);
      expect(names.any((n) => n.contains('Surf')), isFalse);
      expect(names.length, 5);
    });

    test('chopped tomatoes: garlic variant is not offered, size filter', () {
      final r = _match('chopped tomatoes');
      expect(_names(r.link.asda), [
        'Napolina Chopped Tomatoes in a Rich Tomato Juice 4 x 400g',
        'Mutti Finely Chopped Tomatoes 4x400g',
      ]);
    });

    test('tea bags: Asda tea shelf, in stock, no peppermint or 40 pack', () {
      final r = _match('tea bags');
      // Both Tetley packs are out of stock in the fixture.
      expect(_names(r.link.asda), [
        'Taylors of Harrogate 160 Tea Bags 500g',
        'ASDA Everyday 240 Tea Bags 696g',
      ]);
    });
  });

  group('fixtures: Costco side', () {
    test('milk: Costco none (Milo, coconut, oat, formula all rejected)', () {
      final r = _match('milk');
      expect(r.link.costco, isEmpty);
      expect(r.costcoConfidence, MatchConfidence.none);
      expect(r.costcoRejectReason, isNotNull);
      expect(r.costcoRejectReason, contains('modifier guard'));
    });

    test('baked beans: Heinz + Branston 24 packs, never coffee beans', () {
      final r = _match('baked beans');
      expect(_names(r.link.costco), [
        'Heinz Baked Beans, 24 x 415g',
        'Branston Baked Beans In Tomato Sauce, 24 x 410g',
      ]);
      expect(r.costcoConfidence, MatchConfidence.high);
      expect(r.costcoRejectReason, isNull);
      expect(r.brand, isNull);
      expect(r.link.mode, LinkMode.anyOf);
    });

    test('heinz baked beans: brand lock at both stores', () {
      final r = _match(
        'heinz baked beans',
        asdaKey: 'baked beans',
        costcoKey: 'baked beans',
      );
      expect(r.brand, 'heinz');
      expect(_names(r.link.costco), ['Heinz Baked Beans, 24 x 415g']);
      expect(r.link.asda, isNotEmpty);
      expect(r.link.asda.every((p) => p.brand == 'Heinz'), isTrue);
      // The first Heinz result is the Barbecue variant; it is skipped.
      expect(r.link.asda.first.name, isNot(contains('Barbecue')));
      expect(r.link.asda.first.name, 'Heinz Baked Beans 4 x 415g');
    });

    test('tea bags: Yorkshire / Tetley / Twinings, never green matcha', () {
      final r = _match('tea bags');
      expect(_names(r.link.costco), [
        'Taylors of Harrogate Yorkshire Tea, 600 Tea Bags',
        'Twinings English Breakfast Tea Bags, 300 Pack',
        'Tetley 1 Cup Tea Bags, 1100 Pack',
      ]);
      expect(
        chooseBasis(r.link.asda.first.quantity, r.link.costco.first.quantity),
        CompareBasis.bag,
      );
    });

    test('yorkshire tea bags: brand lock keeps tea bags as the product', () {
      final r = _match(
        'yorkshire tea bags',
        asdaKey: 'tea bags',
        costcoKey: 'tea bags',
      );
      expect(r.brand, 'yorkshire tea');
      expect(_names(r.link.costco), [
        'Taylors of Harrogate Yorkshire Tea, 600 Tea Bags',
      ]);
      expect(r.link.asda.single.name, contains('40 Yorkshire Tea Bags'));
    });

    test('olive oil: chilli flavoured oil excluded', () {
      final r = _match('olive oil');
      expect(_names(r.link.costco), [
        '1896 Extra Virgin Olive Oil, 1L',
        'Filippo Berio Classic Olive Oil, 5L',
        'Kirkland Signature Spanish Extra Virgin Olive Oil, 5L',
      ]);
    });

    test('pasta: gluten free pack rejected; spaghetti counts as pasta', () {
      final r = _match('pasta', asdaKey: 'spaghetti', costcoKey: 'pasta');
      expect(_names(r.link.costco), ['La Molisana Spaghetti, 6 x 500g']);
      expect(r.link.asda.first.name, 'Napolina Spaghetti 500g');
    });

    test('spaghetti: matches La Molisana only', () {
      final r = _match('spaghetti', costcoKey: 'pasta');
      expect(_names(r.link.costco), ['La Molisana Spaghetti, 6 x 500g']);
    });

    test('toilet roll / loo roll: Cushelle, not Andrex wipes or Bloo', () {
      for (final item in ['toilet roll', 'loo roll']) {
        final r = _match(
          item,
          asdaKey: 'toilet roll',
          costcoKey: 'toilet tissue',
        );
        expect(_names(r.link.costco), [
          'Cushelle Quilted 3-Ply Toilet Tissue, 24 Pack (157 Sheets)',
        ], reason: item);
      }
    });

    test('dishwasher tablets: Finish + Kirkland, not salt or rinse aid', () {
      final r = _match('dishwasher tablets');
      expect(_names(r.link.costco), [
        'Finish Quantum All in One Lemon Dishwasher Tablets, 2 x 100 Pack',
        'Kirkland Signature Ultra Shine Dishwasher Pacs, 115 Count',
      ]);
      expect(
        chooseBasis(r.link.asda.first.quantity, r.link.costco.first.quantity),
        CompareBasis.tablet,
      );
    });

    test('dishwasher tabs / pods / pacs alias to tablets', () {
      for (final item in [
        'dishwasher tabs',
        'dishwasher pods',
        'dishwasher pacs',
      ]) {
        final r = _match(
          item,
          asdaKey: 'dishwasher tablets',
          costcoKey: 'dishwasher tablets',
        );
        expect(r.link.costco.length, 2, reason: item);
        expect(r.link.asda, isNotEmpty, reason: item);
      }
    });

    test('laundry liquid matches Costco washing liquid (basis wash)', () {
      for (final item in ['laundry liquid', 'washing liquid', 'detergent']) {
        final r = _match(
          item,
          asdaKey: 'laundry liquid',
          costcoKey: 'washing liquid',
        );
        expect(r.link.costco.length, 4, reason: item);
        expect(
          chooseBasis(r.link.asda.first.quantity, r.link.costco.first.quantity),
          CompareBasis.wash,
          reason: item,
        );
      }
    });

    test('washing up liquid is not laundry liquid', () {
      final r = autoMatch(
        'washing up liquid',
        asda: const [],
        costco: _costcoTerm('washing liquid'),
        now: _fetched,
      );
      expect(r.link.costco, isEmpty);
    });

    test('chicken breast: Costco none (Whiskas rejected)', () {
      final r = _match('chicken breast');
      expect(r.link.asda, isEmpty);
      expect(r.asdaConfidence, MatchConfidence.none);
      expect(r.link.costco, isEmpty);
      expect(r.costcoConfidence, MatchConfidence.none);
      expect(
        r.costcoRejectReason,
        'no Costco product matched all of: chicken, breast',
      );
      expect(r.link.mode, LinkMode.exact);
    });

    test('baked beans reject reason when nothing has both words', () {
      final r = autoMatch(
        'baked beans',
        asda: _asdaTerm('baked beans'),
        costco: _costcoTerm('baked beans').skip(2).toList(),
        now: _fetched,
      );
      expect(
        r.costcoRejectReason,
        'no Costco product matched all of: baked, bean',
      );
    });

    test('kitchen roll: Costco none (no results)', () {
      final r = _match('kitchen roll');
      expect(r.link.costco, isEmpty);
      expect(r.costcoRejectReason, 'no Costco results');
      expect(r.link.asda, isNotEmpty);
    });

    test('chopped tomatoes: organic and peeled plum rejected', () {
      final r = _match('chopped tomatoes');
      expect(_names(r.link.costco), ['Valfrutta Chopped Tomatoes, 12 x 400g']);
    });

    test('basmati rice: Tilda 6 x 250g', () {
      final r = _match('basmati rice');
      expect(_names(r.link.costco), ['Tilda Pure Basmati Rice, 6 x 250g']);
    });

    test('cereal: Costco names lack the word, so no match', () {
      final r = _match('cereal');
      expect(r.link.costco, isEmpty);
    });
  });

  group('normalisation and brand detection', () {
    final asda = [
      _prod(
        PriceStore.asda,
        'a',
        "Kellogg's Corn Flakes 670g",
        2.85,
        brand: "Kellogg's",
        shelf: 'Cereal',
        q: const PackQuantity(grams: 670),
      ),
    ];
    final costco = [
      _prod(
        PriceStore.costco,
        'c',
        "Kellogg's Corn Flakes, 2 x 720g",
        5.0,
        q: const PackQuantity(grams: 1440),
      ),
    ];

    test("kellogg's / kelloggs / Kellogg corn flakes all lock Kellogg's", () {
      for (final item in [
        "Kellogg's corn flakes",
        'kelloggs corn flakes',
        'kellogg corn flakes',
      ]) {
        final r = autoMatch(item, asda: asda, costco: costco, now: _fetched);
        expect(r.brand, 'kelloggs', reason: item);
        expect(r.link.costco.length, 1, reason: item);
      }
    });

    test('plural folding: rolls/bags/tomatoes/beans/washes/tablets', () {
      final r = autoMatch(
        'tomatoes',
        asda: [
          _prod(
            PriceStore.asda,
            'a',
            'Cherry Tomato 250g',
            1.0,
            shelf: 's',
            q: const PackQuantity(grams: 250),
          ),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(r.asdaConfidence, MatchConfidence.high);
    });

    test('glass and swiss are not singularised', () {
      final r = autoMatch(
        'swiss glass',
        asda: [_prod(PriceStore.asda, 'a', 'Swiss Glass 1', 1.0, shelf: 's')],
        costco: const [],
        now: _fetched,
      );
      expect(r.asdaConfidence, MatchConfidence.high);
      expect(
        autoMatch(
          'swis glas',
          asda: r.link.asda,
          costco: const [],
        ).asdaConfidence,
        MatchConfidence.low,
      );
    });

    test('brand match is whole-token: "surfboard" does not lock Surf', () {
      final r = autoMatch('surfboard', asda: const [], costco: const []);
      expect(r.brand, isNull);
    });

    test('brands present on Asda results are detected', () {
      final r = autoMatch(
        'ben original microwave rice',
        asda: _asdaTerm('basmati rice'),
        costco: const [],
        now: _fetched,
      );
      expect(r.brand, 'bens original');
      expect(r.link.asda.single.name, contains('Bens Original'));
    });

    test('asda in the item locks Asda to own-brand, Costco open', () {
      final r = _match(
        'asda olive oil',
        asdaKey: 'olive oil',
        costcoKey: 'olive oil',
      );
      expect(r.brand, 'asda');
      expect(r.link.asda, isNotEmpty);
      expect(r.link.asda.every((p) => p.brand.contains('ASDA')), isTrue);
      expect(r.link.asda.any((p) => p.brand == 'Filippo Berio'), isFalse);
      expect(r.link.costco.length, 3);
    });

    test('brand lock with no brand match at Asda gives none', () {
      final r = _match(
        'heinz olive oil',
        asdaKey: 'olive oil',
        costcoKey: 'olive oil',
      );
      expect(r.brand, 'heinz');
      expect(r.link.asda, isEmpty);
      expect(r.asdaConfidence, MatchConfidence.none);
      expect(r.link.costco, isEmpty);
      expect(r.costcoConfidence, MatchConfidence.none);
    });

    test('item with only a brand: Costco stays empty', () {
      final r = _match(
        'heinz',
        asdaKey: 'baked beans',
        costcoKey: 'baked beans',
      );
      expect(r.asdaConfidence, MatchConfidence.low);
      expect(r.link.costco, isEmpty);
      expect(r.costcoRejectReason, contains('no product words'));
    });
  });

  group('asda edge cases', () {
    PriceProduct a(
      String id,
      String name,
      double price, {
      PackQuantity? q,
      String? shelf = 'S',
      bool inStock = true,
    }) => _prod(
      PriceStore.asda,
      id,
      name,
      price,
      q: q,
      shelf: shelf,
      inStock: inStock,
    );

    test('no result contains every token: first result, low confidence', () {
      final r = autoMatch(
        'oat milk',
        asda: [
          a(
            '1',
            'Hemp Drink 1L',
            1.0,
            q: const PackQuantity(millilitres: 1000),
          ),
          a(
            '2',
            'Hazelnut Drink 1L',
            1.1,
            q: const PackQuantity(millilitres: 1000),
          ),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(r.asdaConfidence, MatchConfidence.low);
      expect(r.link.asda.map((p) => p.id), ['1', '2']);
    });

    test('anchor without quantity: same shelf only', () {
      final r = autoMatch(
        'bread',
        asda: [
          a('1', 'White Bread', 1.0),
          a('2', 'Brown Bread 800g', 1.2, q: const PackQuantity(grams: 800)),
          a('3', 'Seeded Bread', 1.5, shelf: 'Other'),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(r.link.asda.map((p) => p.id), ['1', '2']);
    });

    test('0.5x and 2x boundaries are inclusive, beyond is dropped', () {
      PackQuantity g(double v) => PackQuantity(grams: v);
      final r = autoMatch(
        'rice',
        asda: [
          a('anchor', 'Rice 1kg', 1.0, q: g(1000)),
          a('half', 'Rice 500g', 1.0, q: g(500)),
          a('double', 'Rice 2kg', 1.0, q: g(2000)),
          a('small', 'Rice 499g', 1.0, q: g(499)),
          a('big', 'Rice 2.01kg', 1.0, q: g(2010)),
          a('noqty', 'Rice loose', 1.0),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(r.link.asda.map((p) => p.id), ['anchor', 'half', 'double']);
    });

    test('out of stock excluded unless nothing else remains', () {
      PackQuantity g(double v) => PackQuantity(grams: v);
      final mixed = autoMatch(
        'rice',
        asda: [
          a('1', 'Rice 1kg', 1.0, q: g(1000), inStock: false),
          a('2', 'Rice 1kg Long', 1.0, q: g(1000)),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(mixed.link.asda.map((p) => p.id), ['2']);
      final allOut = autoMatch(
        'rice',
        asda: [
          a('1', 'Rice 1kg', 1.0, q: g(1000), inStock: false),
          a('2', 'Rice 1kg Long', 1.0, q: g(1000), inStock: false),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(allOut.link.asda.map((p) => p.id), ['1', '2']);
    });

    test('empty inputs give an empty exact link and no exception', () {
      final r = autoMatch('milk', asda: const [], costco: const []);
      expect(r.link.asda, isEmpty);
      expect(r.link.costco, isEmpty);
      expect(r.link.mode, LinkMode.exact);
      expect(r.link.itemKey, 'milk');
      expect(r.asdaConfidence, MatchConfidence.none);
      expect(r.costcoConfidence, MatchConfidence.none);
    });
  });

  group('sibling shelves in the same aisle', () {
    PriceProduct a(
      String id,
      String name,
      double price, {
      required String shelf,
      String aisle = 'Aisle',
      PackQuantity? q,
      bool inStock = true,
    }) => _prod(
      PriceStore.asda,
      id,
      name,
      price,
      q: q,
      shelf: shelf,
      aisle: aisle,
      inStock: inStock,
    );
    PackQuantity rolls(double n) => PackQuantity(count: n, countUnit: 'roll');
    PackQuantity ml(double n) => PackQuantity(millilitres: n);

    List<String> ids(AutoMatchResult r) =>
        r.link.asda.map((p) => p.id).toList();

    test('toilet roll picks up small and standard shelves within 0.5x-2x', () {
      final r = autoMatch(
        'toilet roll',
        asda: [
          a(
            'anchor',
            'Andrex Toilet Tissue 8 Rolls',
            10,
            shelf: 'Medium Pack',
            q: rolls(8),
          ),
          a(
            'small4',
            'Andrex Toilet Tissue 4 Rolls',
            2.48,
            shelf: 'Small Pack',
            q: rolls(4),
          ),
          a(
            'small2',
            'Andrex Toilet Tissue 2 Rolls',
            1.5,
            shelf: 'Small Pack',
            q: rolls(2),
          ),
          a(
            'std12',
            'So Soft 12 Long-Lasting Rolls',
            9,
            shelf: 'Standard Toilet Roll',
            q: rolls(12),
          ),
          a(
            'std6',
            'So Soft 6 Long-Lasting Rolls',
            4.83,
            shelf: 'Standard Toilet Roll',
            q: rolls(6),
          ),
          a(
            'std24',
            'So Soft 24 Long-Lasting Rolls',
            15,
            shelf: 'Standard Toilet Roll',
            q: rolls(24),
          ),
          a(
            'other',
            'Kitchen Towel Roll',
            2,
            shelf: 'Kitchen',
            aisle: 'Other aisle',
            q: rolls(8),
          ),
          a('nocore', 'Moist Wipes 8 Rolls', 2, shelf: 'Wipes', q: rolls(8)),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(r.asdaConfidence, MatchConfidence.high);
      // 2 rolls (0.25x) and 24 rolls (3x) are out of the window; a product
      // missing a core word or in another aisle is never taken.
      expect(ids(r), ['anchor', 'small4', 'std12', 'std6']);
      expect(r.link.mode, LinkMode.anyOf);
    });

    test('sibling shelves need an aisle on the anchor and a quantity', () {
      final noAisle = autoMatch(
        'toilet roll',
        asda: [
          _prod(
            PriceStore.asda,
            'anchor',
            'Toilet Roll 8 Rolls',
            1,
            shelf: 'A',
            q: rolls(8),
          ),
          _prod(
            PriceStore.asda,
            'sib',
            'Toilet Roll 6 Rolls',
            1,
            shelf: 'B',
            q: rolls(6),
          ),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(ids(noAisle), ['anchor']);
      final noQty = autoMatch(
        'toilet roll',
        asda: [
          a('anchor', 'Toilet Roll Jumbo', 1, shelf: 'A'),
          a('sib', 'Toilet Roll 6 Rolls', 1, shelf: 'B', q: rolls(6)),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(ids(noQty), ['anchor']);
    });

    test('milk stays semi skimmed: whole, skimmed, 1% are rejected', () {
      final r = autoMatch(
        'milk',
        asda: [
          a(
            'semi',
            'British Milk Semi Skimmed 2 Pints',
            1.2,
            shelf: 'Semi Skimmed Milk',
            q: ml(1136),
          ),
          a(
            'semi1l',
            'Semi-Skimmed Milk 1L',
            1.1,
            shelf: 'Other Semi Shelf',
            q: ml(1000),
          ),
          a(
            'whole',
            'British Whole Milk 2 Pints',
            1.2,
            shelf: 'Whole Milk',
            q: ml(1136),
          ),
          a(
            'skim',
            'British Milk Skimmed 2 Pints',
            1.2,
            shelf: 'Skimmed & 1% Fat Milk',
            q: ml(1136),
          ),
          a(
            'one',
            'Fat Free 1% Milk 2 Pints',
            1.2,
            shelf: 'Skimmed & 1% Fat Milk',
            q: ml(1136),
          ),
          a(
            'lactose',
            'Lactose Free Milk 1L',
            1.5,
            shelf: 'Free From Milk',
            q: ml(1000),
          ),
          a('plain', 'Fresh Milk 1L', 1.0, shelf: 'Plain Shelf', q: ml(1000)),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(ids(r), ['semi', 'semi1l']);
    });

    test('whole milk anchor takes only whole siblings', () {
      final r = autoMatch(
        'whole milk',
        asda: [
          a(
            'w1',
            'British Whole Milk 2 Pints',
            1.2,
            shelf: 'Whole Milk',
            q: ml(1136),
          ),
          a(
            'w2',
            'Organic Whole Milk 2 Pints',
            1.9,
            shelf: 'Organic',
            q: ml(1136),
          ),
          a('w3', 'Jersey Whole Milk 1L', 1.6, shelf: 'Jersey', q: ml(1000)),
          a(
            'semi',
            'Semi Skimmed Milk 2 Pints',
            1.2,
            shelf: 'Semi',
            q: ml(1136),
          ),
        ],
        costco: const [],
        now: _fetched,
      );
      // Organic is both a modifier and a variant; Jersey is plain whole.
      expect(ids(r), ['w1', 'w3']);
    });

    test('olive oil and extra virgin olive oil do not mix across shelves', () {
      final r = autoMatch(
        'olive oil',
        asda: [
          a('plain', 'Olive Oil 1 Litre', 7, shelf: 'Olive Oil', q: ml(1000)),
          a(
            'plain2',
            'Light Olive Oil 1 Litre',
            7,
            shelf: 'Cooking Oils',
            q: ml(1000),
          ),
          a(
            'plain3',
            'Pure Olive Oil 750ml',
            5,
            shelf: 'Cooking Oils',
            q: ml(750),
          ),
          a(
            'evoo',
            'Extra Virgin Olive Oil 1 Litre',
            7.5,
            shelf: 'Premium Oils',
            q: ml(1000),
          ),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(ids(r), ['plain', 'plain3']);
    });

    test('sensitive non-bio does not mix with bio or plain', () {
      PackQuantity washes(double n, double l) =>
          PackQuantity(count: n, countUnit: 'wash', millilitres: l);
      final r = autoMatch(
        'laundry liquid',
        asda: [
          a(
            'sens',
            'Sensitive Non-Bio Laundry Liquid 60 Washes',
            2.84,
            shelf: 'Sensitive',
            q: washes(60, 1500),
          ),
          a(
            'sens2',
            'Sensitive Non Bio Laundry Liquid 50 Washes',
            3,
            shelf: 'Gentle',
            q: washes(50, 1250),
          ),
          a(
            'bio',
            'Bio Laundry Liquid 60 Washes',
            3,
            shelf: 'Bio',
            q: washes(60, 1500),
          ),
          a(
            'nonbio',
            'Non Bio Laundry Liquid 60 Washes',
            3,
            shelf: 'Gentle',
            q: washes(60, 1500),
          ),
          a(
            'plain',
            'Tropical Laundry Liquid 60 Washes',
            2.84,
            shelf: 'Fresh',
            q: washes(60, 1500),
          ),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(ids(r), ['sens', 'sens2']);
    });

    test('brand lock still applies to sibling shelves', () {
      final r = autoMatch(
        'heinz tomato soup',
        asda: [
          a(
            'h1',
            'Heinz Tomato Soup 400g',
            1,
            shelf: 'Soup',
            q: const PackQuantity(grams: 400),
          ),
          a(
            'h2',
            'Heinz Cream of Tomato Soup 300g',
            1,
            shelf: 'Cream Soup',
            q: const PackQuantity(grams: 300),
          ),
          a(
            'b1',
            'Baxters Tomato Soup 400g',
            1,
            shelf: 'Cream Soup',
            q: const PackQuantity(grams: 400),
          ),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(r.brand, 'heinz');
      expect(ids(r), ['h1', 'h2']);
    });

    test('fixture: olive oil keeps one pick because the rest are sold out', () {
      final all = _asdaTerm('olive oil');
      final r = _match('olive oil');
      expect(r.link.asda.single.name, 'ASDA Olive Oil 1 Litre');
      // Every dropped product is out of stock (STOCK 0), including all the
      // extra virgin ones, so the variant guard is not what trims this list.
      final dropped = all.where((p) => p.id != r.link.asda.single.id);
      expect(dropped, isNotEmpty);
      expect(dropped.every((p) => !p.inStock), isTrue);
    });

    test('fixture: toilet roll widens across aisles via the dept', () {
      final all = _asdaTerm('toilet roll');
      expect(all.map((p) => p.aisle).toSet().length, 3);
      expect(all.map((p) => p.dept).toSet(), {'Toilet Roll'});
      for (final item in ['toilet roll', 'loo roll']) {
        final r = _match(item, asdaKey: 'toilet roll');
        expect(_names(r.link.asda), [
          'Andrex Skin Protect Toilet Tissue Standard Rolls 8 Rolls',
          'Andrex Skin Protect Toilet Tissue Standard Rolls 4 Rolls',
          'Shades by ASDA So Soft 12 Long-Lasting Rolls',
          'Shades by ASDA So Soft 6 Long-Lasting Rolls',
          'Andrex Complete Clean Toilet Tissue 12 MEGA Rolls 50% More sheets',
          'Andrex Complete Clean Toilet Tissue 6 MEGA Rolls 50% More sheets',
        ], reason: item);
        expect(r.link.mode, LinkMode.anyOf);
      }
    });

    test('dept widening needs the dept name to be only the item', () {
      PackQuantity ml(double n) => PackQuantity(millilitres: n);
      PriceProduct m(String id, String name, String aisle, String shelf) =>
          _prod(
            PriceStore.asda,
            id,
            name,
            1,
            q: ml(1000),
            shelf: shelf,
            aisle: aisle,
            dept: 'Milk, Butter, Cream & Eggs',
          );
      final r = autoMatch(
        'milk',
        asda: [
          m('semi', 'Semi Skimmed Milk 1L', 'Fresh Milk', 'Semi'),
          m('long', 'Long Life Semi Skimmed Milk 1L', 'Long Life Milk', 'LL'),
        ],
        costco: const [],
        now: _fetched,
      );
      expect(r.link.asda.map((p) => p.id), ['semi']);
    });

    test('fixture: milk crosses shelves in Fresh Milk but only semi', () {
      final all = _asdaTerm('milk');
      expect(
        all
            .where((p) => p.aisle == 'Fresh Milk')
            .map((p) => p.shelf)
            .toSet()
            .length,
        3,
      );
      final r = _match('milk');
      expect(r.link.asda.every((p) => p.name.contains('Semi')), isTrue);
    });
  });

  group('link shape', () {
    test('auto links are unconfirmed and never flag unavailable', () {
      for (final item in ['milk', 'chicken breast', 'kitchen roll']) {
        final r = _match(item);
        expect(r.link.userConfirmed, isFalse, reason: item);
        expect(r.link.asdaUnavailable, isFalse, reason: item);
        expect(r.link.costcoUnavailable, isFalse, reason: item);
        expect(r.link.itemKey, PriceLink.keyFor(item));
      }
    });

    test('mode is exact when each store has at most one pick', () {
      final r = _match('basmati rice', asdaKey: 'basmati rice');
      expect(r.link.asda.length, greaterThan(1));
      expect(r.link.mode, LinkMode.anyOf);
      final one = _match(
        'heinz baked beans',
        asdaKey: 'baked beans',
        costcoKey: 'baked beans',
      );
      expect(one.link.asda.length, 1);
      expect(one.link.costco.length, 1);
      expect(one.link.mode, LinkMode.exact);
    });
  });

  test('end to end: autoMatch then compareBasket over the 12 terms', () {
    final lines = <CompareLine>[];
    for (final term in _asdaFixture.keys) {
      final r = autoMatch(
        term,
        asda: _asdaTerm(term),
        costco: _costcoTerm(_costcoKeyFor[term]!),
        now: _fetched,
      );
      lines.add(CompareLine(itemName: term, link: r.link));
    }
    expect(lines.length, 12);

    final result = compareBasket(lines);
    expect(result.unlinkedCount, 0);
    expect(result.recommendation, Recommendation.split);
    expect(result.forcedByCostcoOnly, isFalse);
    expect(result.splitNetSaving, greaterThan(0));

    LineComparison line(String name) =>
        result.lines.firstWhere((l) => l.line.itemName == name);
    final oil = line('olive oil');
    final roll = line('toilet roll');
    expect(oil.costcoSaving, isNotNull);
    expect(roll.costcoSaving, isNotNull);
    expect(oil.costcoSaving! + roll.costcoSaving!, greaterThan(5.99));
    expect(oil.cheaperStore, PriceStore.costco);
    expect(roll.cheaperStore, PriceStore.costco);
    expect(line('laundry liquid').basis, CompareBasis.wash);
    expect(line('tea bags').basis, CompareBasis.bag);
    expect(line('kitchen roll').status, LineStatus.asdaOnly);
    expect(line('milk').status, LineStatus.asdaOnly);
    expect(
      result.splitPlan.costcoLines.any((l) => l.line.itemName == 'olive oil'),
      isTrue,
    );
  });
}
