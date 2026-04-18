import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/history_entry.dart';
import 'package:groceries_app/services/shelf_life_guesser.dart';
import 'package:groceries_app/services/shelf_life_resolver.dart';

HistoryEntry _bought(String name, DateTime at) => HistoryEntry(
      id: 'h${at.microsecondsSinceEpoch}',
      itemName: name,
      categoryId: 'dairy',
      action: HistoryAction.bought,
      quantity: 1,
      byName: 'Alice',
      at: at,
    );

void main() {
  group('resolveShelfLifeDays ladder', () {
    test('returns null when no signal at any layer', () {
      expect(
        resolveShelfLifeDays(
          itemName: 'totally-novel-item',
          categoryName: 'nonexistent-category',
          history: const [],
        ),
        isNull,
      );
    });

    test('falls back to category when no keyword or history', () {
      expect(
        resolveShelfLifeDays(
          itemName: 'totally-novel-item',
          categoryName: 'Dairy',
          history: const [],
        ),
        10, // dairy category default
      );
    });

    test('keyword beats category', () {
      // "milk" has its own keyword (7) that should win over "dairy" (10).
      expect(
        resolveShelfLifeDays(
          itemName: 'Skim Milk',
          categoryName: 'Dairy',
          history: const [],
        ),
        7,
      );
    });

    test('learned-from-history beats keyword and category', () {
      // Four yogurt purchases, 4 days apart → median gap = 4 days.
      final history = [
        _bought('Yogurt', DateTime(2026, 4, 1)),
        _bought('Yogurt', DateTime(2026, 4, 5)),
        _bought('Yogurt', DateTime(2026, 4, 9)),
        _bought('Yogurt', DateTime(2026, 4, 13)),
      ];
      final resolved = resolveShelfLifeDays(
        itemName: 'Yogurt',
        categoryName: 'Dairy',
        history: history,
      );
      expect(resolved, 4,
          reason: 'household median should override keyword "yogurt" (21)');
    });

    test('history with <3 purchases falls through to keyword', () {
      final history = [
        _bought('Cheddar', DateTime(2026, 4, 1)),
        _bought('Cheddar', DateTime(2026, 4, 10)),
      ];
      expect(
        resolveShelfLifeDays(
          itemName: 'Cheddar',
          categoryName: 'Dairy',
          history: history,
        ),
        60, // per-item keyword value
      );
    });

    test('null category still lets keyword match run', () {
      expect(
        resolveShelfLifeDays(
          itemName: 'Spaghetti',
          categoryName: null,
          history: const [],
        ),
        365,
      );
    });
  });

  group('expanded keyword table (regression spot-checks)', () {
    test('grains resolve to long shelf life', () {
      expect(guessShelfLifeDays('', itemName: 'Jasmine Rice'), 365);
      expect(guessShelfLifeDays('', itemName: 'quinoa'), 365);
      expect(guessShelfLifeDays('', itemName: 'Spaghetti 500g'), 365);
    });

    test('nuts and seeds get their own window', () {
      expect(guessShelfLifeDays('', itemName: 'Roasted almonds'), 90);
      expect(guessShelfLifeDays('', itemName: 'chia seed pudding mix'), 365);
    });

    test('canned goods resolve without a category', () {
      expect(guessShelfLifeDays('', itemName: 'Canned tomatoes'), 365);
      expect(guessShelfLifeDays('', itemName: 'canned tuna'), 365);
    });

    test('condiments resolve to their specific life', () {
      expect(guessShelfLifeDays('', itemName: 'Sriracha'), 365);
      expect(guessShelfLifeDays('', itemName: 'Peanut butter'), 180);
      expect(guessShelfLifeDays('', itemName: 'Mayonnaise'), 60);
      expect(guessShelfLifeDays('', itemName: 'Olive oil 500ml'), 180);
    });

    test('longest-key-wins still holds after the expansion', () {
      // "green onion" (7) should win over "onion" (30).
      expect(guessShelfLifeDays('', itemName: 'Green onions'), 7);
      // "hot sauce" (365) should win over "sauce" (no such shorter key, so
      // would fall to category). Spot-check the pair "tomato sauce" (180)
      // doesn't get swallowed by "tomato" (7).
      expect(guessShelfLifeDays('', itemName: 'Tomato sauce'), 180);
    });
  });
}
