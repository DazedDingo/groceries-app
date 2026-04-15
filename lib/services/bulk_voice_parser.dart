import 'dart:convert';
import 'package:http/http.dart' as http;

/// One parsed grocery line item from a spoken transcript.
class ParsedVoiceItem {
  final String name;
  final int quantity;
  final String? unit;
  ParsedVoiceItem({required this.name, required this.quantity, this.unit});

  Map<String, dynamic> toMap() => {
        'name': name,
        'quantity': quantity,
        if (unit != null) 'unit': unit,
      };

  factory ParsedVoiceItem.fromMap(Map<String, dynamic> m) => ParsedVoiceItem(
        name: (m['name'] ?? '').toString().trim(),
        quantity: (m['quantity'] is num)
            ? (m['quantity'] as num).toInt()
            : int.tryParse(m['quantity']?.toString() ?? '') ?? 1,
        unit: (m['unit'] as String?)?.trim().isEmpty == true
            ? null
            : (m['unit'] as String?)?.trim(),
      );
}

/// Parses freeform spoken transcripts into a structured shopping list using
/// Gemini Flash. The transcript may include corrections ("oh wait, actually 2"),
/// duplicates that should be combined ("milk... and another milk"), and
/// natural-language separators ("next", "and", "also").
class BulkVoiceParser {
  final String apiKey;
  final http.Client _client;

  BulkVoiceParser({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.0-flash:generateContent';

  static const _systemInstruction = '''
You convert spoken pantry/grocery cataloguing transcripts into a clean JSON list.

Rules:
- Output ONLY a JSON object: {"items": [{"name": "...", "quantity": 1, "unit": "..."}]}
- "name" is the item name (singular preferred, lowercase, no leading articles).
- "quantity" is an integer count (default 1).
- "unit" is optional (e.g. "g", "kg", "lb", "oz"). Omit if just a count.
- Honour corrections: "actually 3 milk" overrides earlier "1 milk".
- Combine duplicates: if the same item is mentioned twice with no explicit
  correction, sum the quantities ("1 milk... and one more milk" -> 2 milk).
- Ignore filler words: "next", "and", "also", "um", "okay", "let's see".
- If the transcript is empty or contains no items, return {"items": []}.
- Never include explanations, code fences, or anything outside the JSON object.
''';

  Future<List<ParsedVoiceItem>> parse(String transcript) async {
    final clean = transcript.trim();
    if (clean.isEmpty) return [];

    final uri = Uri.parse('$_endpoint?key=$apiKey');
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [{'text': _systemInstruction}]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [{'text': 'Transcript:\n$clean'}]
        }
      ],
      'generationConfig': {
        'temperature': 0.0,
        'responseMimeType': 'application/json',
      },
    });

    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('Gemini error ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return [];
    final parts = (candidates.first as Map)['content']?['parts'] as List?;
    if (parts == null || parts.isEmpty) return [];
    final text = (parts.first as Map)['text'] as String?;
    if (text == null || text.trim().isEmpty) return [];

    return parseJsonResponse(text);
  }

  /// Exposed for testing — extracts items from the model's JSON response,
  /// tolerating stray whitespace or accidental code fences.
  static List<ParsedVoiceItem> parseJsonResponse(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?'), '').trim();
      if (t.endsWith('```')) t = t.substring(0, t.length - 3).trim();
    }
    final obj = jsonDecode(t);
    if (obj is! Map) return [];
    final items = obj['items'];
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((m) => ParsedVoiceItem.fromMap(m.cast<String, dynamic>()))
        .where((i) => i.name.isNotEmpty && i.quantity > 0)
        .toList();
  }

  void dispose() => _client.close();
}
