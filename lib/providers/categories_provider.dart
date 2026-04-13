import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/categories_service.dart';
import '../models/category.dart';
import 'household_provider.dart';

final categoriesServiceProvider = Provider<CategoriesService>((ref) => CategoriesService());

final categoriesProvider = StreamProvider<List<GroceryCategory>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref.watch(categoriesServiceProvider).categoriesStream(householdId);
});
