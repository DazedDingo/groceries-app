// Round 2: end-to-end integration coverage for the bulk voice add feature
// and the per-household API-key storage model.
// Scenarios exercised here go across multiple providers, services, and
// Firestore paths — the kind of cross-cutting issue unit tests miss.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/providers/auth_provider.dart';
import 'package:groceries_app/providers/categories_provider.dart';
import 'package:groceries_app/providers/gemini_key_provider.dart';
import 'package:groceries_app/providers/household_key_notifier.dart';
import 'package:groceries_app/providers/household_provider.dart';
import 'package:groceries_app/providers/items_provider.dart';
import 'package:groceries_app/providers/recipe_search_provider.dart';
import 'package:groceries_app/screens/shopping_list/bulk_voice_screen.dart';
import 'package:groceries_app/services/auth_service.dart';
import 'package:groceries_app/services/bulk_voice_parser.dart';
import 'package:groceries_app/services/categories_service.dart';
import 'package:groceries_app/services/category_overrides.dart';
import 'package:groceries_app/services/household_config_service.dart';
import 'package:groceries_app/services/household_service.dart';
import 'package:groceries_app/services/items_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _containerFor({
  required FakeFirebaseFirestore db,
  required String uid,
  required String householdId,
}) {
  final mockUser = MockUser(uid: uid, email: '$uid@x.com', displayName: uid);
  final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
  db.doc('users/$uid').set({'householdId': householdId});
  return ProviderContainer(
    overrides: [
      householdIdProvider.overrideWith((ref) async => householdId),
      householdServiceProvider.overrideWithValue(HouseholdService(db: db)),
      authStateProvider.overrideWith((ref) => Stream.value(mockUser)),
      authServiceProvider.overrideWithValue(AuthService(auth: auth)),
      itemsServiceProvider.overrideWithValue(ItemsService(db: db)),
      categoriesServiceProvider.overrideWithValue(CategoriesService(db: db)),
      categoryOverrideServiceProvider
          .overrideWithValue(CategoryOverrideService(db: db)),
      householdConfigServiceProvider
          .overrideWithValue(HouseholdConfigService(db: db)),
    ],
  );
}

Future<void> _tick([int ms = 60]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Multi-household API key isolation', () {
    test('keys set in one household never leak to another', () async {
      final db = FakeFirebaseFirestore();
      final alice = _containerFor(db: db, uid: 'alice', householdId: 'hhA');
      final bob = _containerFor(db: db, uid: 'bob', householdId: 'hhB');
      addTearDown(alice.dispose);
      addTearDown(bob.dispose);

      await alice
          .read(geminiKeyProvider.notifier)
          .set('AIza-ALICE-HOUSEHOLD');
      await _tick();

      // Force bob's notifier to hydrate; should remain empty.
      bob.read(geminiKeyProvider);
      await _tick();
      expect(bob.read(geminiKeyProvider), '');

      // And Alice's household A doc has the key.
      final docA = await db.doc('households/hhA/config/apiKeys').get();
      expect(docA.data()?['geminiKey'], 'AIza-ALICE-HOUSEHOLD');
      final docB = await db.doc('households/hhB/config/apiKeys').get();
      expect(docB.exists, false,
          reason: 'Bob\'s household must not have been touched');
    });

    test('two members of SAME household share the same key reactively',
        () async {
      final db = FakeFirebaseFirestore();
      final alice =
          _containerFor(db: db, uid: 'alice', householdId: 'shared-hh');
      final bob =
          _containerFor(db: db, uid: 'bob', householdId: 'shared-hh');
      addTearDown(alice.dispose);
      addTearDown(bob.dispose);

      // Bob reads first, gets empty.
      bob.read(geminiKeyProvider);
      await _tick();
      expect(bob.read(geminiKeyProvider), '');

      // Alice sets the key.
      await alice
          .read(geminiKeyProvider.notifier)
          .set('SHARED-AIza-KEY');
      // Bob should see it appear via the stream.
      await _tick(120);
      expect(bob.read(geminiKeyProvider), 'SHARED-AIza-KEY');
    });

    test('setting Spoonacular in one hh leaves Gemini in another untouched',
        () async {
      final db = FakeFirebaseFirestore();
      await db
          .doc('households/hhA/config/apiKeys')
          .set({'geminiKey': 'KEEP-GEMINI-A'});
      final alice = _containerFor(db: db, uid: 'alice', householdId: 'hhA');
      final bob = _containerFor(db: db, uid: 'bob', householdId: 'hhB');
      addTearDown(alice.dispose);
      addTearDown(bob.dispose);

      await bob
          .read(spoonacularKeyProvider.notifier)
          .set('SPOON-FOR-B');
      await _tick();

      final docA = await db.doc('households/hhA/config/apiKeys').get();
      final docB = await db.doc('households/hhB/config/apiKeys').get();
      expect(docA.data()?['geminiKey'], 'KEEP-GEMINI-A');
      expect(docA.data()?['spoonacularKey'], isNull);
      expect(docB.data()?['spoonacularKey'], 'SPOON-FOR-B');
      expect(docB.data()?['geminiKey'], isNull);
    });
  });

  group('End-to-end migration', () {
    test('legacy SharedPreferences -> Firestore, keys survive container reset',
        () async {
      SharedPreferences.setMockInitialValues({
        'geminiApiKey': 'LEGACY-GEM',
        'spoonacularApiKey': 'LEGACY-SPOON',
      });
      final db = FakeFirebaseFirestore();

      // First session: migration fires.
      final session1 =
          _containerFor(db: db, uid: 'alice', householdId: 'hh1');
      session1.read(geminiKeyProvider);
      session1.read(spoonacularKeyProvider);
      await _tick(150);
      expect(session1.read(geminiKeyProvider), 'LEGACY-GEM');
      expect(session1.read(spoonacularKeyProvider), 'LEGACY-SPOON');
      session1.dispose();

      // Second session: legacy prefs gone, Firestore is source of truth.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('geminiApiKey'), false);
      expect(prefs.containsKey('spoonacularApiKey'), false);

      final session2 =
          _containerFor(db: db, uid: 'alice', householdId: 'hh1');
      addTearDown(session2.dispose);
      session2.read(geminiKeyProvider);
      session2.read(spoonacularKeyProvider);
      await _tick(100);
      expect(session2.read(geminiKeyProvider), 'LEGACY-GEM');
      expect(session2.read(spoonacularKeyProvider), 'LEGACY-SPOON');
    });

    test('fresh user with no prefs and no Firestore keys starts empty',
        () async {
      final db = FakeFirebaseFirestore();
      final container =
          _containerFor(db: db, uid: 'newbie', householdId: 'hh1');
      addTearDown(container.dispose);
      container.read(geminiKeyProvider);
      container.read(spoonacularKeyProvider);
      await _tick(100);
      expect(container.read(geminiKeyProvider), '');
      expect(container.read(spoonacularKeyProvider), '');
      final doc = await db.doc('households/hh1/config/apiKeys').get();
      expect(doc.exists, false,
          reason: 'no migration should create a doc if nothing to migrate');
    });
  });

  group('Bulk voice end-to-end flow', () {
    // Simulates: user speaks → parser produces items → user taps Add →
    // items land in Firestore items collection with proper attribution
    // and history entries.
    testWidgets('transcript flows to shopping list items with history entries',
        (tester) async {
      final db = FakeFirebaseFirestore();
      // Pre-seed the key & a category so guessCategory can match.
      await db
          .doc('households/hh1/config/apiKeys')
          .set({'geminiKey': 'AIza-T'});
      await db.collection('households/hh1/categories').add({
        'name': 'Dairy',
        'color': '#000000',
      });

      final mockUser = MockUser(
          uid: 'alice', email: 'a@b.com', displayName: 'Alice');
      final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
      db.doc('users/alice').set({'householdId': 'hh1'});

      final parserResult = [
        ParsedVoiceItem(name: 'whole milk', quantity: 2, unit: 'L'),
        ParsedVoiceItem(name: 'cinnamon sticks', quantity: 3),
      ];

      await tester.pumpWidget(ProviderScope(
        overrides: [
          householdIdProvider.overrideWith((ref) async => 'hh1'),
          householdServiceProvider.overrideWithValue(HouseholdService(db: db)),
          authStateProvider.overrideWith((ref) => Stream.value(mockUser)),
          authServiceProvider.overrideWithValue(AuthService(auth: auth)),
          itemsServiceProvider.overrideWithValue(ItemsService(db: db)),
          categoriesServiceProvider
              .overrideWithValue(CategoriesService(db: db)),
          categoryOverrideServiceProvider
              .overrideWithValue(CategoryOverrideService(db: db)),
          householdConfigServiceProvider
              .overrideWithValue(HouseholdConfigService(db: db)),
          bulkVoiceParseFnProvider.overrideWithValue(
            (_) async => parserResult,
          ),
        ],
        child: const MaterialApp(
          home: BulkVoiceScreen(autoStartListening: false),
        ),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<BulkVoiceScreenState>(
        find.byType(BulkVoiceScreen),
      );
      // Simulate user speech by injecting a transcript and triggering parse.
      state.seedForTest(transcript: 'two whole milk in L, three cinnamon sticks');
      await tester.pump();
      await state.triggerParseForTest();
      await tester.pumpAndSettle();

      expect(find.text('whole milk'), findsOneWidget);
      expect(find.text('cinnamon sticks'), findsOneWidget);

      // Tap Add.
      await tester.tap(find.widgetWithText(FilledButton, 'Add 2 to list'));
      // Poll fake firestore until the write lands.
      var written = 0;
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        final snap = await db.collection('households/hh1/items').get();
        written = snap.docs.length;
        if (written >= 2) break;
      }

      expect(written, 2);

      final items = await db.collection('households/hh1/items').get();
      final byName = {for (var d in items.docs) d['name']: d.data()};
      expect(byName['whole milk']?['quantity'], 2);
      expect(byName['whole milk']?['unit'], 'L');
      expect(byName['cinnamon sticks']?['quantity'], 3);
      // Attribution: voice in-app, by Alice.
      expect(byName['whole milk']?['addedBy']['displayName'], 'Alice');
      expect(byName['whole milk']?['addedBy']['source'], 'voice_in_app');

      // History records created atomically alongside the items.
      final history = await db.collection('households/hh1/history').get();
      expect(history.docs.length, 2);
      expect(history.docs.every((d) => d['action'] == 'added'), isTrue);
    });
  });
}
