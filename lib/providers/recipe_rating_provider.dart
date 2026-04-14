import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/recipe_rating_service.dart';
import 'household_provider.dart';

final recipeRatingServiceProvider =
    Provider<RecipeRatingService>((ref) => RecipeRatingService());

/// Stream of ratings (uid → 1-5) for a single recipe in the current household.
final recipeRatingsProvider =
    StreamProvider.family<Map<String, int>, String>((ref, recipeId) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref
      .watch(recipeRatingServiceProvider)
      .ratingsStream(householdId, recipeId);
});
