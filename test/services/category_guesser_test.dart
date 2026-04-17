import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/category.dart';
import 'package:groceries_app/services/category_guesser.dart';

final _categories = [
  const GroceryCategory(id: '1', name: 'Meats', color: Color(0xFFFF0000), addedBy: 'system'),
  const GroceryCategory(id: '2', name: 'Dairy', color: Color(0xFF0000FF), addedBy: 'system'),
  const GroceryCategory(id: '3', name: 'Produce', color: Color(0xFF00FF00), addedBy: 'system'),
  const GroceryCategory(id: '4', name: 'Bakery', color: Color(0xFFFFFF00), addedBy: 'system'),
  const GroceryCategory(id: '5', name: 'Spices', color: Color(0xFFFF00FF), addedBy: 'system'),
  const GroceryCategory(id: '6', name: 'Frozen', color: Color(0xFF00FFFF), addedBy: 'system'),
  const GroceryCategory(id: '7', name: 'Drinks', color: Color(0xFF888888), addedBy: 'system'),
  const GroceryCategory(id: '8', name: 'Household', color: Color(0xFF444444), addedBy: 'system'),
];

void main() {
  group('guessCategory', () {
    group('meats', () {
      test('chicken', () => expect(guessCategory('chicken', _categories)?.name, 'Meats'));
      test('beef mince', () => expect(guessCategory('beef mince', _categories)?.name, 'Meats'));
      test('salmon fillet', () => expect(guessCategory('salmon fillet', _categories)?.name, 'Meats'));
      test('bacon', () => expect(guessCategory('bacon', _categories)?.name, 'Meats'));
      test('prawns', () => expect(guessCategory('prawn', _categories)?.name, 'Meats'));
    });

    group('dairy', () {
      test('milk', () => expect(guessCategory('milk', _categories)?.name, 'Dairy'));
      test('cheddar cheese', () => expect(guessCategory('cheddar cheese', _categories)?.name, 'Dairy'));
      test('eggs', () => expect(guessCategory('eggs', _categories)?.name, 'Dairy'));
      test('yoghurt', () => expect(guessCategory('yoghurt', _categories)?.name, 'Dairy'));
      test('butter', () => expect(guessCategory('butter', _categories)?.name, 'Dairy'));
    });

    group('produce', () {
      test('banana', () => expect(guessCategory('banana', _categories)?.name, 'Produce'));
      test('broccoli', () => expect(guessCategory('broccoli', _categories)?.name, 'Produce'));
      test('garlic', () => expect(guessCategory('garlic', _categories)?.name, 'Produce'));
      test('mixed salad', () => expect(guessCategory('mixed salad', _categories)?.name, 'Produce'));
    });

    group('US/UK aliases', () {
      test('cilantro → Produce', () => expect(guessCategory('cilantro', _categories)?.name, 'Produce'));
      test('coriander → Produce', () => expect(guessCategory('coriander', _categories)?.name, 'Produce'));
      test('aubergine → Produce', () => expect(guessCategory('aubergine', _categories)?.name, 'Produce'));
      test('eggplant → Produce', () => expect(guessCategory('eggplant', _categories)?.name, 'Produce'));
      test('capsicum → Produce', () => expect(guessCategory('capsicum', _categories)?.name, 'Produce'));
      test('bell pepper → Produce', () => expect(guessCategory('bell pepper', _categories)?.name, 'Produce'));
      test('zucchini → Produce', () => expect(guessCategory('zucchini', _categories)?.name, 'Produce'));
      test('scallion → Produce', () => expect(guessCategory('scallion', _categories)?.name, 'Produce'));
      test('spring onion → Produce', () => expect(guessCategory('spring onion', _categories)?.name, 'Produce'));
      test('green onion → Produce', () => expect(guessCategory('green onion', _categories)?.name, 'Produce'));
      test('arugula → Produce', () => expect(guessCategory('arugula', _categories)?.name, 'Produce'));
      test('rocket → Produce', () => expect(guessCategory('rocket', _categories)?.name, 'Produce'));
      test('eggplant beats eggs (longer wins)', () {
        expect(guessCategory('eggplant parmesan', _categories)?.name, 'Produce');
      });
    });

    group('bakery', () {
      test('bread', () => expect(guessCategory('bread', _categories)?.name, 'Bakery'));
      test('croissant', () => expect(guessCategory('croissant', _categories)?.name, 'Bakery'));
      test('flour', () => expect(guessCategory('flour', _categories)?.name, 'Bakery'));
      test('pitta bread', () => expect(guessCategory('pitta bread', _categories)?.name, 'Bakery'));
    });

    group('spices', () {
      test('cumin', () => expect(guessCategory('cumin', _categories)?.name, 'Spices'));
      test('ground cinnamon', () => expect(guessCategory('ground cinnamon', _categories)?.name, 'Spices'));
    });

    group('drinks', () {
      test('orange juice matches Drinks (longer keyword wins)', () {
        // "orange juice" is a specific keyword and longer than "orange" —
        // length-sorted matching picks the specific term.
        expect(guessCategory('orange juice', _categories)?.name, 'Drinks');
      });
      test('apple juice falls back to Produce', () {
        // No specific "apple juice" keyword; "apple" and "juice" are same length,
        // insertion order wins → apple (Produce).
        expect(guessCategory('apple juice', _categories)?.name, 'Produce');
      });
      test('coffee', () => expect(guessCategory('coffee', _categories)?.name, 'Drinks'));
      test('beer', () => expect(guessCategory('beer', _categories)?.name, 'Drinks'));
      test('lemonade matches Drinks (longer than lemon)', () {
        expect(guessCategory('lemonade', _categories)?.name, 'Drinks');
      });
      test('soda', () => expect(guessCategory('soda', _categories)?.name, 'Drinks'));
    });

    group('length-sorted keyword priority', () {
      test('ice cream matches Frozen, not cream→Dairy', () {
        expect(guessCategory('ice cream', _categories)?.name, 'Frozen');
      });
      test('washing up liquid matches Household', () {
        expect(guessCategory('washing up liquid', _categories)?.name, 'Household');
      });
      test('bin bags matches Household', () {
        expect(guessCategory('bin bags', _categories)?.name, 'Household');
      });
    });

    group('household', () {
      test('dishwasher detergent', () => expect(guessCategory('dishwasher detergent', _categories)?.name, 'Household'));
      test('toothpaste', () => expect(guessCategory('toothpaste', _categories)?.name, 'Household'));
      test('bin bags', () => expect(guessCategory('bin bag', _categories)?.name, 'Household'));
    });

    group('case insensitivity', () {
      test('CHICKEN matches meats', () => expect(guessCategory('CHICKEN', _categories)?.name, 'Meats'));
      test('Milk matches dairy', () => expect(guessCategory('Milk', _categories)?.name, 'Dairy'));
    });

    group('no match', () {
      test('unknown item returns null', () => expect(guessCategory('widget', _categories), isNull));
      test('empty string returns null', () => expect(guessCategory('', _categories), isNull));
      test('empty categories returns null', () => expect(guessCategory('chicken', []), isNull));
    });
  });
}
