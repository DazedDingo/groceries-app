import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/categories_provider.dart';
import '../../models/item.dart';
import '../../models/category.dart';
import '../../models/pantry_item.dart';
import '../../services/category_guesser.dart';
import '../../services/text_item_parser.dart';
import '../shared/bulk_add_dialog.dart';
import 'widgets/pantry_item_tile.dart';

class PantryScreen extends ConsumerWidget {
  const PantryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pantry = ref.watch(filteredPantryProvider);
    final selectedCat = ref.watch(pantrySelectedCategoryProvider);
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final categories = ref.watch(categoriesProvider).value ?? [];
    final pantryService = ref.watch(pantryServiceProvider);
    final itemsService = ref.watch(itemsServiceProvider);
    final user = ref.watch(authStateProvider).value;

    final needsRestock = pantry.where((p) => p.isBelowOptimal).toList();
    final stocked = pantry.where((p) => !p.isBelowOptimal).toList();

    String catSortKey(PantryItem p) {
      try {
        return categories.firstWhere((c) => c.id == p.categoryId).name;
      } catch (_) {
        return 'zzz';
      }
    }
    needsRestock.sort((a, b) => catSortKey(a).compareTo(catSortKey(b)));
    stocked.sort((a, b) => catSortKey(a).compareTo(catSortKey(b)));

    String categoryName(String catId) {
      try {
        return categories.firstWhere((c) => c.id == catId).name;
      } catch (_) {
        return 'Uncategorised';
      }
    }

    Widget buildTile(item) => PantryItemTile(
      key: Key(item.id),
      item: item,
      categoryName: categoryName(item.categoryId),
      onDecrement: () => pantryService.decrementQuantity(
          householdId: householdId, itemId: item.id, current: item.currentQuantity),
      onIncrement: () => pantryService.incrementQuantity(
          householdId: householdId, itemId: item.id, current: item.currentQuantity),
      onAddToList: () => itemsService.addItem(
        householdId: householdId,
        name: item.name,
        categoryId: item.categoryId,
        preferredStores: item.preferredStores,
        pantryItemId: item.id,
        quantity: (item.optimalQuantity - item.currentQuantity).clamp(1, 999),
        addedBy: AddedBy(
          uid: user?.uid,
          displayName: user?.displayName ?? 'Unknown',
          source: ItemSource.app,
        ),
      ),
      onTap: () => context.go('/pantry/${item.id}'),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pantry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            onPressed: () => _showBulkAddDialog(context, ref, householdId, categories),
            tooltip: 'Bulk add',
          ),
        ],
      ),
      body: Column(
        children: [
          if (categories.isNotEmpty)
            SingleChildScrollView(
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
                    onSelected: (_) => ref.read(pantrySelectedCategoryProvider.notifier).state =
                        selectedCat == c.id ? null : c.id,
                  ),
                )).toList(),
              ),
            ),
          Expanded(
            child: pantry.isEmpty
                ? const Center(child: Text('No pantry items yet. Tap + to add one.'))
                : ListView(
                    children: [
                      if (needsRestock.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text('Needs restocking',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  )),
                        ),
                        ...needsRestock.map(buildTile),
                        const Divider(),
                      ],
                      if (stocked.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text('Stocked',
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                        ...stocked.map(buildTile),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref, householdId, categories),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showBulkAddDialog(BuildContext context, WidgetRef ref,
      String householdId, List<GroceryCategory> categories) async {
    final items = await showDialog<List<ParsedTextItem>>(
      context: context,
      builder: (_) => const BulkAddDialog(
        title: 'Bulk add to pantry',
        hint: 'One item per line, e.g.:\nchicken\npasta\nmilk\neggs',
      ),
    );
    if (items == null || items.isEmpty || !context.mounted) return;

    try {
      for (final item in items) {
        final cat = guessCategory(item.name, categories);
        await ref.read(pantryServiceProvider).addItem(
          householdId: householdId,
          name: item.name,
          categoryId: cat?.id ?? 'uncategorised',
          preferredStores: [],
          optimalQuantity: item.quantity,
          currentQuantity: 0,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${items.length} pantry items')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add items: $e')),
        );
      }
    }
  }

  void _showAddDialog(BuildContext context, WidgetRef ref, String householdId,
      List<GroceryCategory> categories) {
    final nameCtrl = TextEditingController();
    final optCtrl = TextEditingController(text: '1');
    GroceryCategory? selectedCategory;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add pantry item'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Item name'),
              onChanged: (val) {
                final guess = guessCategory(val, categories);
                if (guess != null && guess != selectedCategory) {
                  setState(() => selectedCategory = guess);
                }
              },
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Category'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<GroceryCategory>(
                  value: selectedCategory,
                  isExpanded: true,
                  hint: const Text('Uncategorised'),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                      .toList(),
                  onChanged: (c) => setState(() => selectedCategory = c),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: optCtrl,
              decoration: const InputDecoration(labelText: 'Optimal quantity'),
              keyboardType: TextInputType.number,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                ref.read(pantryServiceProvider).addItem(
                  householdId: householdId,
                  name: nameCtrl.text.trim(),
                  categoryId: selectedCategory?.id ?? 'uncategorised',
                  preferredStores: [],
                  optimalQuantity: int.tryParse(optCtrl.text) ?? 1,
                  currentQuantity: 0,
                );
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
