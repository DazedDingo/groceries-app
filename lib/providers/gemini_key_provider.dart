import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/bulk_voice_parser.dart';
import 'household_key_notifier.dart';

/// Gemini API key, stored at households/{id}/config/apiKeys.geminiKey so it
/// is shared across all members of the household and survives uninstalls.
final geminiKeyProvider =
    StateNotifierProvider<HouseholdKeyNotifier, String>(
  (ref) => HouseholdKeyNotifier(
    ref,
    firestoreField: 'geminiKey',
    legacyPrefsKey: 'geminiApiKey',
  ),
);

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
