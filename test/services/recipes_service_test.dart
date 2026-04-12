import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:groceries_app/services/recipes_service.dart';
import 'package:groceries_app/models/recipe.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;
  late RecipesService service;
  const hid = 'test-household';

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    service = RecipesService(db: fakeDb);
  });

  test('addRecipe creates doc and stream emits it', () async {
    final id = await service.addRecipe(
      householdId: hid,
      name: 'Pancakes',
      ingredients: [
        const RecipeIngredient(name: 'Flour', quantity: 2, categoryId: 'bakery'),
        const RecipeIngredient(name: 'Eggs', quantity: 3, categoryId: 'dairy'),
      ],
      notes: 'Mix well',
    );
    expect(id, isNotEmpty);

    final recipes = await service.recipesStream(hid).first;
    expect(recipes.length, 1);
    expect(recipes.first.name, 'Pancakes');
    expect(recipes.first.ingredients.length, 2);
    expect(recipes.first.notes, 'Mix well');
  });

  test('updateRecipe changes fields', () async {
    final id = await service.addRecipe(
      householdId: hid,
      name: 'Old Name',
      ingredients: [const RecipeIngredient(name: 'A', quantity: 1)],
    );
    await service.updateRecipe(
      householdId: hid,
      recipeId: id,
      name: 'New Name',
      ingredients: [const RecipeIngredient(name: 'B', quantity: 2)],
      notes: 'Updated',
    );

    final recipes = await service.recipesStream(hid).first;
    expect(recipes.first.name, 'New Name');
    expect(recipes.first.ingredients.first.name, 'B');
  });

  test('deleteRecipe removes doc', () async {
    final id = await service.addRecipe(
      householdId: hid,
      name: 'ToDelete',
      ingredients: [],
    );
    await service.deleteRecipe(householdId: hid, recipeId: id);

    final recipes = await service.recipesStream(hid).first;
    expect(recipes, isEmpty);
  });
}
