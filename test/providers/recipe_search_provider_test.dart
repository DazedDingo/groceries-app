import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/providers/auth_provider.dart';
import 'package:groceries_app/providers/household_key_notifier.dart';
import 'package:groceries_app/providers/household_provider.dart';
import 'package:groceries_app/providers/recipe_search_provider.dart';
import 'package:groceries_app/services/auth_service.dart';
import 'package:groceries_app/services/household_config_service.dart';
import 'package:groceries_app/services/household_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _makeContainer(FakeFirebaseFirestore db,
    {String householdId = 'hh1'}) {
  final mockUser = MockUser(uid: 'u1', email: 'a@b.com', displayName: 'Alice');
  final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
  db.doc('users/${mockUser.uid}').set({'householdId': householdId});

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts empty when nothing is stored', () async {
    final db = FakeFirebaseFirestore();
    final container = _makeContainer(db);
    addTearDown(container.dispose);

    expect(container.read(spoonacularKeyProvider), '');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(spoonacularKeyProvider), '');
  });

  test('hydrates from Firestore household config', () async {
    final db = FakeFirebaseFirestore();
    await db
        .doc('households/hh1/config/apiKeys')
        .set({'spoonacularKey': 'SAVED-KEY'});
    final container = _makeContainer(db);
    addTearDown(container.dispose);

    container.read(spoonacularKeyProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(spoonacularKeyProvider), 'SAVED-KEY');
  });

  test('migrates legacy SharedPreferences value into Firestore', () async {
    SharedPreferences.setMockInitialValues(
        {'spoonacularApiKey': 'LEGACY-KEY'});
    final db = FakeFirebaseFirestore();
    final container = _makeContainer(db);
    addTearDown(container.dispose);

    container.read(spoonacularKeyProvider);
    // Allow init -> stream emit -> migration write -> stream re-emit.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(spoonacularKeyProvider), 'LEGACY-KEY');
    final fs = await db.doc('households/hh1/config/apiKeys').get();
    expect(fs.data()?['spoonacularKey'], 'LEGACY-KEY');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('spoonacularApiKey'), false,
        reason: 'legacy entry should be cleaned up after migration');
  });

  test('set persists to Firestore and trims whitespace', () async {
    final db = FakeFirebaseFirestore();
    final container = _makeContainer(db);
    addTearDown(container.dispose);
    container.read(spoonacularKeyProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container
        .read(spoonacularKeyProvider.notifier)
        .set('  my-new-key  ');

    expect(container.read(spoonacularKeyProvider), 'my-new-key');
    final fs = await db.doc('households/hh1/config/apiKeys').get();
    expect(fs.data()?['spoonacularKey'], 'my-new-key');
  });

  test('set with empty string clears the Firestore field', () async {
    final db = FakeFirebaseFirestore();
    await db
        .doc('households/hh1/config/apiKeys')
        .set({'spoonacularKey': 'OLD-KEY'});
    final container = _makeContainer(db);
    addTearDown(container.dispose);
    container.read(spoonacularKeyProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container.read(spoonacularKeyProvider.notifier).set('');

    expect(container.read(spoonacularKeyProvider), '');
    final fs = await db.doc('households/hh1/config/apiKeys').get();
    expect(fs.data()?['spoonacularKey'], '');
  });
}
