import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/fuzzy_match.dart';

void main() {
  group('levenshtein', () {
    test('identical strings return 0', () {
      expect(levenshtein('milk', 'milk'), 0);
    });

    test('empty vs non-empty returns length', () {
      expect(levenshtein('', 'abc'), 3);
      expect(levenshtein('abc', ''), 3);
    });

    test('single insertion', () {
      expect(levenshtein('egg', 'eggs'), 1);
    });

    test('single deletion', () {
      expect(levenshtein('eggs', 'egg'), 1);
    });

    test('single substitution', () {
      expect(levenshtein('cat', 'bat'), 1);
    });

    test('typical typo', () {
      expect(levenshtein('cheese', 'cheeze'), 1);
    });

    test('completely different strings', () {
      // distance should equal longer length when nothing overlaps
      expect(levenshtein('abc', 'xyz'), 3);
    });
  });

  group('isFuzzyMatch', () {
    test('exact match (case-insensitive) returns true', () {
      expect(isFuzzyMatch('Milk', 'milk'), isTrue);
    });

    test('substring match returns true', () {
      expect(isFuzzyMatch('egg', 'eggs'), isTrue);
      expect(isFuzzyMatch('eggs', 'egg'), isTrue);
    });

    test('typo within edit-distance threshold', () {
      expect(isFuzzyMatch('cheeze', 'cheese'), isTrue); // distance 1
      expect(isFuzzyMatch('buttor', 'butter'), isTrue); // distance 1
    });

    test('completely different short words return false', () {
      expect(isFuzzyMatch('egg', 'fig'), isFalse);
      expect(isFuzzyMatch('cat', 'dog'), isFalse);
    });

    test('strings < 4 chars that are not substrings return false', () {
      // "egg" vs "ogg" — distance 1 but both < 4 chars
      expect(isFuzzyMatch('egg', 'ogg'), isFalse);
    });

    test('empty strings return false', () {
      expect(isFuzzyMatch('', 'milk'), isFalse);
      expect(isFuzzyMatch('milk', ''), isFalse);
    });

    test('long words with distance above threshold return false', () {
      // "chicken" vs "kitchen" — distance 2, maxLen 7, threshold floor(7/4)=1 → false
      expect(isFuzzyMatch('chicken', 'kitchen'), isFalse);
    });

    test('longer strings tolerate edit distance 2', () {
      // "chocolate" (9) vs "chocolaet" — distance 2, threshold floor(9/4)=2 → true
      expect(isFuzzyMatch('chocolate', 'chocolaet'), isTrue);
    });
  });
}
