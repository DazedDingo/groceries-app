import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/asda_client.dart';
import 'package:groceries_app/services/price/asda_parser.dart';

import 'price_test_support.dart';

Map<String, dynamic> _entry(
  String term, {
  String url = 'https://abc-dsn.algolia.net/1/indexes/*/queries?x=1',
  int status = 200,
}) => {'url': url, 'status': status, 'body': jsonEncode(asdaFixture[term])};

void main() {
  group('findAsdaAlgoliaResponse', () {
    test('finds the ASDA_PRODUCTS response and it parses', () {
      final found = findAsdaAlgoliaResponse([_entry('milk')]);
      expect(found, isNotNull);
      final products = parseAsdaAlgolia(found!, fetchedAt: fixtureFetched);
      expect(products, isNotEmpty);
      expect(products.first.store, PriceStore.asda);
    });

    test('ignores garbage, non-Algolia, wrong-index and failed entries', () {
      final captured = <dynamic>[
        'a string',
        42,
        null,
        {'url': 'https://www.asda.com/api/x', 'body': '{"results":[]}'},
        {'url': 'https://x/1/indexes/*/queries', 'body': 'not json'},
        {'url': 'https://x/1/indexes/*/queries', 'body': '[1,2]'},
        {
          'url': 'https://x/1/indexes/*/queries',
          'body': jsonEncode({
            'results': [
              {'index': 'ASDA_SUGGESTIONS', 'hits': []},
            ],
          }),
        },
        _entry('milk', status: 500),
        {'url': 42, 'body': '{}'},
      ];
      expect(findAsdaAlgoliaResponse(captured), isNull);
      expect(findAsdaAlgoliaResponse(const []), isNull);
    });

    test('picks the newest matching entry among several', () {
      final found = findAsdaAlgoliaResponse([
        _entry('milk'),
        {'url': 'https://x/other', 'body': '{}'},
        _entry('cereal'),
        {'url': 'https://x/1/indexes/*/queries', 'body': 'junk'},
      ]);
      expect(found, isNotNull);
      final names = parseAsdaAlgolia(
        found!,
        fetchedAt: fixtureFetched,
      ).map((p) => p.name.toLowerCase());
      final cereal = parseAsdaAlgolia(
        asdaFixture['cereal'] as Map<String, dynamic>,
        fetchedAt: fixtureFetched,
      ).map((p) => p.name.toLowerCase());
      expect(names.toList(), cereal.toList());
    });

    test(
      'a zero-hit ASDA_PRODUCTS response is returned and parses to empty',
      () {
        final body = jsonEncode({
          'results': [
            {
              'index': 'ASDA_PRODUCTS',
              'hits': <dynamic>[],
              'nbHits': 0,
              'query': 'zzzzqx',
            },
          ],
        });
        final found = findAsdaAlgoliaResponse([
          {
            'url': 'https://x.algolia.net/1/indexes/*/queries',
            'status': 200,
            'body': body,
          },
        ]);
        expect(found, isNotNull);
        expect(parseAsdaAlgolia(found!, fetchedAt: fixtureFetched), isEmpty);
      },
    );

    test('accepts an already-decoded body and a missing status', () {
      final found = findAsdaAlgoliaResponse([
        {'url': 'https://x/1/indexes/*/queries', 'body': asdaFixture['milk']},
      ]);
      expect(found, isNotNull);
    });
  });

  group('pollForAsdaResponse', () {
    // Fake time: sleeping advances the clock.
    late DateTime t;
    setUp(() => t = DateTime.utc(2026, 1, 1));
    DateTime now() => t;
    Future<void> sleep(Duration d) async => t = t.add(d);

    test('returns as soon as a response appears', () async {
      var polls = 0;
      final r = await pollForAsdaResponse(
        readCaptured: () async => ++polls >= 3 ? [_entry('milk')] : const [],
        readTitle: () async => 'Asda',
        now: now,
        sleep: sleep,
      );
      expect(r, isNotNull);
      expect(polls, 3);
    });

    test('times out after ~20s when nothing arrives', () async {
      final r = await pollForAsdaResponse(
        readCaptured: () async => const [],
        readTitle: () async => 'Asda Groceries',
        now: now,
        sleep: sleep,
      );
      expect(r, isNull);
      expect(
        t.difference(DateTime.utc(2026, 1, 1)).inSeconds,
        inInclusiveRange(20, 21),
      );
    });

    test('a Cloudflare title extends the wait to 30s', () async {
      final r = await pollForAsdaResponse(
        readCaptured: () async => const [],
        readTitle: () async => 'Just a moment...',
        now: now,
        sleep: sleep,
      );
      expect(r, isNull);
      expect(
        t.difference(DateTime.utc(2026, 1, 1)).inSeconds,
        inInclusiveRange(30, 31),
      );
    });

    test(
      'a response after the 20s mark is still found during a challenge',
      () async {
        final r = await pollForAsdaResponse(
          readCaptured: () async =>
              t.difference(DateTime.utc(2026, 1, 1)).inSeconds >= 25
              ? [_entry('milk')]
              : const [],
          readTitle: () async => 'Just a moment...',
          now: now,
          sleep: sleep,
        );
        expect(r, isNotNull);
      },
    );
  });
}
