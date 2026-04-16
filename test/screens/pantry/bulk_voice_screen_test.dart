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
import 'package:groceries_app/providers/pantry_provider.dart';
import 'package:groceries_app/screens/pantry/bulk_voice_screen.dart';
import 'package:groceries_app/services/auth_service.dart';
import 'package:groceries_app/services/bulk_voice_parser.dart';
import 'package:groceries_app/services/categories_service.dart';
import 'package:groceries_app/services/category_overrides.dart';
import 'package:groceries_app/services/household_config_service.dart';
import 'package:groceries_app/services/household_service.dart';
import 'package:groceries_app/services/pantry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeParser {
  final List<String> calls = [];
  Future<List<ParsedVoiceItem>> Function(String) handler;
  _FakeParser(this.handler);
  Future<List<ParsedVoiceItem>> call(String t) {
    calls.add(t);
    return handler(t);
  }
}

Widget _wrap({
  required FakeFirebaseFirestore db,
  required _FakeParser parser,
  String householdId = 'hh1',
  bool autoStartListening = false,
}) {
  final mockUser = MockUser(uid: 'u1', email: 'a@b.com', displayName: 'Alice');
  final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
  db.doc('users/${mockUser.uid}').set({'householdId': householdId});

  return ProviderScope(
    overrides: [
      householdIdProvider.overrideWith((ref) async => householdId),
      householdServiceProvider.overrideWithValue(HouseholdService(db: db)),
      authStateProvider.overrideWith((ref) => Stream.value(mockUser)),
      authServiceProvider.overrideWithValue(AuthService(auth: auth)),
      pantryServiceProvider.overrideWithValue(PantryService(db: db)),
      categoriesServiceProvider.overrideWithValue(CategoriesService(db: db)),
      categoryOverrideServiceProvider
          .overrideWithValue(CategoryOverrideService(db: db)),
      householdConfigServiceProvider
          .overrideWithValue(HouseholdConfigService(db: db)),
      bulkVoiceParseFnProvider.overrideWithValue(parser.call),
    ],
    child: MaterialApp(
      home: PantryBulkVoiceScreen(autoStartListening: autoStartListening),
    ),
  );
}

PantryBulkVoiceScreenState _state(WidgetTester tester) =>
    tester.state<PantryBulkVoiceScreenState>(
        find.byType(PantryBulkVoiceScreen));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows missing-key banner when no Gemini key set',
      (tester) async {
    final parser = _FakeParser((_) async => []);
    await tester.pumpWidget(_wrap(db: FakeFirebaseFirestore(), parser: parser));
    await tester.pumpAndSettle();
    expect(find.textContaining('Set a Gemini API key'), findsOneWidget);
  });

  testWidgets('Add N to pantry button is disabled when no items',
      (tester) async {
    final parser = _FakeParser((_) async => []);
    await tester.pumpWidget(_wrap(db: FakeFirebaseFirestore(), parser: parser));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add 0 to pantry'),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets(
      'parsed items seed both current and optimal from the dictated quantity',
      (tester) async {
    // Parser is only invoked when a Gemini key is present — other tests seed
    // this via SharedPreferences. The setUp above resets it, so do it per-test.
    SharedPreferences.setMockInitialValues({'geminiApiKey': 'AIzaTEST'});
    final db = FakeFirebaseFirestore();
    // Seed categories so guessCategory has something to resolve against.
    await db.collection('households/hh1/categories').add({
      'name': 'Pantry',
      'color': 0xFF000000,
      'keywords': ['pasta', 'tomato'],
    });
    final parser = _FakeParser((_) async => [
          ParsedVoiceItem(name: 'pasta', quantity: 3),
          ParsedVoiceItem(name: 'tomato tins', quantity: 4, unit: 'cans'),
        ]);
    await tester.pumpWidget(_wrap(db: db, parser: parser));
    await tester.pumpAndSettle();
    _state(tester).seedForTest(transcript: '3 pasta, 4 tomato tins');
    await tester.pumpAndSettle();
    await _state(tester).triggerParseForTest();
    await tester.pumpAndSettle();

    // Review list shows both current and optimal; both default to dictated qty.
    expect(find.text('Current 3  ·  Optimal 3'), findsOneWidget);
    expect(find.text('Current 4 cans  ·  Optimal 4 cans'), findsOneWidget);
  });

  testWidgets(
      'addAll writes each item with the current/optimal shown in the review list',
      (tester) async {
    final db = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({'geminiApiKey': 'AIzaTEST'});
    final parser = _FakeParser((_) async => []);
    await tester.pumpWidget(_wrap(db: db, parser: parser));
    await tester.pumpAndSettle();
    _state(tester).seedForTest(items: const [
      PantryReviewItem(
          name: 'Pasta', currentQuantity: 3, optimalQuantity: 6, unit: null),
      PantryReviewItem(
          name: 'Olive oil',
          currentQuantity: 1,
          optimalQuantity: 1,
          unit: 'L'),
    ]);
    await tester.pumpAndSettle();
    await _state(tester).triggerAddAllForTest();
    await tester.pumpAndSettle();

    final snap = await db.collection('households/hh1/pantry').get();
    expect(snap.docs.length, 2);
    final byName = {for (final d in snap.docs) d['name']: d.data()};
    // currentQuantity and optimalQuantity are written exactly as reviewed —
    // this is the key regression to catch: previously currentQuantity was
    // hard-coded to 0 and the commander lost the ability to pre-seed stock.
    expect(byName['Pasta']!['currentQuantity'], 3);
    expect(byName['Pasta']!['optimalQuantity'], 6);
    expect(byName['Olive oil']!['currentQuantity'], 1);
    expect(byName['Olive oil']!['optimalQuantity'], 1);
    expect(byName['Olive oil']!['unit'], 'L');
  });

  testWidgets('re-parse preserves user-edited current/optimal on kept items',
      (tester) async {
    final db = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({'geminiApiKey': 'AIzaTEST'});
    // Parser returns the same "pasta" that's already in the review list with
    // its user-edited current=2/optimal=8. If the screen rebuilt from the
    // parse output it would reset to 3/3 — we must keep the edits.
    final parser = _FakeParser((_) async => [
          ParsedVoiceItem(name: 'pasta', quantity: 3),
        ]);
    await tester.pumpWidget(_wrap(db: db, parser: parser));
    await tester.pumpAndSettle();
    _state(tester).seedForTest(
      transcript: '3 pasta',
      items: const [
        PantryReviewItem(
            name: 'pasta',
            currentQuantity: 2,
            optimalQuantity: 8,
            unit: null),
      ],
    );
    await tester.pumpAndSettle();
    await _state(tester).triggerParseForTest();
    await tester.pumpAndSettle();

    expect(find.text('Current 2  ·  Optimal 8'), findsOneWidget);
    expect(find.text('Current 3  ·  Optimal 3'), findsNothing);
  });

  testWidgets('silence timeout force-parses without waiting for debounce',
      (tester) async {
    final db = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({'geminiApiKey': 'AIzaTEST'});
    var parseCount = 0;
    final parser = _FakeParser((_) async {
      parseCount++;
      return const [];
    });
    await tester.pumpWidget(_wrap(db: db, parser: parser));
    await tester.pumpAndSettle();
    final s = _state(tester);
    s.seedForTest(transcript: '3 pasta');
    s.setListeningForTest(true);
    // Bypass the 1500ms debounce: silence timeout schedules an immediate parse.
    s.triggerSilenceTimeoutForTest();
    // Shorter than the debounce — if it used the slow path, no parse fires yet.
    await tester.pump(const Duration(milliseconds: 50));
    expect(parseCount, 1);
  });
}
