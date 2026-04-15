import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bulk_voice_parser.dart';

/// Gemini API key, stored locally per device in SharedPreferences.
/// Used by the bulk voice add feature to parse spoken transcripts into
/// structured grocery items.
final geminiKeyProvider =
    StateNotifierProvider<GeminiKeyNotifier, String>(
        (ref) => GeminiKeyNotifier());

/// Function that parses a transcript into structured items.
/// Overridden in tests to swap in canned responses without hitting the network.
typedef BulkVoiceParseFn = Future<List<ParsedVoiceItem>> Function(String transcript);

final bulkVoiceParseFnProvider = Provider<BulkVoiceParseFn>((ref) {
  return (String transcript) async {
    final key = ref.read(geminiKeyProvider);
    if (key.isEmpty) {
      throw StateError('No Gemini API key set');
    }
    final parser = BulkVoiceParser(apiKey: key);
    try {
      return await parser.parse(transcript);
    } finally {
      parser.dispose();
    }
  };
});

class GeminiKeyNotifier extends StateNotifier<String> {
  static const _prefsKey = 'geminiApiKey';
  GeminiKeyNotifier() : super('') {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_prefsKey) ?? '';
  }

  Future<void> set(String value) async {
    state = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (state.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, state);
    }
  }
}
