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

  group('hasEnough', () {
    group('same unit', () {
      test('sufficient grams', () {
        expect(hasEnough(500, 'g', 200, 'g'), isTrue);
      });
      test('insufficient grams', () {
        expect(hasEnough(100, 'g', 200, 'g'), isFalse);
      });
      test('equal quantities', () {
        expect(hasEnough(200, 'g', 200, 'g'), isTrue);
      });
      test('both null units', () {
        expect(hasEnough(3, null, 2, null), isTrue);
        expect(hasEnough(1, null, 2, null), isFalse);
      });
      test('both empty units', () {
        expect(hasEnough(3, '', 2, ''), isTrue);
      });
    });

    group('same-system magnitude conversion (weight)', () {
      test('1kg pantry covers 200g recipe', () {
        expect(hasEnough(1, 'kg', 200, 'g'), isTrue);
      });
      test('500g pantry does not cover 1kg recipe', () {
        expect(hasEnough(500, 'g', 1, 'kg'), isFalse);
      });
      test('case-insensitive unit match', () {
        expect(hasEnough(1, 'KG', 200, 'G'), isTrue);
      });
    });

    group('same-system magnitude conversion (volume)', () {
      test('1L pantry covers 500ml recipe', () {
        expect(hasEnough(1, 'L', 500, 'ml'), isTrue);
      });
      test('500ml pantry does not cover 1L recipe', () {
        expect(hasEnough(500, 'ml', 1, 'L'), isFalse);
      });
      test('cups to ml', () {
        // 2 cups = 480ml
        expect(hasEnough(2, 'cups', 400, 'ml'), isTrue);
        expect(hasEnough(2, 'cups', 500, 'ml'), isFalse);
      });
    });

    group('cross-system weight conversion', () {
      test('10oz pantry covers 200g recipe', () {
        // 10 * 28.3495 = 283.5g > 200
        expect(hasEnough(10, 'oz', 200, 'g'), isTrue);
      });
      test('5oz pantry does not cover 200g recipe', () {
        // 5 * 28.3495 = 141.75g < 200
        expect(hasEnough(5, 'oz', 200, 'g'), isFalse);
      });
      test('1lb pantry covers 400g recipe', () {
        // 1 * 453.592 > 400
        expect(hasEnough(1, 'lb', 400, 'g'), isTrue);
      });
    });

    group('cross-system volume conversion', () {
      test('1gal pantry covers 2L recipe', () {
        // 1 * 3785.41 ml > 2000 ml
        expect(hasEnough(1, 'gal', 2, 'L'), isTrue);
      });
      test('1fl oz does not cover 100ml', () {
        // 29.57ml < 100ml
        expect(hasEnough(1, 'fl oz', 100, 'ml'), isFalse);
      });
    });

    group('incompatible or unknown units fall back to raw compare', () {
      test('weight vs volume: raw compare', () {
        // Can't convert, fall back to quantity compare
        expect(hasEnough(500, 'g', 200, 'ml'), isTrue);
        expect(hasEnough(100, 'g', 200, 'ml'), isFalse);
      });
      test('unknown same unit: direct compare', () {
        expect(hasEnough(3, 'packs', 2, 'packs'), isTrue);
        expect(hasEnough(1, 'packs', 2, 'packs'), isFalse);
      });
      test('unknown different units: raw quantity compare', () {
        expect(hasEnough(5, 'cans', 3, 'bags'), isTrue);
        expect(hasEnough(2, 'cans', 3, 'bags'), isFalse);
      });
    });
  });
}
