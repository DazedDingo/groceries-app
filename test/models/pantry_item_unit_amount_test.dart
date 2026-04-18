import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/pantry_item.dart';

void main() {
  group('PantryItem unitAmount', () {
    test('defaults to null when absent', () {
      final item = PantryItem(
        id: 'p',
        name: 'Flour',
        categoryId: 'baking',
        preferredStores: const [],
        optimalQuantity: 2,
        currentQuantity: 1,
        restockAfterDays: null,
        lastNudgedAt: null,
        lastPurchasedAt: null,
      );
      expect(item.unitAmount, isNull);
    });

    test('round-trips through toMap / fromFirestore', () async {
      final db = FakeFirebaseFirestore();
      final item = PantryItem(
        id: 'p1',
        name: 'Flour',
        categoryId: 'baking',
        preferredStores: const [],
        optimalQuantity: 2,
        currentQuantity: 1,
        restockAfterDays: null,
        unitAmount: 500,
        unit: 'g',
        lastNudgedAt: null,
        lastPurchasedAt: null,
      );
      await db.doc('households/hh1/pantry/p1').set(item.toMap());
      final snap = await db.doc('households/hh1/pantry/p1').get();
      final roundTripped = PantryItem.fromFirestore(snap);
      expect(roundTripped.unitAmount, 500);
      expect(roundTripped.unit, 'g');
    });

    test('parses an int stored as num', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('households/hh1/pantry/p1').set({
        'name': 'Oil',
        'categoryId': 'cooking',
        'preferredStores': <String>[],
        'optimalQuantity': 1,
        'currentQuantity': 1,
        'unitAmount': 1, // stored as int — must not blow up fromFirestore
        'unit': 'L',
      });
      final snap = await db.doc('households/hh1/pantry/p1').get();
      final p = PantryItem.fromFirestore(snap);
      expect(p.unitAmount, 1.0);
      expect(p.unit, 'L');
    });
  });
}
