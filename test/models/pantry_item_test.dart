import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:groceries_app/models/pantry_item.dart';

PantryItem _item({
  int optimal = 6,
  int current = 2,
  bool isHighPriority = false,
  DateTime? runningLowAt,
}) => PantryItem(
  id: 'p1', name: 'Milk', categoryId: 'dairy',
  preferredStores: const [], optimalQuantity: optimal,
  currentQuantity: current, restockAfterDays: 7,
  lastNudgedAt: null, lastPurchasedAt: null,
  runningLowAt: runningLowAt,
  isHighPriority: isHighPriority,
);

void main() {
  group('PantryItem', () {
    test('isBelowOptimal returns true when current < optimal', () {
      expect(_item(current: 2, optimal: 6).isBelowOptimal, isTrue);
    });

    test('isBelowOptimal returns false when current == optimal', () {
      expect(_item(current: 6, optimal: 6).isBelowOptimal, isFalse);
    });

    test('isBelowOptimal returns false when current > optimal', () {
      expect(_item(current: 8, optimal: 6).isBelowOptimal, isFalse);
    });

    test('isHighPriority defaults to false', () {
      expect(_item().isHighPriority, isFalse);
    });

    test('isHighPriority true is preserved through copyWith', () {
      final item = _item(isHighPriority: true);
      final copy = item.copyWith();
      expect(copy.isHighPriority, isTrue);
    });

    test('copyWith overrides isHighPriority', () {
      final item = _item(isHighPriority: false);
      final updated = item.copyWith(isHighPriority: true);
      expect(updated.isHighPriority, isTrue);
    });

    test('toMap includes isHighPriority true', () {
      final map = _item(isHighPriority: true).toMap();
      expect(map['isHighPriority'], isTrue);
    });

    test('toMap includes isHighPriority false', () {
      final map = _item(isHighPriority: false).toMap();
      expect(map['isHighPriority'], isFalse);
    });

    test('runningLowAt defaults to null', () {
      expect(_item().runningLowAt, isNull);
    });

    test('runningLowAt round-trips through toMap / fromFirestore', () async {
      final now = DateTime(2026, 4, 18, 12);
      final db = FakeFirebaseFirestore();
      await db.collection('pantry').doc('p1').set({
        'name': 'Milk',
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'optimalQuantity': 6,
        'currentQuantity': 2,
        'restockAfterDays': 7,
        'lastNudgedAt': null,
        'lastPurchasedAt': null,
        'runningLowAt': Timestamp.fromDate(now),
        'location': null,
        'isHighPriority': false,
      });
      final doc = await db.collection('pantry').doc('p1').get();
      final item = PantryItem.fromFirestore(doc);
      expect(item.runningLowAt, now);
      expect(
        item.toMap()['runningLowAt'],
        isA<Timestamp>().having((t) => t.toDate(), 'date', now),
      );
    });

    test('runningLowAt=null round-trips as null', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('pantry').doc('p1').set(_item().toMap());
      final doc = await db.collection('pantry').doc('p1').get();
      expect(PantryItem.fromFirestore(doc).runningLowAt, isNull);
    });
  });
}
