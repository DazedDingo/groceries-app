import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/services/items_service.dart';
import 'package:groceries_app/services/meal_plan_service.dart';
import 'package:groceries_app/services/recipe_import_service.dart';
import 'package:groceries_app/services/recipes_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// JSON-LD payload matching what BBC Good Food / Allrecipes / NYT Cooking
/// actually serve. Using a fixture (not a live network call) keeps the test
/// hermetic but still exercises the real parser.
const _recipeHtml = '''
<!doctype html>
<html><head>
<meta property="og:title" content="Easy Pancakes" />
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Recipe",
  "name": "Easy Pancakes",
  "description": "Light, fluffy pancakes for a weekend breakfast.",
  "recipeIngredient": [
    "100 g plain flour",
    "2 eggs",
    "300 ml milk",
    "1 tsp vegetable oil",
    "1 pinch salt"
  ],
  "recipeInstructions": [
    {"@type": "HowToStep", "text": "Sift the flour into a bowl."},
    {"@type": "HowToStep", "text": "Whisk eggs and milk into the flour."},
    {"@type": "HowToStep", "text": "Heat oil in a frying pan and cook each pancake for 1 minute per side."}
  ]
}
</script>
</head><body><h1>Easy Pancakes</h1></body></html>
''';

void main() {
  group('e2e: import recipe → meal plan → shopping list', () {
    late FakeFirebaseFirestore db;
    late RecipesService recipes;
    late MealPlanService mealPlan;
    late ItemsService items;
    late RecipeImportService importer;

    const householdId = 'hh1';

    setUp(() {
      db = FakeFirebaseFirestore();
      recipes = RecipesService(db: db);
      mealPlan = MealPlanService(db: db);
      items = ItemsService(db: db);
      importer = RecipeImportService(
        client: MockClient((req) async {
          expect(req.url.toString(), 'https://example.com/easy-pancakes');
          expect(req.headers['User-Agent'], 'GroceriesApp/1.0');
          return http.Response(_recipeHtml, 200,
              headers: {'content-type': 'text/html'});
        }),
      );
    });

    test('import a URL → save → plan → push ingredients to list', () async {
      // 1) Import from URL
      final imported = await importer.importFromUrl('https://example.com/easy-pancakes');
      expect(imported.name, 'Easy Pancakes');
      expect(imported.ingredients.length, 5,
          reason: 'all 5 JSON-LD ingredients should parse');
      expect(imported.ingredients.first.name, contains('flour'),
          reason: 'text parser should extract the ingredient name');
      expect(imported.ingredients.first.quantity, 100);
      expect(imported.ingredients.first.unit, 'g');
      expect(imported.instructions.length, 3);
      expect(imported.sourceUrl, 'https://example.com/easy-pancakes');

      // 2) Save the imported recipe
      final recipeId = await recipes.addRecipe(
        householdId: householdId,
        name: imported.name,
        ingredients: imported.ingredients,
        instructions: imported.instructions,
        notes: imported.notes,
        sourceUrl: imported.sourceUrl,
      );
      expect(recipeId, isNotEmpty);

      // 3) Add the recipe to the meal plan for tomorrow at dinner (servings = 2)
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dinnerDay = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
      await mealPlan.addEntry(
        householdId: householdId,
        date: dinnerDay,
        meal: 'dinner',
        recipeId: recipeId,
        recipeName: imported.name,
        servings: 2,
      );

      // 4) Verify the meal plan stream surfaces the entry for that week
      final monday = dinnerDay.subtract(Duration(days: dinnerDay.weekday - 1));
      final weekStart = DateTime(monday.year, monday.month, monday.day);
      final entries = await mealPlan.weekStream(householdId, weekStart).first;
      expect(entries.length, 1);
      expect(entries.first.recipeName, 'Easy Pancakes');
      expect(entries.first.servings, 2);
      expect(entries.first.meal, 'dinner');

      // 5) Push every ingredient to the shopping list, scaled by servings
      // (matches the "Add all ingredients" flow in MealPlanScreen)
      final mealEntry = entries.first;
      final savedRecipeSnap = await db.doc('households/$householdId/recipes/$recipeId').get();
      final savedRecipe = (savedRecipeSnap.data() as Map<String, dynamic>);
      final savedIngs = (savedRecipe['ingredients'] as List)
          .map((m) => m as Map<String, dynamic>)
          .toList();

      const addedBy = AddedBy(uid: 'u1', displayName: 'Tester', source: ItemSource.app);
      for (final ing in savedIngs) {
        await items.addItem(
          householdId: householdId,
          name: ing['name'],
          categoryId: ing['categoryId'] ?? 'uncategorised',
          preferredStores: const [],
          pantryItemId: null,
          quantity: (ing['quantity'] as int) * mealEntry.servings,
          unit: ing['unit'],
          recipeSource: imported.name,
          addedBy: addedBy,
        );
      }

      // 6) Verify shopping list contains every ingredient with scaled quantity
      final listSnap = await db.collection('households/$householdId/items').get();
      expect(listSnap.docs.length, 5);

      final flour = listSnap.docs.firstWhere((d) => (d['name'] as String).contains('flour'));
      expect(flour['quantity'], 200, reason: '100g × 2 servings');
      expect(flour['unit'], 'g');
      expect(flour['recipeSource'], 'Easy Pancakes');

      final milk = listSnap.docs.firstWhere((d) => (d['name'] as String).contains('milk'));
      expect(milk['quantity'], 600, reason: '300ml × 2 servings');
      expect(milk['unit'], 'ml');
    });

    test('http error during import surfaces as exception (no silent failure)',
        () async {
      final failing = RecipeImportService(
        client: MockClient((_) async => http.Response('not found', 404)),
      );
      expect(
        () => failing.importFromUrl('https://example.com/missing'),
        throwsException,
      );
    });

    test('non-recipe page falls back to title + empty ingredients', () async {
      const plainHtml = '''
<html><head><title>Some Blog Post</title></head><body>no recipe here</body></html>
''';
      final fallback = RecipeImportService(
        client: MockClient((_) async => http.Response(plainHtml, 200)),
      );
      final result = await fallback.importFromUrl('https://example.com/blog');
      expect(result.name, 'Some Blog Post');
      expect(result.ingredients, isEmpty);
      expect(result.notes, contains('https://example.com/blog'));
    });
  });
}
