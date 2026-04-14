import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/recipes_service.dart';
import '../models/recipe.dart';
import 'household_provider.dart';

final recipesServiceProvider = Provider<RecipesService>((ref) => RecipesService());

final recipesProvider = StreamProvider<List<Recipe>>((ref) async* {
  // Await the first resolved household id so a transient AsyncLoading on
  // auth-token refresh doesn't collapse the stream to empty.
  final householdId = await ref.watch(householdIdProvider.future);
  if (householdId == null) {
    yield const [];
    return;
  }
  yield* ref.watch(recipesServiceProvider).recipesStream(householdId);
});
