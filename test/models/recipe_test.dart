import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/recipe.dart';

void main() {
  group('RecipeIngredient', () {
    test('toMap round-trips', () {
      const ing = RecipeIngredient(name: 'Flour', quantity: 2, categoryId: 'bakery');
      final map = ing.toMap();
      expect(map['name'], 'Flour');
      expect(map['quantity'], 2);
      expect(map['categoryId'], 'bakery');
    });

    test('fromMap with defaults', () {
      final ing = RecipeIngredient.fromMap({'name': 'Salt'});
      expect(ing.quantity, 1);
      expect(ing.categoryId, isNull);
    });
  });

  group('Recipe', () {
    test('toMap includes all fields', () {
      const recipe = Recipe(
        id: 'r1',
        name: 'Pasta',
        ingredients: [
          RecipeIngredient(name: 'Spaghetti', quantity: 1, categoryId: null),
          RecipeIngredient(name: 'Tomato sauce', quantity: 2, categoryId: 'canned'),
        ],
        notes: 'Cook 10 mins',
      );
      final map = recipe.toMap();
      expect(map['name'], 'Pasta');
      expect((map['ingredients'] as List).length, 2);
      expect(map['notes'], 'Cook 10 mins');
    });
  });
}
