import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/category.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/pantry_grouper.dart';

PantryItem _item({
  required String id,
  required String name,
  String categoryId = 'cat-a',
  String? location,
  int current = 2,
  int optimal = 2,
  DateTime? expiresAt,
}) =>
    PantryItem(
      id: id,
      name: name,
      categoryId: categoryId,
      preferredStores: const [],
      optimalQuantity: optimal,
      currentQuantity: current,
      restockAfterDays: null,
      lastNudgedAt: null,
      lastPurchasedAt: null,
      runningLowAt: null,
      location: location,
      expiresAt: expiresAt,
    );

GroceryCategory _cat(String id, String name) =>
    GroceryCategory(id: id, name: name, color: const Color(0xFF000000), addedBy: 't');

void main() {
  group('groupByCategory', () {
    test('sections follow category display order', () {
      final cats = [_cat('cat-a', 'Apples'), _cat('cat-b', 'Bread')];
      final items = [
        _item(id: '1', name: 'bread', categoryId: 'cat-b'),
        _item(id: '2', name: 'apple', categoryId: 'cat-a'),
      ];
      final groups = groupByCategory(items, cats);
      expect(groups.map((g) => g.label), ['Apples', 'Bread']);
    });

    test('items without a matching category land in Uncategorised', () {
      final cats = [_cat('cat-a', 'Apples')];
      final items = [
        _item(id: '1', name: 'apple', categoryId: 'cat-a'),
        _item(id: '2', name: 'mystery', categoryId: 'cat-x'),
      ];
      final groups = groupByCategory(items, cats);
      expect(groups.last.label, 'Uncategorised');
      expect(groups.last.items.single.name, 'mystery');
    });

    test('expired items float to the top of a category', () {
      final cats = [_cat('cat-a', 'Apples')];
      final items = [
        _item(id: '1', name: 'fresh', categoryId: 'cat-a'),
        _item(
          id: '2',
          name: 'rotten',
          categoryId: 'cat-a',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];
      final groups = groupByCategory(items, cats);
      expect(groups.single.items.map((i) => i.name), ['rotten', 'fresh']);
    });

    test('empty sections are dropped', () {
      final cats = [_cat('cat-a', 'Apples'), _cat('cat-b', 'Bread')];
      final items = [_item(id: '1', name: 'apple', categoryId: 'cat-a')];
      final groups = groupByCategory(items, cats);
      expect(groups.map((g) => g.label), ['Apples']);
    });
  });

  group('groupByLocation', () {
    test('built-in locations come first, then custom, then Not set', () {
      final items = [
        _item(id: '1', name: 'a', location: 'garage'),
        _item(id: '2', name: 'b', location: null),
        _item(id: '3', name: 'c', location: PantryLocation.fridge.id),
      ];
      final groups = groupByLocation(items, ['garage']);
      expect(groups.map((g) => g.label), ['Fridge', 'garage', 'Not set']);
    });

    test('expired items float to the top of a location', () {
      final items = [
        _item(id: '1', name: 'fresh', location: PantryLocation.pantry.id),
        _item(
          id: '2',
          name: 'rotten',
          location: PantryLocation.pantry.id,
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];
      final groups = groupByLocation(items, const []);
      expect(groups.single.items.map((i) => i.name), ['rotten', 'fresh']);
    });

    test('below-optimal items rank above stocked', () {
      final items = [
        _item(
          id: '1',
          name: 'stocked',
          location: PantryLocation.pantry.id,
          current: 2,
          optimal: 2,
        ),
        _item(
          id: '2',
          name: 'low',
          location: PantryLocation.pantry.id,
          current: 0,
          optimal: 2,
        ),
      ];
      final groups = groupByLocation(items, const []);
      expect(groups.single.items.map((i) => i.name), ['low', 'stocked']);
    });
  });

  group('statusRank', () {
    test('orders expired < expiring < below-optimal < stale < stocked', () {
      final now = DateTime.now();
      final expired = _item(
        id: '1',
        name: 'expired',
        expiresAt: now.subtract(const Duration(days: 1)),
      );
      final expiring = _item(
        id: '2',
        name: 'expiring',
        expiresAt: now.add(const Duration(days: 1)),
      );
      final belowOptimal = _item(id: '3', name: 'low', current: 0, optimal: 2);
      final stocked = _item(id: '4', name: 'ok', current: 2, optimal: 2);

      expect(statusRank(expired) < statusRank(expiring), isTrue);
      expect(statusRank(expiring) < statusRank(belowOptimal), isTrue);
      expect(statusRank(belowOptimal) < statusRank(stocked), isTrue);
    });
  });
}
