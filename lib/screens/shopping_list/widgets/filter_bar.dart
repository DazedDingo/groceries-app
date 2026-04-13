import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/category.dart';
import '../../../providers/items_provider.dart';

class FilterBar extends ConsumerWidget {
  final List<GroceryCategory> categories;
  const FilterBar({super.key, required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCat = ref.watch(selectedCategoryFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: categories.map((c) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
            label: Text(c.name),
            selected: selectedCat == c.id,
            selectedColor: c.color.withValues(alpha: 0.3),
            onSelected: (_) => ref.read(selectedCategoryFilterProvider.notifier).state =
                selectedCat == c.id ? null : c.id,
          ),
        )).toList(),
      ),
    );
  }
}
