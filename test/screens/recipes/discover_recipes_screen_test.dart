import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:groceries_app/providers/auth_provider.dart';
import 'package:groceries_app/providers/household_key_notifier.dart';
import 'package:groceries_app/providers/household_provider.dart';
import 'package:groceries_app/providers/recipe_search_provider.dart';
import 'package:groceries_app/providers/recipes_provider.dart';
import 'package:groceries_app/screens/recipes/discover_recipes_screen.dart';
import 'package:groceries_app/services/auth_service.dart';
import 'package:groceries_app/services/household_config_service.dart';
import 'package:groceries_app/services/household_service.dart';
import 'package:groceries_app/services/recipe_search_service.dart';
import 'package:groceries_app/services/recipes_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap({
  required RecipeSearchService searchService,
  required FakeFirebaseFirestore db,
  MockUser? user,
}) {
  final mockUser = user ??
      MockUser(
        uid: 'u1',
        email: 'alice@example.com',
        displayName: 'Alice',
      );
  final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

  final router = GoRouter(
    initialLocation: '/recipes/discover',
    routes: [
      GoRoute(
        path: '/recipes/discover',
        builder: (_, __) => const DiscoverRecipesScreen(),
      ),
      GoRoute(
        path: '/recipes',
        builder: (_, __) => const Scaffold(body: Text('recipes-home')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('settings-home')),
      ),
    ],
  );

  // Seed the user-doc householdId so HouseholdService can resolve it.
  db.doc('users/${mockUser.uid}').set({'householdId': 'hh1'});

  return ProviderScope(
    overrides: [
      recipeSearchServiceProvider.overrideWithValue(searchService),
      householdIdProvider.overrideWith((ref) async => 'hh1'),
      householdServiceProvider.overrideWithValue(HouseholdService(db: db)),
      authStateProvider.overrideWith((ref) => Stream.value(mockUser)),
      authServiceProvider.overrideWithValue(AuthService(auth: auth)),
      recipesServiceProvider.overrideWithValue(RecipesService(db: db)),
      householdConfigServiceProvider
          .overrideWithValue(HouseholdConfigService(db: db)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> seedSpoonacularKey(FakeFirebaseFirestore db, String v) async {
    if (v.isEmpty) return;
    await db
        .doc('households/hh1/config/apiKeys')
        .set({'spoonacularKey': v});
  }

  testWidgets('shows TheMealDB selected by default and empty state prompt',
      (tester) async {
    final client = MockClient((req) async => http.Response('{}', 200));
    final service = RecipeSearchService(client: client);
    await tester.pumpWidget(_wrap(
      searchService: service,
      db: FakeFirebaseFirestore(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TheMealDB'), findsOneWidget);
    expect(find.text('Spoonacular'), findsOneWidget);
    expect(find.text('Search for a recipe to get started'), findsOneWidget);
  });

  testWidgets('switching to Spoonacular without key shows Settings banner',
      (tester) async {
    final client = MockClient((req) async => http.Response('{}', 200));
    final service = RecipeSearchService(client: client);
    await tester.pumpWidget(_wrap(
      searchService: service,
      db: FakeFirebaseFirestore(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spoonacular'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Add your free Spoonacular API key'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Settings'), findsOneWidget);
  });

  testWidgets('Spoonacular banner hidden when key is set', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedSpoonacularKey(db, 'MY-KEY');
    final client = MockClient((req) async => http.Response('{}', 200));
    final service = RecipeSearchService(client: client);
    await tester.pumpWidget(_wrap(
      searchService: service,
      db: db,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spoonacular'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Add your free Spoonacular API key'),
        findsNothing);
  });

  testWidgets('search submits query and renders results', (tester) async {
    final client = MockClient((req) async {
      expect(req.url.host, 'www.themealdb.com');
      expect(req.url.queryParameters['s'], 'pasta');
      return http.Response(
        json.encode({
          'meals': [
            {
              'idMeal': '52771',
              'strMeal': 'Spicy Arrabiata Penne',
              'strMealThumb':
                  'https://www.themealdb.com/images/media/meals/x.jpg',
            },
          ],
        }),
        200,
      );
    });
    final service = RecipeSearchService(client: client);
    await tester.pumpWidget(_wrap(
      searchService: service,
      db: FakeFirebaseFirestore(),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pasta');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(); // loading
    await tester.pumpAndSettle();

    expect(find.text('Spicy Arrabiata Penne'), findsOneWidget);
    expect(find.text('TheMealDB'), findsWidgets);
  });

  testWidgets('search error is surfaced to the user', (tester) async {
    final client =
        MockClient((req) async => http.Response('server on fire', 500));
    final service = RecipeSearchService(client: client);
    await tester.pumpWidget(_wrap(
      searchService: service,
      db: FakeFirebaseFirestore(),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pasta');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.textContaining('TheMealDB error'), findsOneWidget);
  });

  testWidgets('tapping result saves recipe with addedBy attribution',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final client = MockClient((req) async {
      final url = req.url.toString();
      if (url.contains('search.php')) {
        return http.Response(
          json.encode({
            'meals': [
              {
                'idMeal': '52771',
                'strMeal': 'Spicy Arrabiata Penne',
                'strMealThumb': '',
              },
            ],
          }),
          200,
        );
      }
      if (url.contains('lookup.php')) {
        return http.Response(
          json.encode({
            'meals': [
              {
                'idMeal': '52771',
                'strMeal': 'Spicy Arrabiata Penne',
                'strCategory': 'Vegetarian',
                'strArea': 'Italian',
                'strInstructions': 'Boil water.\nAdd pasta.',
                'strSource': 'https://example.com/penne',
                'strIngredient1': 'penne',
                'strMeasure1': '200 g',
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final service = RecipeSearchService(client: client);

    await tester.pumpWidget(_wrap(searchService: service, db: db));
    await tester.pumpAndSettle();

    // Search
    await tester.enterText(find.byType(TextField), 'pasta');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // Tap result
    await tester.tap(find.text('Spicy Arrabiata Penne'));
    await tester.pumpAndSettle();

    // Preview sheet should show ingredient + save button
    expect(find.text('Save to my recipes'), findsOneWidget);
    expect(find.textContaining('penne'), findsWidgets);

    await tester.tap(find.text('Save to my recipes'));
    await tester.pumpAndSettle();

    // Verify Firestore write landed with addedBy
    final snap = await db.collection('households/hh1/recipes').get();
    expect(snap.docs.length, 1);
    expect(snap.docs.first['name'], 'Spicy Arrabiata Penne');
    expect(snap.docs.first['addedByUid'], 'u1');
    expect(snap.docs.first['addedByDisplayName'], 'Alice');
  });
}
