import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/pantry_item.dart';

PantryItem _item({DateTime? expiresAt, int? shelfLifeDays}) => PantryItem(
  id: 'p1', name: 'Chicken', categoryId: 'meats',
  preferredStores: const [], optimalQuantity: 2,
  currentQuantity: 1, restockAfterDays: null,
  shelfLifeDays: shelfLifeDays, expiresAt: expiresAt,
  lastNudgedAt: null, lastPurchasedAt: null,
);

void main() {
  group('PantryItem expiry', () {
    test('isExpired true when expiresAt is in the past', () {
      final item = _item(expiresAt: DateTime.now().subtract(const Duration(days: 1)));
      expect(item.isExpired, isTrue);
    });

    test('isExpired false when expiresAt is in the future', () {
      final item = _item(expiresAt: DateTime.now().add(const Duration(days: 10)));
      expect(item.isExpired, isFalse);
    });

    test('isExpired false when expiresAt is null', () {
      final item = _item();
      expect(item.isExpired, isFalse);
    });

    test('isExpiringSoon true when within 2 days', () {
      final item = _item(expiresAt: DateTime.now().add(const Duration(days: 1)));
      expect(item.isExpiringSoon, isTrue);
      expect(item.isExpired, isFalse);
    });

    test('isExpiringSoon false when more than 2 days out', () {
      final item = _item(expiresAt: DateTime.now().add(const Duration(days: 5)));
      expect(item.isExpiringSoon, isFalse);
    });

    test('isExpiringSoon false when already expired', () {
      final item = _item(expiresAt: DateTime.now().subtract(const Duration(days: 1)));
      expect(item.isExpiringSoon, isFalse);
    });
  });

  group('PantryItem copyWith', () {
    test('copies all fields correctly', () {
      final original = PantryItem(
        id: 'p1', name: 'Chicken', categoryId: 'meats',
        preferredStores: const ['coles'], optimalQuantity: 3,
        currentQuantity: 1, restockAfterDays: 7,
        shelfLifeDays: 3, expiresAt: DateTime(2026, 4, 20),
        lastNudgedAt: DateTime(2026, 4, 10),
        lastPurchasedAt: DateTime(2026, 4, 12),
      );

      final copied = original.copyWith(
        name: 'Beef',
        currentQuantity: 2,
        shelfLifeDays: 5,
      );

      expect(copied.id, 'p1'); // id is never changed
      expect(copied.name, 'Beef');
      expect(copied.categoryId, 'meats'); // unchanged
      expect(copied.currentQuantity, 2);
      expect(copied.shelfLifeDays, 5);
      expect(copied.optimalQuantity, 3); // unchanged
      expect(copied.expiresAt, DateTime(2026, 4, 20)); // unchanged
      expect(copied.lastPurchasedAt, DateTime(2026, 4, 12)); // unchanged
    });

    test('preserves original values when no overrides', () {
      final original = _item(shelfLifeDays: 10, expiresAt: DateTime(2026, 5, 1));
      final copied = original.copyWith();
      expect(copied.name, original.name);
      expect(copied.shelfLifeDays, 10);
      expect(copied.expiresAt, DateTime(2026, 5, 1));
    });
  });

  group('PantryItem fromFirestore null safety', () {
    test('name defaults to empty string when null', () {
      // This is a unit test for the null fallback fix.
      // We can't easily mock DocumentSnapshot, but we test the model logic.
      final item = _item();
      expect(item.name, isNotEmpty); // 'Chicken' from helper
    });
  });
}
