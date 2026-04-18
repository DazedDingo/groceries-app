import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/items_service.dart';

PantryItem _pantryItem({
  int? shelfLifeDays,
  String? unit,
  double? unitAmount,
}) =>
    PantryItem(
      id: 'p1',
      name: 'Milk',
      categoryId: 'dairy',
      preferredStores: const [],
      optimalQuantity: 2,
      currentQuantity: 0,
      restockAfterDays: null,
      shelfLifeDays: shelfLifeDays,
      unitAmount: unitAmount,
      unit: unit,
      lastNudgedAt: null,
      lastPurchasedAt: null,
    );

ShoppingItem _shopping({String? unit}) => ShoppingItem(
      id: 's1',
      name: 'Milk',
      categoryId: 'dairy',
      preferredStores: const [],
      quantity: 1,
      unit: unit,
      pantryItemId: 'p1',
      addedBy: const AddedBy(
        uid: 'u1', displayName: 'Alice', source: ItemSource.app),
      addedAt: DateTime(2026, 4, 18),
    );

void main() {
  group('ItemsService.checkOff shelf-life fallback', () {
    late FakeFirebaseFirestore db;
    late ItemsService service;

    setUp(() async {
      db = FakeFirebaseFirestore();
      service = ItemsService(db: db);
      await db.doc('households/hh1/pantry/p1').set({
        'name': 'Milk',
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'optimalQuantity': 2,
        'currentQuantity': 0,
        'restockAfterDays': null,
        'shelfLifeDays': null,
        'unit': null,
      });
      await db.doc('households/hh1/items/s1').set({
        'name': 'Milk',
        'quantity': 1,
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'pantryItemId': 'p1',
        'addedBy': const AddedBy(
                uid: 'u1', displayName: 'Alice', source: ItemSource.app)
            .toMap(),
        'addedAt': Timestamp.fromDate(DateTime(2026, 4, 18)),
      });
    });

    test('uses fallback days when pantry shelfLifeDays is null and persists it', () async {
      await service.checkOff(
        householdId: 'hh1',
        item: _shopping(),
        pantryItem: _pantryItem(shelfLifeDays: null),
        shelfLifeDaysFallback: 7,
      );

      final snap = await db.doc('households/hh1/pantry/p1').get();
      expect(snap['shelfLifeDays'], 7,
          reason: 'fallback should persist so next check-off skips the guess');
      final exp = (snap['expiresAt'] as Timestamp).toDate();
      final delta = exp.difference(DateTime.now()).inDays;
      expect(delta >= 6 && delta <= 7, true,
          reason: 'expiresAt should be ~7 days out');
    });

    test('prefers existing shelfLifeDays over fallback', () async {
      await db.doc('households/hh1/pantry/p1').update({'shelfLifeDays': 3});
      await service.checkOff(
        householdId: 'hh1',
        item: _shopping(),
        pantryItem: _pantryItem(shelfLifeDays: 3),
        shelfLifeDaysFallback: 30,
      );

      final snap = await db.doc('households/hh1/pantry/p1').get();
      expect(snap['shelfLifeDays'], 3);
      final exp = (snap['expiresAt'] as Timestamp).toDate();
      final delta = exp.difference(DateTime.now()).inDays;
      expect(delta >= 2 && delta <= 3, true);
    });

    test('restarts expiry countdown on every checkOff (even with stale expiresAt)', () async {
      // Pre-existing expiry in the past.
      await db.doc('households/hh1/pantry/p1').update({
        'shelfLifeDays': 5,
        'expiresAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      await service.checkOff(
        householdId: 'hh1',
        item: _shopping(),
        pantryItem: _pantryItem(shelfLifeDays: 5),
      );

      final snap = await db.doc('households/hh1/pantry/p1').get();
      final exp = (snap['expiresAt'] as Timestamp).toDate();
      expect(exp.isAfter(DateTime.now()), true,
          reason: 'stored expiresAt should be reset to today + shelfLife');
    });

    test('no shelfLifeDays and no fallback leaves expiresAt untouched', () async {
      await db.doc('households/hh1/pantry/p1').update({
        'expiresAt': null,
      });
      await service.checkOff(
        householdId: 'hh1',
        item: _shopping(),
        pantryItem: _pantryItem(shelfLifeDays: null),
      );
      final snap = await db.doc('households/hh1/pantry/p1').get();
      expect(snap.data()!.containsKey('expiresAt') ? snap['expiresAt'] : null, isNull);
      expect(snap.data()!.containsKey('shelfLifeDays') ? snap['shelfLifeDays'] : null, isNull);
    });
  });
}
