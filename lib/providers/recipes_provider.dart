import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/recipes_service.dart';
import '../models/recipe.dart';
import 'household_provider.dart';

final recipesServiceProvider = Provider<RecipesService>((ref) => RecipesService());

final recipesProvider = StreamProvider<List<Recipe>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref.watch(recipesServiceProvider).recipesStream(householdId);
});
