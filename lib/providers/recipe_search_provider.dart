import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/recipe_search_service.dart';

final recipeSearchServiceProvider =
    Provider<RecipeSearchService>((ref) => RecipeSearchService());

/// Spoonacular API key, stored locally per device in SharedPreferences.
final spoonacularKeyProvider =
    StateNotifierProvider<SpoonacularKeyNotifier, String>(
        (ref) => SpoonacularKeyNotifier());

class SpoonacularKeyNotifier extends StateNotifier<String> {
  static const _prefsKey = 'spoonacularApiKey';
  SpoonacularKeyNotifier() : super('') {
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
