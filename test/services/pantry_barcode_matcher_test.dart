import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/pantry_barcode_matcher.dart';

PantryItem _p(String id, String name) => PantryItem(
      id: id,
      name: name,
      categoryId: 'cat',
      preferredStores: const [],
      optimalQuantity: 1,
      currentQuantity: 0,
      restockAfterDays: null,
      lastNudgedAt: null,
      lastPurchasedAt: null,
    );

void main() {
  group('findPantryMatch', () {
    test('empty scanned name returns no match', () {
      final r = findPantryMatch('', [_p('a', 'Milk')]);
      expect(r.exact, isNull);
      expect(r.fuzzy, isEmpty);
      expect(r.hasMatch, isFalse);
    });

    test('exact name match (case-insensitive) populates exact', () {
      final r = findPantryMatch('milk', [_p('a', 'Milk'), _p('b', 'Bread')]);
      expect(r.exact?.id, 'a');
      expect(r.fuzzy, isEmpty);
    });

    test('substring matches go to fuzzy, not exact', () {
      // "almond milk" scanned, pantry has "milk" — fuzzy hit (substring rule).
      final r = findPantryMatch('almond milk', [_p('a', 'milk')]);
      expect(r.exact, isNull);
      expect(r.fuzzy.map((p) => p.id), contains('a'));
    });

    test('typo within edit-distance threshold lands in fuzzy', () {
      // "yoghurt" vs "yogurt" — single edit, both ≥4 chars, threshold ≥1.
      final r = findPantryMatch('yoghurt', [_p('a', 'yogurt')]);
      expect(r.fuzzy.map((p) => p.id), contains('a'));
      expect(r.exact, isNull);
    });

    test('unrelated short words do NOT fuzzy-match', () {
      // Levenshtein guard requires both ≥4 chars; 'egg' vs 'fig' must miss.
      final r = findPantryMatch('egg', [_p('a', 'fig')]);
      expect(r.exact, isNull);
      expect(r.fuzzy, isEmpty);
    });

    test('exact and fuzzy can coexist on different pantry items', () {
      final r = findPantryMatch('milk', [
        _p('a', 'Milk'),
        _p('b', 'almond milk'), // substring fuzzy
        _p('c', 'bread'),
      ]);
      expect(r.exact?.id, 'a');
      expect(r.fuzzy.map((p) => p.id), contains('b'));
      expect(r.fuzzy.map((p) => p.id), isNot(contains('c')));
    });

    test('skips pantry rows with empty names', () {
      final r = findPantryMatch('milk', [_p('a', ''), _p('b', 'Milk')]);
      expect(r.exact?.id, 'b');
    });
  });
}
