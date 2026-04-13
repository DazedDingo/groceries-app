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
}
