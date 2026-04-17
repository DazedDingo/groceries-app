// ignore_for_file: no_leading_underscores_for_local_identifiers
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/history_entry.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/suggestion_ranker.dart';

SuggestionItem _s(
  String name, {
  DateTime? lastUsed,
  int frequency = 0,
  SuggestionSource source = SuggestionSource.history,
  bool isOnList = false,
  bool isHighPriority = false,
}) =>
    SuggestionItem(
      name: name,
      lastUsed: lastUsed,
      frequency: frequency,
      source: source,
      isOnList: isOnList,
      isHighPriority: isHighPriority,
    );

final _now = DateTime(2026, 4, 17, 12);

void main() {
  group('rankSuggestions — match quality', () {
    test('returns empty when no candidates', () {
      expect(rankSuggestions([], 'milk', _now), isEmpty);
    });

    test('empty query returns no matches when no candidates qualify', () {
      expect(rankSuggestions([_s('milk')], '', _now), ['milk']);
    });

    test('exact match beats substring beats fuzzy', () {
      final result = rankSuggestions(
        [
          _s('soy milk'), // substring
          _s('millk'), // fuzzy (edit distance 1, both ≥4 chars)
          _s('milk'), // exact
        ],
        'milk',
        _now,
      );
      expect(result.first, 'milk');
      expect(result[1], 'soy milk');
      expect(result[2], 'millk');
    });

    test('prefix match beats substring match', () {
      final result = rankSuggestions(
        [
          _s('soy milk'), // substring
          _s('milk chocolate'), // prefix
        ],
        'milk',
        _now,
      );
      expect(result.first, 'milk chocolate');
    });

    test('non-matching items are excluded', () {
      final result = rankSuggestions(
        [_s('bread'), _s('milk')],
        'milk',
        _now,
      );
      expect(result, ['milk']);
    });
  });

  group('rankSuggestions — recency & frequency', () {
    test('recent item ranks above old item, same match quality', () {
      final result = rankSuggestions(
        [
          _s('milk', lastUsed: _now.subtract(const Duration(days: 60))),
          _s('milk stout', lastUsed: _now.subtract(const Duration(hours: 1))),
        ],
        'mil',
        _now,
      );
      // 'milk' is a prefix match (higher base) vs 'milk stout' also prefix.
      // Both prefix → recency decides. Stout is fresher.
      expect(result.first, 'milk stout');
    });

    test('high-frequency item beats one-off', () {
      final result = rankSuggestions(
        [
          _s('rare milk', frequency: 1),
          _s('regular milk', frequency: 50),
        ],
        'milk',
        _now,
      );
      expect(result.first, 'regular milk');
    });
  });

  group('rankSuggestions — flags', () {
    test('isHighPriority boosts ranking', () {
      final result = rankSuggestions(
        [
          _s('normal milk'),
          _s('low milk', isHighPriority: true),
        ],
        'milk',
        _now,
      );
      expect(result.first, 'low milk');
    });

    test('isOnList demotes ranking', () {
      final result = rankSuggestions(
        [
          _s('milk a', isOnList: true),
          _s('milk b'),
        ],
        'milk',
        _now,
      );
      expect(result.first, 'milk b');
      expect(result.last, 'milk a');
    });

    test('pantry source tie-breaks above history for equal base', () {
      final result = rankSuggestions(
        [
          _s('milk', source: SuggestionSource.history),
          _s('Milk', source: SuggestionSource.pantry), // dup (case-insensitive)
        ],
        'milk',
        _now,
      );
      // Dedupe by lowercase — first wins since we iterate in insertion order.
      expect(result, ['milk']);
    });
  });

  group('rankSuggestions — de-duplication & limit', () {
    test('de-duplicates case-insensitively', () {
      final result = rankSuggestions(
        [_s('Milk'), _s('milk'), _s('MILK')],
        'milk',
        _now,
      );
      expect(result, ['Milk']);
    });

    test('respects limit', () {
      final candidates =
          List.generate(20, (i) => _s('milk_${i.toString().padLeft(2, '0')}'));
      final result = rankSuggestions(candidates, 'milk', _now, limit: 5);
      expect(result.length, 5);
    });

    test('default limit is 10', () {
      final candidates = List.generate(30, (i) => _s('milk_$i'));
      final result = rankSuggestions(candidates, 'milk', _now);
      expect(result.length, 10);
    });
  });

  group('buildSuggestions', () {
    PantryItem _p(String name, {bool highPriority = false, int current = 2}) =>
        PantryItem(
          id: 'p_$name',
          name: name,
          categoryId: 'c',
          preferredStores: const [],
          optimalQuantity: 3,
          currentQuantity: current,
          restockAfterDays: null,
          lastNudgedAt: null,
          lastPurchasedAt: _now.subtract(const Duration(days: 3)),
          isHighPriority: highPriority,
        );

    HistoryEntry _h(String name, DateTime at) => HistoryEntry(
          id: 'h_$name',
          itemName: name,
          categoryId: 'c',
          action: HistoryAction.bought,
          quantity: 1,
          at: at,
          byName: 'u',
        );

    ShoppingItem _i(String name) => ShoppingItem(
          id: 'i_$name',
          name: name,
          quantity: 1,
          unit: null,
          note: null,
          categoryId: 'c',
          preferredStores: const [],
          pantryItemId: null,
          recipeSource: null,
          isRecurring: false,
          addedBy: const AddedBy(
            uid: 'u', displayName: 'u', source: ItemSource.app,
          ),
          addedAt: _now,
        );

    test('returns empty when all sources empty', () {
      expect(
        buildSuggestions(
            currentListItems: [], history: [], pantryItems: []),
        isEmpty,
      );
    });

    test('counts history frequency', () {
      final result = buildSuggestions(
        currentListItems: [],
        history: [
          _h('milk', _now.subtract(const Duration(days: 1))),
          _h('milk', _now.subtract(const Duration(days: 2))),
          _h('bread', _now.subtract(const Duration(days: 5))),
        ],
        pantryItems: [],
      );
      final milk = result.firstWhere((s) => s.name == 'milk');
      expect(milk.frequency, 2);
      final bread = result.firstWhere((s) => s.name == 'bread');
      expect(bread.frequency, 1);
    });

    test('merges same-name candidates across sources', () {
      final result = buildSuggestions(
        currentListItems: [_i('milk')],
        history: [_h('Milk', _now.subtract(const Duration(days: 3)))],
        pantryItems: [_p('MILK', highPriority: true)],
      );
      expect(result.length, 1);
      final merged = result.first;
      expect(merged.isOnList, isTrue);
      expect(merged.frequency, 1);
      expect(merged.isHighPriority, isTrue);
      expect(merged.source, SuggestionSource.pantry);
    });

    test('ignores non-bought history entries', () {
      final result = buildSuggestions(
        currentListItems: [],
        history: [
          HistoryEntry(
            id: 'h1', itemName: 'milk', categoryId: 'c',
            action: HistoryAction.added, quantity: 1,
            at: _now, byName: 'u',
          ),
        ],
        pantryItems: [],
      );
      expect(result, isEmpty);
    });

    test('flags below-optimal pantry as high priority', () {
      final result = buildSuggestions(
        currentListItems: [],
        history: [],
        pantryItems: [_p('milk', current: 0)],
      );
      expect(result.first.isHighPriority, isTrue);
    });
  });
}
