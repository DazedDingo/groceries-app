import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/bulk_voice_parser.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client _mockClientReturning(String modelText, {int status = 200}) {
  return MockClient((req) async {
    expect(req.url.host, 'generativelanguage.googleapis.com');
    expect(req.url.queryParameters['key'], isNotEmpty);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['contents'], isA<List>());
    return http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': modelText}
              ]
            }
          }
        ]
      }),
      status,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  group('BulkVoiceParser.parseJsonResponse', () {
    test('parses a clean JSON object', () {
      final items = BulkVoiceParser.parseJsonResponse(
        '{"items":[{"name":"milk","quantity":2},{"name":"bread","quantity":1}]}',
      );
      expect(items.length, 2);
      expect(items[0].name, 'milk');
      expect(items[0].quantity, 2);
      expect(items[0].unit, isNull);
      expect(items[1].name, 'bread');
    });

    test('handles fenced code blocks', () {
      final items = BulkVoiceParser.parseJsonResponse(
        '```json\n{"items":[{"name":"eggs","quantity":12}]}\n```',
      );
      expect(items.length, 1);
      expect(items[0].name, 'eggs');
      expect(items[0].quantity, 12);
    });

    test('preserves units when present', () {
      final items = BulkVoiceParser.parseJsonResponse(
        '{"items":[{"name":"flour","quantity":2,"unit":"kg"}]}',
      );
      expect(items.single.unit, 'kg');
    });

    test('drops items with empty names or zero quantity', () {
      final items = BulkVoiceParser.parseJsonResponse(
        '{"items":[{"name":"","quantity":1},{"name":"olive oil","quantity":0},{"name":"rice","quantity":3}]}',
      );
      expect(items.length, 1);
      expect(items.single.name, 'rice');
    });

    test('returns empty list for empty items', () {
      expect(BulkVoiceParser.parseJsonResponse('{"items":[]}'), isEmpty);
    });

    test('coerces string quantity to int', () {
      final items = BulkVoiceParser.parseJsonResponse(
        '{"items":[{"name":"milk","quantity":"3"}]}',
      );
      expect(items.single.quantity, 3);
    });
  });

  group('BulkVoiceParser.parse (HTTP)', () {
    test('returns empty list for blank transcript without calling API', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('', 200);
      });
      final parser = BulkVoiceParser(apiKey: 'test', client: client);
      final items = await parser.parse('   ');
      expect(items, isEmpty);
      expect(calls, 0);
    });

    test('round-trips a typical model response', () async {
      final client = _mockClientReturning(
        '{"items":[{"name":"coriander","quantity":1},{"name":"cinnamon sticks","quantity":2}]}',
      );
      final parser = BulkVoiceParser(apiKey: 'test', client: client);
      final items = await parser.parse('1 coriander, next, 2 cinnamon sticks');
      expect(items.length, 2);
      expect(items[0].name, 'coriander');
      expect(items[1].name, 'cinnamon sticks');
      expect(items[1].quantity, 2);
    });

    test('throws on non-200 response', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final parser = BulkVoiceParser(apiKey: 'test', client: client);
      expect(parser.parse('milk'), throwsException);
    });

    test('returns empty list when candidates is empty', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'candidates': []}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final parser = BulkVoiceParser(apiKey: 'test', client: client);
      final items = await parser.parse('something');
      expect(items, isEmpty);
    });
  });
}
