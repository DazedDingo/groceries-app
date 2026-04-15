import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/providers/auth_provider.dart';
import 'package:groceries_app/providers/gemini_key_provider.dart';
import 'package:groceries_app/providers/household_key_notifier.dart';
import 'package:groceries_app/providers/household_provider.dart';
import 'package:groceries_app/providers/recipe_search_provider.dart';
import 'package:groceries_app/services/auth_service.dart';
import 'package:groceries_app/services/household_config_service.dart';
import 'package:groceries_app/services/household_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container(FakeFirebaseFirestore db,
    {String? householdId = 'hh1'}) {
  final mockUser = MockUser(uid: 'u1', email: 'a@b.com', displayName: 'Alice');
  final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
  if (householdId != null) {
    db.doc('users/${mockUser.uid}').set({'householdId': householdId});
  }
  return ProviderContainer(
    overrides: [
      householdIdProvider.overrideWith((ref) async => householdId),
      householdServiceProvider.overrideWithValue(HouseholdService(db: db)),
      authStateProvider.overrideWith((ref) => Stream.value(mockUser)),
      authServiceProvider.overrideWithValue(AuthService(auth: auth)),
      householdConfigServiceProvider
          .overrideWithValue(HouseholdConfigService(db: db)),
    ],
  );
}

Future<void> _tick([int ms = 50]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HouseholdKeyNotifier', () {
    test('stays empty when user has no household', () async {
      final db = FakeFirebaseFirestore();
      // Seed a value in Firestore for some household — notifier shouldn't
      // see it because the user has no householdId.
      await db
          .doc('households/otherhh/config/apiKeys')
          .set({'geminiKey': 'SOMEONES-KEY'});
      final container = _container(db, householdId: null);
      addTearDown(container.dispose);

      container.read(geminiKeyProvider);
      await _tick();
      expect(container.read(geminiKeyProvider), '');
    });

    test('set() before household resolves still eventually persists',
        () async {
      final db = FakeFirebaseFirestore();
      final container = _container(db);
      addTearDown(container.dispose);
      // Immediately set without awaiting init.
      await container.read(geminiKeyProvider.notifier).set('EARLY-KEY');
      await _tick();
      expect(container.read(geminiKeyProvider), 'EARLY-KEY');
      final fs = await db.doc('households/hh1/config/apiKeys').get();
      expect(fs.data()?['geminiKey'], 'EARLY-KEY');
    });

    test('remote change propagates to local state', () async {
      final db = FakeFirebaseFirestore();
      final container = _container(db);
      addTearDown(container.dispose);
      container.read(geminiKeyProvider);
      await _tick();
      expect(container.read(geminiKeyProvider), '');

      // Partner updates the key from another session.
      await db
          .doc('households/hh1/config/apiKeys')
          .set({'geminiKey': 'PARTNER-SET'});
      await _tick();
      expect(container.read(geminiKeyProvider), 'PARTNER-SET');
    });

    test('two different keys (gemini + spoonacular) coexist', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('households/hh1/config/apiKeys').set({
        'geminiKey': 'GEM-1',
        'spoonacularKey': 'SPOON-1',
      });
      final container = _container(db);
      addTearDown(container.dispose);
      container.read(geminiKeyProvider);
      container.read(spoonacularKeyProvider);
      await _tick();
      expect(container.read(geminiKeyProvider), 'GEM-1');
      expect(container.read(spoonacularKeyProvider), 'SPOON-1');
    });

    test('setting one key does not clobber the other', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('households/hh1/config/apiKeys').set({
        'geminiKey': 'GEM-ORIG',
        'spoonacularKey': 'SPOON-ORIG',
      });
      final container = _container(db);
      addTearDown(container.dispose);
      container.read(geminiKeyProvider);
      container.read(spoonacularKeyProvider);
      await _tick();

      await container
          .read(spoonacularKeyProvider.notifier)
          .set('SPOON-UPDATED');
      await _tick();

      final doc = await db.doc('households/hh1/config/apiKeys').get();
      expect(doc.data()?['geminiKey'], 'GEM-ORIG');
      expect(doc.data()?['spoonacularKey'], 'SPOON-UPDATED');
      expect(container.read(geminiKeyProvider), 'GEM-ORIG');
      expect(container.read(spoonacularKeyProvider), 'SPOON-UPDATED');
    });

    test('migration clears legacy SharedPreferences entry', () async {
      SharedPreferences.setMockInitialValues({
        'geminiApiKey': 'LEGACY-GEM',
        'spoonacularApiKey': 'LEGACY-SPOON',
      });
      final db = FakeFirebaseFirestore();
      final container = _container(db);
      addTearDown(container.dispose);
      container.read(geminiKeyProvider);
      container.read(spoonacularKeyProvider);
      await _tick(150);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('geminiApiKey'), false);
      expect(prefs.containsKey('spoonacularApiKey'), false);
      expect(container.read(geminiKeyProvider), 'LEGACY-GEM');
      expect(container.read(spoonacularKeyProvider), 'LEGACY-SPOON');
    });

    test('migration does NOT overwrite an existing Firestore key', () async {
      SharedPreferences.setMockInitialValues(
          {'geminiApiKey': 'LEGACY-LOCAL'});
      final db = FakeFirebaseFirestore();
      await db
          .doc('households/hh1/config/apiKeys')
          .set({'geminiKey': 'ALREADY-REMOTE'});
      final container = _container(db);
      addTearDown(container.dispose);
      container.read(geminiKeyProvider);
      await _tick(150);

      final doc = await db.doc('households/hh1/config/apiKeys').get();
      expect(doc.data()?['geminiKey'], 'ALREADY-REMOTE',
          reason: 'legacy key must not clobber an existing Firestore value');
      expect(container.read(geminiKeyProvider), 'ALREADY-REMOTE');
    });

    test('set() trims whitespace and persists trimmed form', () async {
      final db = FakeFirebaseFirestore();
      final container = _container(db);
      addTearDown(container.dispose);
      container.read(geminiKeyProvider);
      await _tick();

      await container
          .read(geminiKeyProvider.notifier)
          .set('   padded-key   ');
      await _tick();

      expect(container.read(geminiKeyProvider), 'padded-key');
      final doc = await db.doc('households/hh1/config/apiKeys').get();
      expect(doc.data()?['geminiKey'], 'padded-key');
    });

    test('ProviderContainer dispose cancels the Firestore subscription',
        () async {
      final db = FakeFirebaseFirestore();
      final container = _container(db);
      container.read(geminiKeyProvider);
      await _tick();
      // Dispose the container — should not throw and should cancel the
      // underlying stream subscription cleanly.
      container.dispose();
      // Writing to the doc AFTER dispose should be harmless (no listener).
      await db
          .doc('households/hh1/config/apiKeys')
          .set({'geminiKey': 'POST-DISPOSE'});
      await _tick();
      // If the subscription leaked, we'd see an error from setState on a
      // disposed notifier. Surviving this block is the pass condition.
      expect(true, isTrue);
    });
  });
}
