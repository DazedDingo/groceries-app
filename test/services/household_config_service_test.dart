import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/household_config_service.dart';

void main() {
  group('HouseholdConfigService', () {
    late FakeFirebaseFirestore db;
    late HouseholdConfigService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = HouseholdConfigService(db: db);
    });

    test('apiKeysStream emits empty strings when doc does not exist', () async {
      final keys = await service.apiKeysStream('hh1').first;
      expect(keys['spoonacularKey'], '');
      expect(keys['geminiKey'], '');
    });

    test('apiKeysStream emits stored values', () async {
      await db.doc('households/hh1/config/apiKeys').set({
        'spoonacularKey': 'SP-123',
        'geminiKey': 'AIza-456',
      });
      final keys = await service.apiKeysStream('hh1').first;
      expect(keys['spoonacularKey'], 'SP-123');
      expect(keys['geminiKey'], 'AIza-456');
    });

    test('setKey writes a single field via merge (does not clobber others)',
        () async {
      await db
          .doc('households/hh1/config/apiKeys')
          .set({'spoonacularKey': 'SP-EXISTING'});
      await service.setKey('hh1', 'geminiKey', 'AIza-NEW');
      final doc = await db.doc('households/hh1/config/apiKeys').get();
      expect(doc.data()?['spoonacularKey'], 'SP-EXISTING');
      expect(doc.data()?['geminiKey'], 'AIza-NEW');
    });

    test('setKey can clear a field by writing empty string', () async {
      await db
          .doc('households/hh1/config/apiKeys')
          .set({'geminiKey': 'AIza-OLD'});
      await service.setKey('hh1', 'geminiKey', '');
      final doc = await db.doc('households/hh1/config/apiKeys').get();
      expect(doc.data()?['geminiKey'], '');
    });

    test('different households are isolated', () async {
      await service.setKey('hh1', 'geminiKey', 'KEY-A');
      await service.setKey('hh2', 'geminiKey', 'KEY-B');
      final keysA = await service.apiKeysStream('hh1').first;
      final keysB = await service.apiKeysStream('hh2').first;
      expect(keysA['geminiKey'], 'KEY-A');
      expect(keysB['geminiKey'], 'KEY-B');
    });
  });
}
