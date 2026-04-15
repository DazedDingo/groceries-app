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

    test('apiKeysStream emits on every change (reactive)', () async {
      final updates = <Map<String, String>>[];
      final sub = service.apiKeysStream('hh1').listen(updates.add);
      // Initial emission (doc doesn't exist) → empty strings.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(updates.length, 1);
      expect(updates.first['geminiKey'], '');

      await service.setKey('hh1', 'geminiKey', 'V1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await service.setKey('hh1', 'geminiKey', 'V2');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final gem = updates.map((m) => m['geminiKey']).toList();
      expect(gem, containsAll(['', 'V1', 'V2']));
      await sub.cancel();
    });

    test('setKey on a nonexistent doc creates it', () async {
      final docPre = await db.doc('households/brandnew/config/apiKeys').get();
      expect(docPre.exists, false);
      await service.setKey('brandnew', 'geminiKey', 'hello');
      final docPost = await db.doc('households/brandnew/config/apiKeys').get();
      expect(docPost.exists, true);
      expect(docPost.data()?['geminiKey'], 'hello');
    });

    test('unknown key names round-trip without touching known fields',
        () async {
      // Defensive: the service writes arbitrary field names; new kinds of
      // keys can be added in future without schema changes.
      await service.setKey('hh1', 'geminiKey', 'GEM');
      await service.setKey('hh1', 'futureExternalKey', 'FUTURE');
      final doc = await db.doc('households/hh1/config/apiKeys').get();
      expect(doc.data()?['geminiKey'], 'GEM');
      expect(doc.data()?['futureExternalKey'], 'FUTURE');
    });
  });
}
