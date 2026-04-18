import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/shelf_life_guesser.dart';

void main() {
  group('guessShelfLifeDays', () {
    test('returns correct days for known categories', () {
      expect(guessShelfLifeDays('Meats'), 3);
      expect(guessShelfLifeDays('Dairy'), 10);
      expect(guessShelfLifeDays('Produce'), 7);
      expect(guessShelfLifeDays('Bakery'), 5);
      expect(guessShelfLifeDays('Frozen'), 90);
      expect(guessShelfLifeDays('Drinks'), 30);
      expect(guessShelfLifeDays('Spices'), 365);
      expect(guessShelfLifeDays('Household'), 365);
    });

    test('is case insensitive', () {
      expect(guessShelfLifeDays('MEATS'), 3);
      expect(guessShelfLifeDays('dairy'), 10);
      expect(guessShelfLifeDays('Frozen'), 90);
    });

    test('returns null for unknown category', () {
      expect(guessShelfLifeDays('Snacks'), isNull);
      expect(guessShelfLifeDays(''), isNull);
    });

    test('meats value matches dropdown option (3, not 4)', () {
      // Regression: meats was 4 which didn't match the shelf life dropdown
      expect(guessShelfLifeDays('Meats'), 3);
    });
  });

  group('guessShelfLifeDays — per-item name overrides', () {
    test('name match wins over category default', () {
      // Milk overrides dairy's 10 → 7
      expect(guessShelfLifeDays('Dairy', itemName: 'Whole Milk'), 7);
      // Yogurt overrides dairy's 10 → 21
      expect(guessShelfLifeDays('Dairy', itemName: 'Greek Yogurt'), 21);
      // Bacon overrides meats' 3 → 7
      expect(guessShelfLifeDays('Meats', itemName: 'Bacon strips'), 7);
      // Potato overrides produce's 7 → 30
      expect(guessShelfLifeDays('Produce', itemName: 'Russet potatoes'), 30);
    });

    test('longest keyword wins (multi-word prefers over single)', () {
      // "chicken breast" (2d) wins over "chicken" (3d)
      expect(guessShelfLifeDays('Meats', itemName: 'Chicken breast'), 2);
      // "sweet potato" (21d) wins over "potato" (30d)
      expect(guessShelfLifeDays('Produce', itemName: 'Sweet potato'), 21);
      // "hard cheese" (60d) wins over "cheese" (21d)
      expect(guessShelfLifeDays('Dairy', itemName: 'Hard cheese wedge'), 60);
      // "cream cheese" (14d) wins over "cream" (7d) and "cheese" (21d)
      expect(guessShelfLifeDays('Dairy', itemName: 'Cream cheese'), 14);
    });

    test('case-insensitive name matching', () {
      expect(guessShelfLifeDays('Dairy', itemName: 'MILK'), 7);
      expect(guessShelfLifeDays('Meats', itemName: 'Ground BEEF'), 2);
    });

    test('falls back to category when name has no match', () {
      expect(guessShelfLifeDays('Dairy', itemName: 'Kefir'), 10);
      expect(guessShelfLifeDays('Produce', itemName: 'Exotic fruit'), 7);
    });

    test('null or empty itemName falls through to category', () {
      expect(guessShelfLifeDays('Meats', itemName: null), 3);
      expect(guessShelfLifeDays('Meats', itemName: ''), 3);
    });

    test('returns null if neither name nor category match', () {
      expect(guessShelfLifeDays('Unknown', itemName: 'Exotic thing'), isNull);
    });
  });
}
