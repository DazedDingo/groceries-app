import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:groceries_app/services/pantry_service.dart';

void main() {
  group('PantryService', () {
    late PantryService service;
    late FakeFirebaseFirestore fakeDb;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = PantryService(db: fakeDb);
    });

    test('decrementQuantity reduces currentQuantity by 1', () async {
      await fakeDb.doc('households/hh1/pantry/p1').set({
        'name': 'Eggs', 'categoryId': 'dairy', 'preferredStores': [],
        'optimalQuantity': 6, 'currentQuantity': 3,
        'restockAfterDays': null, 'lastNudgedAt': null, 'lastPurchasedAt': null,
      });
      await service.decrementQuantity(householdId: 'hh1', itemId: 'p1', current: 3);
      final doc = await fakeDb.doc('households/hh1/pantry/p1').get();
      expect(doc['currentQuantity'], 2);
    });
  });
}
