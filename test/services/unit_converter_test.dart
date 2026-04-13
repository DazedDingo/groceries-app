import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/unit_converter.dart';

void main() {
  group('formatQuantityUnit', () {
    group('no unit', () {
      test('quantity 1 returns empty string', () {
        expect(formatQuantityUnit(1, null, UnitSystem.metric), '');
      });

      test('quantity > 1 returns multiplier', () {
        expect(formatQuantityUnit(3, null, UnitSystem.metric), '×3');
      });

      test('empty string unit treated as no unit', () {
        expect(formatQuantityUnit(2, '', UnitSystem.metric), '×2');
      });
    });

    group('metric system (no conversion needed)', () {
      test('grams stay as grams', () {
        expect(formatQuantityUnit(500, 'g', UnitSystem.metric), '500 g');
      });

      test('kg stays as kg', () {
        expect(formatQuantityUnit(2, 'kg', UnitSystem.metric), '2 kg');
      });

      test('ml stays as ml', () {
        expect(formatQuantityUnit(250, 'ml', UnitSystem.metric), '250 ml');
      });

      test('L stays as L', () {
        expect(formatQuantityUnit(1, 'L', UnitSystem.metric), '1 L');
      });
    });

    group('metric → US conversion', () {
      test('grams to ounces', () {
        final result = formatQuantityUnit(100, 'g', UnitSystem.us);
        // 100g * 0.035274 = 3.5274 → "3.5 oz"
        expect(result, '3.5 oz');
      });

      test('kg to lb', () {
        final result = formatQuantityUnit(1, 'kg', UnitSystem.us);
        // 1kg * 2.20462 = 2.20462 → "2.2 lb"
        expect(result, '2.2 lb');
      });

      test('ml to fl oz', () {
        final result = formatQuantityUnit(500, 'ml', UnitSystem.us);
        // 500ml * 0.033814 = 16.907 → "16.9 fl oz"
        expect(result, '16.9 fl oz');
      });

      test('L to gal', () {
        final result = formatQuantityUnit(4, 'L', UnitSystem.us);
        // 4L * 0.264172 = 1.056688 → "1.1 gal"
        expect(result, '1.1 gal');
      });
    });

    group('US → metric conversion', () {
      test('oz to grams in metric mode', () {
        final result = formatQuantityUnit(10, 'oz', UnitSystem.metric);
        // 10oz * 28.3495 = 283.495 → "283.5 g"
        expect(result, '283.5 g');
      });

      test('lb to kg in metric mode', () {
        final result = formatQuantityUnit(5, 'lb', UnitSystem.metric);
        // 5lb * 0.453592 = 2.26796 → "2.3 kg"
        expect(result, '2.3 kg');
      });
    });

    group('units already in target system', () {
      test('oz in US mode stays oz', () {
        final result = formatQuantityUnit(8, 'oz', UnitSystem.us);
        expect(result, '8 oz');
      });

      test('lb in US mode stays lb', () {
        final result = formatQuantityUnit(3, 'lb', UnitSystem.us);
        expect(result, '3 lb');
      });

      test('cups in US mode stays cups', () {
        final result = formatQuantityUnit(2, 'cups', UnitSystem.us);
        expect(result, '2 cups');
      });
    });

    group('non-convertible units', () {
      test('packs are passed through', () {
        expect(formatQuantityUnit(3, 'packs', UnitSystem.metric), '3 packs');
        expect(formatQuantityUnit(3, 'packs', UnitSystem.us), '3 packs');
      });

      test('cans are passed through', () {
        expect(formatQuantityUnit(2, 'cans', UnitSystem.metric), '2 cans');
      });

      test('dozen is passed through', () {
        expect(formatQuantityUnit(1, 'dozen', UnitSystem.us), '1 dozen');
      });
    });
  });
}
