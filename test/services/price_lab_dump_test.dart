import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/price_lab_dump.dart';

void main() {
  test('dump has the documented top-level and page keys', () {
    final dump = buildPriceLabDump(
      generatedAt: DateTime.utc(2026, 1, 2, 3, 4),
      appVersion: '0.1.54+54',
      userAgent: 'UA',
      pages: [
        PriceLabPage(
          term: 'milk',
          url: 'https://www.asda.com/groceries/search/milk',
          title: 'Milk',
          loggedInHint: true,
          extracted: [
            {'name': 'x'}
          ],
          network: [
            {'url': 'u', 'status': 200, 'body': '{}'}
          ],
          html: '<html></html>',
          globals: ['__NEXT_DATA__'],
        ),
      ],
    );
    expect(dump.keys,
        containsAll(['generatedAt', 'appVersion', 'userAgent', 'pages']));
    expect(dump['generatedAt'], '2026-01-02T03:04:00.000Z');
    final page = (dump['pages'] as List).single as Map<String, dynamic>;
    expect(
        page.keys,
        containsAll([
          'term',
          'url',
          'title',
          'loggedInHint',
          'extracted',
          'network',
          'html',
          'globals'
        ]));
    expect(page['globals'], ['__NEXT_DATA__']);
    // Must be JSON-encodable.
    expect(() => jsonEncode(dump), returnsNormally);
  });

  test('html is truncated to 400k chars', () {
    final page = PriceLabPage(url: 'u', html: 'a' * 500000);
    expect((page.toJson()['html'] as String).length, priceLabMaxHtmlChars);
    expect(priceLabMaxHtmlChars, 400000);
    final small = PriceLabPage(url: 'u', html: 'abc');
    expect(small.toJson()['html'], 'abc');
  });

  test('fromSnapshot parses the JS snapshot JSON', () {
    final p = PriceLabPage.fromSnapshot(
      url: 'u',
      term: 't',
      snapshotJson: jsonEncode({
        'title': 'T',
        'loggedInHint': false,
        'html': '<b>',
        'globals': ['__x', 3],
        'extracted': [
          {'name': 'n'}
        ],
        'network': [],
      }),
    );
    expect(p.title, 'T');
    expect(p.loggedInHint, false);
    expect(p.globals, ['__x', '3']);
    expect(p.extracted.length, 1);
    expect(p.term, 't');
  });

  test('fromSnapshot tolerates null, garbage and wrong types', () {
    for (final s in [null, '', 'not json', '[1,2]', '{"loggedInHint":"yes"}']) {
      final p = PriceLabPage.fromSnapshot(url: 'u', snapshotJson: s);
      expect(p.url, 'u');
      expect(p.loggedInHint, isNull);
      expect(p.extracted, isEmpty);
      expect(p.html, '');
    }
  });

  test('filename uses local yyyyMMdd_HHmm zero-padded', () {
    expect(priceLabDumpFilename(DateTime(2026, 3, 4, 5, 6)),
        'asda_dump_20260304_0506.json');
  });
}
