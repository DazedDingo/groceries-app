import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../shared/help_button.dart';
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
import '../shared/empty_state.dart';
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

    final expired = pantry.where((p) => p.isExpired).toList();
    final expiringSoon = pantry.where((p) => p.isExpiringSoon).toList();
    final stale = pantry.where((p) => p.isStale && !p.isBelowOptimal).toList();
    final needsRestock = pantry
        .where((p) =>
            p.isBelowOptimal && !p.isExpired && !p.isExpiringSoon && !p.isStale)
        .toList();
    final stocked = pantry
        .where((p) =>
            !p.isBelowOptimal &&
            !p.isExpired &&
            !p.isExpiringSoon &&
            !p.isStale)
        .toList();

    String catSortKey(PantryItem p) {
      try {
        return categories.firstWhere((c) => c.id == p.categoryId).name;
      } catch (_) {
        return 'zzz';
      }
    }
    expired.sort((a, b) => catSortKey(a).compareTo(catSortKey(b)));
    expiringSoon.sort((a, b) => catSortKey(a).compareTo(catSortKey(b)));
    stale.sort((a, b) => catSortKey(a).compareTo(catSortKey(b)));
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
      onTap: () => context.push('/pantry/${item.id}'),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pantry'),
        actions: [
          const HelpButton(
            screenTitle: 'Pantry',
            sections: [
              HelpSection(icon: Icons.touch_app, title: 'Opening an item',
                  body: 'Tap any item to open its detail screen, where you can set optimal quantity, shelf life, location, and high-priority toggle.'),
              HelpSection(icon: Icons.exposure, title: 'Adjusting stock',
                  body: 'Use the + and - buttons on each tile to change the current quantity without opening the detail screen.'),
              HelpSection(icon: Icons.add_shopping_cart, title: 'Adding to list',
                  body: 'When an item is below optimal, tap "Add to list" on the tile to request a restock on your shopping list.'),
              HelpSection(icon: Icons.star, title: 'High priority',
                  body: 'Mark an item high priority in its detail screen. It will float to the top of your shopping list and trigger restock nudges immediately when low.'),
              HelpSection(icon: Icons.warning_amber, title: 'Stock indicators',
                  body: 'Warning icon = below optimal quantity. Expiry banners appear at the top when items are expired or expiring soon.'),
              HelpSection(icon: Icons.place, title: 'Locations',
                  body: 'Set Fridge, Freezer, Pantry, Counter, or Other on each item so you know exactly where to look at home.'),
            ],
          ),
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
                ? const EmptyState(
                    icon: Icons.kitchen,
                    title: 'Pantry is empty',
                    subtitle: 'Track what you have at home so you never overbuy',
                  )
                : ListView(
                    children: [
                      if (expired.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${expired.length} expired item${expired.length == 1 ? '' : 's'} — consider removing',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Clear expired items?'),
                                      content: Text('This will remove ${expired.length} expired item${expired.length == 1 ? '' : 's'} from your pantry.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    pantryService.clearExpired(
                                      householdId,
                                      expired.map((e) => e.id).toList(),
                                    );
                                  }
                                },
                                child: Text('Clear all',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text('Expired',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  )),
                        ),
                        ...expired.map(buildTile),
                        const Divider(),
                      ],
                      if (expiringSoon.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text('Expiring soon',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Colors.orange,
                                  )),
                        ),
                        ...expiringSoon.map(buildTile),
                        const Divider(),
                      ],
                      if (stale.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text('Sitting unused',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Colors.brown,
                                  )),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Text(
                            'In your pantry 60+ days — use it or bin it.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        ...stale.map(buildTile),
                        const Divider(),
                      ],
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
    PantryLocation? selectedLocation;

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
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Location'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<PantryLocation?>(
                  value: selectedLocation,
                  isExpanded: true,
                  hint: const Text('Not set'),
                  items: [
                    const DropdownMenuItem<PantryLocation?>(
                        value: null, child: Text('Not set')),
                    ...PantryLocation.values.map((loc) => DropdownMenuItem(
                          value: loc,
                          child: Text(loc.label),
                        )),
                  ],
                  onChanged: (loc) => setState(() => selectedLocation = loc),
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
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                ref.read(pantryServiceProvider).addItem(
                  householdId: householdId,
                  name: name,
                  categoryId: selectedCategory?.id ?? 'uncategorised',
                  preferredStores: [],
                  optimalQuantity: int.tryParse(optCtrl.text) ?? 1,
                  currentQuantity: 0,
                  location: selectedLocation,
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
