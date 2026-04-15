import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/recipe_search_service.dart';
import 'household_key_notifier.dart';

final recipeSearchServiceProvider =
    Provider<RecipeSearchService>((ref) => RecipeSearchService());

/// Spoonacular API key, stored at households/{id}/config/apiKeys.spoonacularKey
/// so it is shared across all members of the household and survives uninstalls.
final spoonacularKeyProvider =
    StateNotifierProvider<HouseholdKeyNotifier, String>(
  (ref) => HouseholdKeyNotifier(
    ref,
    firestoreField: 'spoonacularKey',
    legacyPrefsKey: 'spoonacularApiKey',
  ),
);
