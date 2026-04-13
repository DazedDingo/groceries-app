import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/text_item_parser.dart';

void main() {
  group('parseTextLine', () {
    test('plain name with no quantity', () {
      final result = parseTextLine('chicken');
      expect(result.name, 'chicken');
      expect(result.quantity, 1);
      expect(result.unit, isNull);
    });

    test('quantity and name', () {
      final result = parseTextLine('3 apples');
      expect(result.name, 'apples');
      expect(result.quantity, 3);
      expect(result.unit, isNull);
    });

    test('quantity, unit, and name', () {
      final result = parseTextLine('2 kg chicken');
      expect(result.name, 'chicken');
      expect(result.quantity, 2);
      expect(result.unit, 'kg');
    });

    test('unit alias normalisation (pounds → lb)', () {
      final result = parseTextLine('5 pounds beef');
      expect(result.name, 'beef');
      expect(result.quantity, 5);
      expect(result.unit, 'lb');
    });

    test('unit alias normalisation (grams → g)', () {
      final result = parseTextLine('200 grams flour');
      expect(result.name, 'flour');
      expect(result.quantity, 200);
      expect(result.unit, 'g');
    });

    test('unit alias normalisation (litres → L)', () {
      final result = parseTextLine('2 litres milk');
      expect(result.name, 'milk');
      expect(result.quantity, 2);
      expect(result.unit, 'L');
    });

    test('unit alias normalisation (packs/packets)', () {
      final r1 = parseTextLine('3 packs pasta');
      expect(r1.unit, 'packs');
      final r2 = parseTextLine('3 packets pasta');
      expect(r2.unit, 'packs');
    });

    test('"of" connector is stripped', () {
      final result = parseTextLine('2 bags of rice');
      expect(result.name, 'rice');
      expect(result.quantity, 2);
      expect(result.unit, 'bags');
    });

    test('handles cans', () {
      final result = parseTextLine('4 cans tomatoes');
      expect(result.name, 'tomatoes');
      expect(result.quantity, 4);
      expect(result.unit, 'cans');
    });

    test('unit-only input treated as name', () {
      // "2 kg" with nothing after — "kg" becomes part of the name
      final result = parseTextLine('2 kg');
      expect(result.name, 'kg');
      expect(result.quantity, 2);
    });

    test('empty input', () {
      final result = parseTextLine('');
      expect(result.name, '');
      expect(result.quantity, 1);
    });

    test('whitespace-only input', () {
      final result = parseTextLine('   ');
      expect(result.name, '');
      expect(result.quantity, 1);
    });

    test('trims whitespace', () {
      final result = parseTextLine('  3 eggs  ');
      expect(result.name, 'eggs');
      expect(result.quantity, 3);
    });

    test('dozen unit', () {
      final result = parseTextLine('1 dozen eggs');
      expect(result.name, 'eggs');
      expect(result.quantity, 1);
      expect(result.unit, 'dozen');
    });

    test('loaf/loaves', () {
      final result = parseTextLine('2 loaves bread');
      expect(result.name, 'bread');
      expect(result.unit, 'loaves');
    });

    test('bottles', () {
      final result = parseTextLine('6 bottles water');
      expect(result.name, 'water');
      expect(result.unit, 'bottles');
    });

    test('multi-word item name', () {
      final result = parseTextLine('2 kg chicken breast');
      expect(result.name, 'chicken breast');
      expect(result.quantity, 2);
      expect(result.unit, 'kg');
    });
  });

  group('parseTextLines', () {
    test('parses multiple lines', () {
      final results = parseTextLines('2 kg chicken\n3 apples\nmilk');
      expect(results, hasLength(3));
      expect(results[0].name, 'chicken');
      expect(results[1].name, 'apples');
      expect(results[2].name, 'milk');
    });

    test('skips blank lines', () {
      final results = parseTextLines('eggs\n\n\nmilk\n');
      expect(results, hasLength(2));
    });

    test('empty input returns empty list', () {
      expect(parseTextLines(''), isEmpty);
    });
  });
}
