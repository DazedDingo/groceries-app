import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/pantry_service.dart';
import '../models/pantry_item.dart';
import 'household_provider.dart';

final pantryServiceProvider = Provider<PantryService>((ref) => PantryService());

final pantryProvider = StreamProvider<List<PantryItem>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref.watch(pantryServiceProvider).pantryStream(householdId);
});

final pantrySelectedCategoryProvider = StateProvider<String?>((ref) => null);

final filteredPantryProvider = Provider<List<PantryItem>>((ref) {
  final pantry = ref.watch(pantryProvider).value ?? [];
  final category = ref.watch(pantrySelectedCategoryProvider);
  var items = pantry.toList();
  if (category != null) {
    items = items.where((p) => p.categoryId == category).toList();
  }
  return items;
});
