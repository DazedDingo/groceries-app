import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/category.dart';
import '../../../models/store.dart';
import '../../../providers/items_provider.dart';

class FilterBar extends ConsumerWidget {
  final List<GroceryCategory> categories;
  final List<Store> stores;
  const FilterBar({super.key, required this.categories, required this.stores});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCat = ref.watch(selectedCategoryFilterProvider);
    final selectedStore = ref.watch(selectedStoreFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ...categories.map((c) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
              label: Text(c.name),
              selected: selectedCat == c.id,
              selectedColor: c.color.withValues(alpha: 0.3),
              onSelected: (_) => ref.read(selectedCategoryFilterProvider.notifier).state =
                  selectedCat == c.id ? null : c.id,
            ),
          )),
          const VerticalDivider(width: 16),
          ...stores.map((s) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(s.name),
              selected: selectedStore == s.id,
              onSelected: (_) => ref.read(selectedStoreFilterProvider.notifier).state =
                  selectedStore == s.id ? null : s.id,
            ),
          )),
        ],
      ),
    );
  }
}
