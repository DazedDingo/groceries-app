import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/recipe.dart';

void main() {
  group('Recipe tags', () {
    test('toMap includes tags', () {
      const recipe = Recipe(
        id: 'r1', name: 'Pasta',
        ingredients: [],
        tags: ['italian', 'quick', 'vegetarian'],
      );
      final map = recipe.toMap();
      expect(map['tags'], ['italian', 'quick', 'vegetarian']);
    });

    test('toMap includes empty tags list', () {
      const recipe = Recipe(id: 'r1', name: 'Soup', ingredients: []);
      final map = recipe.toMap();
      expect(map['tags'], isEmpty);
    });

    test('Recipe defaults to empty tags', () {
      const recipe = Recipe(id: 'r1', name: 'Salad', ingredients: []);
      expect(recipe.tags, isEmpty);
    });
  });

  group('RecipeIngredient quantity scaling', () {
    test('quantity multiplied correctly for Cook This', () {
      const ing = RecipeIngredient(name: 'Flour', quantity: 2, unit: 'kg');
      const multiplier = 3;
      expect(ing.quantity * multiplier, 6);
    });
  });
}
