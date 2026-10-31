import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/costco_client.dart';
import 'package:groceries_app/services/price/price_fetch_exception.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime.utc(2026, 10, 31, 12);

String _fixtureBody(String term) {
  final all =
      jsonDecode(
            File('test/fixtures/price/costco_search.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  return jsonEncode(all[term]);
}

void main() {
  test('builds the documented URL and sends JSON + browser headers', () async {
    late http.Request seen;
    final client = CostcoClient(
      client: MockClient((req) async {
        seen = req;
        return http.Response.bytes(
          utf8.encode(_fixtureBody('baked beans')),
          200,
        );
      }),
      clock: () => _now,
    );
    await client.search('baked beans');

    expect(seen.method, 'GET');
    expect(seen.url.host, 'www.costco.co.uk');
    expect(seen.url.path, '/rest/v2/uk/products/search');
    expect(
      seen.url.queryParameters['query'],
      'baked beans:relevance:cartGroup:8796093380189',
    );
    expect(seen.url.queryParameters['pageSize'], '24');
    expect(seen.url.queryParameters['fields'], 'FULL');
    expect(seen.url.queryParameters['lang'], 'en_GB');
    expect(seen.url.queryParameters['curr'], 'GBP');
    expect(seen.headers['Accept'], 'application/json');
    expect(seen.headers['User-Agent'], contains('Chrome/'));
    expect(seen.headers['User-Agent'], contains('Android'));
    // Spaces are %20 and colons escaped in the raw query.
    expect(seen.url.query, contains('baked%20beans%3Arelevance'));
  });

  test(
    'parses the fixture into Costco products stamped with the clock',
    () async {
      final client = CostcoClient(
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(_fixtureBody('baked beans')),
            200,
          ),
        ),
        clock: () => _now,
      );
      final out = await client.search('baked beans');
      expect(out, isNotEmpty);
      expect(out.every((p) => p.store == PriceStore.costco), isTrue);
      expect(out.every((p) => p.price > 0), isTrue);
      expect(out.first.fetchedAt, _now);
      expect(out.first.name, contains('Heinz Baked Beans'));
    },
  );

  test('non-200 throws PriceFetchException for Costco', () async {
    final client = CostcoClient(
      client: MockClient((_) async => http.Response('nope', 503)),
    );
    await expectLater(
      client.search('milk'),
      throwsA(
        isA<PriceFetchException>()
            .having((e) => e.store, 'store', PriceStore.costco)
            .having((e) => e.message, 'message', contains('503')),
      ),
    );
  });

  test('network error and bad JSON are wrapped too', () async {
    final failing = CostcoClient(
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    await expectLater(
      failing.search('milk'),
      throwsA(isA<PriceFetchException>()),
    );

    final garbage = CostcoClient(
      client: MockClient((_) async => http.Response('<html>', 200)),
    );
    await expectLater(
      garbage.search('milk'),
      throwsA(isA<PriceFetchException>()),
    );
  });

  test('a hung request times out as PriceFetchException', () async {
    final client = CostcoClient(
      timeout: const Duration(milliseconds: 20),
      client: MockClient(
        (_) => Future.delayed(
          const Duration(seconds: 5),
          () => http.Response('{}', 200),
        ),
      ),
    );
    await expectLater(
      client.search('milk'),
      throwsA(isA<PriceFetchException>()),
    );
  });
}
