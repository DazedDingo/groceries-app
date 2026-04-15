@Tags(['smoke'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/bulk_voice_parser.dart';

/// Real-API smoke tests for [BulkVoiceParser]. Only run when GEMINI_API_KEY is
/// set in the environment, so they don't burn quota in CI by default.
///
/// Run with:
///   GEMINI_API_KEY=xxx flutter test test/services/bulk_voice_parser_smoke_test.dart --tags smoke
void main() {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  final skip = apiKey == null || apiKey.isEmpty
      ? 'GEMINI_API_KEY not set'
      : null;

  group('BulkVoiceParser (live Gemini)', skip: skip, () {
    late BulkVoiceParser parser;
    setUp(() => parser = BulkVoiceParser(apiKey: apiKey!));
    tearDown(() => parser.dispose());

    test('extracts a simple list', () async {
      final items = await parser.parse(
        '1 coriander, next, 2 cinnamon sticks, next, 1 milk',
      );
      expect(items.length, 3);
      final names = items.map((i) => i.name.toLowerCase()).toList();
      expect(names, containsAll(['coriander', 'milk']));
      expect(
        names.any((n) => n.contains('cinnamon')),
        isTrue,
        reason: 'Expected cinnamon sticks in $names',
      );
      final cinnamon = items.firstWhere(
        (i) => i.name.toLowerCase().contains('cinnamon'),
      );
      expect(cinnamon.quantity, 2);
    });

    test('honours a verbal correction (oh wait, actually 3)', () async {
      final items = await parser.parse(
        '1 milk... oh wait, actually 3 milk',
      );
      expect(items.length, 1);
      expect(items.single.name.toLowerCase(), contains('milk'));
      expect(items.single.quantity, 3);
    });

    test('combines duplicates with no explicit correction', () async {
      final items = await parser.parse(
        '1 milk, next, 1 bread, next, one more milk',
      );
      // Expect 2 distinct items with milk merged to 2.
      expect(items.length, 2);
      final milk = items.firstWhere(
        (i) => i.name.toLowerCase().contains('milk'),
      );
      expect(milk.quantity, 2);
    });

    test('strips filler words and returns clean names', () async {
      final items = await parser.parse(
        'um, okay, let\'s see, two eggs, and, uh, one loaf of bread',
      );
      expect(items.length, 2);
      final names = items.map((i) => i.name.toLowerCase()).toList();
      expect(names.any((n) => n.contains('egg')), isTrue);
      expect(names.any((n) => n.contains('bread')), isTrue);
      // Names should not contain "um" / "okay" / "uh".
      for (final n in names) {
        expect(n, isNot(contains('um')));
        expect(n, isNot(contains('uh')));
        expect(n, isNot(contains('okay')));
      }
    });

    test('returns empty list for non-grocery rambling', () async {
      final items = await parser.parse(
        'so I was thinking about the weather today, it might rain later',
      );
      expect(items, isEmpty);
    });
  });
}
