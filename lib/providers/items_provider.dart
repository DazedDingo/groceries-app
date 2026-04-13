import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/items_service.dart';
import '../models/item.dart';
import 'household_provider.dart';

final itemsServiceProvider = Provider<ItemsService>((ref) => ItemsService());

final selectedCategoryFilterProvider = StateProvider<String?>((ref) => null);

final itemsProvider = StreamProvider<List<ShoppingItem>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref.watch(itemsServiceProvider).itemsStream(householdId);
});

final filteredItemsProvider = Provider<List<ShoppingItem>>((ref) {
  final items = ref.watch(itemsProvider).value ?? [];
  final category = ref.watch(selectedCategoryFilterProvider);
  return items.where((item) {
    if (category != null && item.categoryId != category) return false;
    return true;
  }).toList();
});
