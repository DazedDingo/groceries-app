import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gemini API key, stored locally per device in SharedPreferences.
/// Used by the bulk voice add feature to parse spoken transcripts into
/// structured grocery items.
final geminiKeyProvider =
    StateNotifierProvider<GeminiKeyNotifier, String>(
        (ref) => GeminiKeyNotifier());

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
