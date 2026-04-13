import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../models/category.dart';
import '../../models/item.dart';
import '../../models/pantry_item.dart';
import 'widgets/item_tile.dart';
import 'widgets/filter_bar.dart';
import 'widgets/voice_fab.dart';
import 'widgets/add_item_dialog.dart';
import '../../services/unit_converter.dart';
import '../../services/category_guesser.dart';
import '../shared/bulk_add_dialog.dart';
import '../../services/text_item_parser.dart';

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final Set<String> _selectedIds = {};
  bool _selecting = false;

  void _enterSelecting(String id) {
    setState(() {
      _selecting = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selecting = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _cancelSelecting() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  Future<void> _showManualAddDialog(String householdId) async {
    final categories = ref.read(categoriesProvider).value ?? [];
    final result = await showDialog<AddItemResult>(
      context: context,
      builder: (ctx) => AddItemDialog(categories: categories),
    );
    if (result == null || !mounted) return;

    // Check for duplicate
    final allItems = ref.read(itemsProvider).value ?? [];
    final duplicate = allItems.any(
      (item) => item.name.toLowerCase() == result.name.toLowerCase(),
    );
    if (duplicate && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Item already on list'),
          content: Text('"${result.name}" is already on your shopping list. Add it again?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add anyway')),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    try {
      final user = ref.read(authStateProvider).valueOrNull;
      await ref.read(itemsServiceProvider).addItem(
        householdId: householdId,
        name: result.name,
        categoryId: result.category?.id ?? 'uncategorised',
        preferredStores: [],
        pantryItemId: null,
        quantity: result.quantity,
        unit: result.unit,
        addedBy: AddedBy(
          uid: user?.uid,
          displayName: user?.displayName ?? 'Unknown',
          source: ItemSource.app,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add item: $e')),
        );
      }
    }
  }

  Future<void> _showBulkAddDialog(String householdId) async {
    final items = await showDialog<List<ParsedTextItem>>(
      context: context,
      builder: (_) => const BulkAddDialog(title: 'Bulk add to list'),
    );
    if (items == null || items.isEmpty || !mounted) return;

    final user = ref.read(authStateProvider).valueOrNull;
    final categories = ref.read(categoriesProvider).value ?? [];
    final addedBy = AddedBy(
      uid: user?.uid,
      displayName: user?.displayName ?? 'Unknown',
      source: ItemSource.app,
    );

    try {
      for (final item in items) {
        final cat = guessCategory(item.name, categories);
        await ref.read(itemsServiceProvider).addItem(
          householdId: householdId,
          name: item.name,
          categoryId: cat?.id ?? 'uncategorised',
          preferredStores: [],
          pantryItemId: null,
          quantity: item.quantity,
          unit: item.unit,
          addedBy: addedBy,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${items.length} items')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add items: $e')),
        );
      }
    }
  }

  Future<void> _cartItem(String householdId, ShoppingItem item) async {
    final pantryList = ref.read(pantryProvider).value ?? [];
    PantryItem? pantryItem;

    if (item.pantryItemId != null) {
      try {
        pantryItem = pantryList.firstWhere((p) => p.id == item.pantryItemId);
      } catch (_) {}
    } else {
      // No pantry link — create a new pantry entry with current quantity = item quantity
      await ref.read(pantryServiceProvider).addItem(
        householdId: householdId,
        name: item.name,
        categoryId: item.categoryId,
        preferredStores: item.preferredStores,
        optimalQuantity: item.quantity,
        currentQuantity: item.quantity,
      );
    }

    try {
      await ref.read(itemsServiceProvider).checkOff(
        householdId: householdId,
        item: item,
        pantryItem: pantryItem,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cart item: $e')),
        );
      }
    }
  }

  Future<void> _confirmBought(String householdId, List<ShoppingItem> allItems) async {
    final selected = allItems.where((i) => _selectedIds.contains(i.id)).toList();
    if (selected.isEmpty) return;

    final pantryList = ref.read(pantryProvider).value ?? [];
    final pantryMap = {for (final p in pantryList) p.id: p};

    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });

    try {
      await ref.read(itemsServiceProvider).confirmBought(
        householdId: householdId,
        items: selected,
        pantryItems: pantryMap,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm: $e')),
        );
      }
    }
  }

  Future<void> _showEditDialog(ShoppingItem item, String householdId,
      List<GroceryCategory> categories) async {
    final nameCtrl = TextEditingController(text: item.name);
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    String categoryId = item.categoryId;
    String? unit = item.unit;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Edit item'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: unit,
              decoration: const InputDecoration(labelText: 'Unit (optional)', isDense: true),
              items: const [
                DropdownMenuItem(value: null, child: Text('None')),
                DropdownMenuItem(value: 'g', child: Text('g')),
                DropdownMenuItem(value: 'kg', child: Text('kg')),
                DropdownMenuItem(value: 'ml', child: Text('ml')),
                DropdownMenuItem(value: 'L', child: Text('L')),
                DropdownMenuItem(value: 'oz', child: Text('oz')),
                DropdownMenuItem(value: 'lb', child: Text('lb')),
                DropdownMenuItem(value: 'cups', child: Text('cups')),
                DropdownMenuItem(value: 'packs', child: Text('packs')),
                DropdownMenuItem(value: 'bags', child: Text('bags')),
                DropdownMenuItem(value: 'bottles', child: Text('bottles')),
                DropdownMenuItem(value: 'cans', child: Text('cans')),
                DropdownMenuItem(value: 'dozen', child: Text('dozen')),
                DropdownMenuItem(value: 'loaves', child: Text('loaves')),
                DropdownMenuItem(value: 'bunches', child: Text('bunches')),
              ],
              onChanged: (v) => setD(() => unit = v),
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Category'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: categoryId,
                  isExpanded: true,
                  items: categories
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setD(() => categoryId = v ?? categoryId),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(itemsServiceProvider).updateItem(
                  householdId: householdId,
                  itemId: item.id,
                  name: nameCtrl.text.trim(),
                  quantity: int.tryParse(qtyCtrl.text) ?? item.quantity,
                  unit: unit,
                  categoryId: categoryId,
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(filteredItemsProvider);
    final allItems = ref.watch(itemsProvider).value ?? [];
    final categories = ref.watch(categoriesProvider).value ?? [];
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final unitSystem = ref.watch(unitSystemProvider);

    final grouped = <String, List<ShoppingItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.categoryId, () => []).add(item);
    }

    final sortedGroups = grouped.entries.toList()
      ..sort((a, b) {
        final catA = categories.firstWhere(
          (c) => c.id == a.key,
          orElse: () => const GroceryCategory(id: '', name: 'zzz', color: Color(0xFF546E7A), addedBy: ''),
        );
        final catB = categories.firstWhere(
          (c) => c.id == b.key,
          orElse: () => const GroceryCategory(id: '', name: 'zzz', color: Color(0xFF546E7A), addedBy: ''),
        );
        return catA.name.compareTo(catB.name);
      });

    return Scaffold(
      appBar: AppBar(
        title: _selecting
            ? Text('${_selectedIds.length} selected')
            : const Text('Shopping List'),
        actions: [
          if (_selecting)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _cancelSelecting,
              tooltip: 'Cancel selection',
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showManualAddDialog(householdId),
              tooltip: 'Add item',
            ),
            IconButton(
              icon: const Icon(Icons.playlist_add),
              onPressed: () => _showBulkAddDialog(householdId),
              tooltip: 'Bulk add',
            ),
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => context.go('/list/history'),
              tooltip: 'History',
            ),
            TextButton(
              onPressed: () => ref.read(unitSystemProvider.notifier).toggle(),
              child: Text(
                unitSystem == UnitSystem.metric ? 'METRIC' : 'US',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (!_selecting) FilterBar(categories: categories),
          Expanded(
            child: ListView(
              children: sortedGroups.expand((entry) {
                final cat = categories.firstWhere(
                  (c) => c.id == entry.key,
                  orElse: () => const GroceryCategory(id: '', name: 'Uncategorised',
                      color: Color(0xFF546E7A), addedBy: ''),
                );
                return [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 16,
                          decoration: BoxDecoration(
                            color: cat.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(cat.name, style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: cat.color,
                        )),
                        const SizedBox(width: 8),
                        Text('(${entry.value.length})', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cat.color.withValues(alpha: 0.6),
                        )),
                      ],
                    ),
                  ),
                  ...entry.value.map((item) => ItemTile(
                    item: item,
                    unitSystem: unitSystem,
                    isSelecting: _selecting,
                    isSelected: _selectedIds.contains(item.id),
                    onLongPress: () => _enterSelecting(item.id),
                    onTap: () {
                      if (_selecting) {
                        _toggleSelection(item.id);
                      } else {
                        _showEditDialog(item, householdId, categories);
                      }
                    },
                    onCheckOff: () => _cartItem(householdId, item),
                    onDelete: () => ref.read(itemsServiceProvider).deleteItem(
                      householdId: householdId, item: item),
                  )),
                ];
              }).toList(),
            ),
          ),
          if (_selecting)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => _confirmBought(householdId, allItems),
                  icon: const Icon(Icons.shopping_bag),
                  label: Text('Confirm ${_selectedIds.length} bought'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _selecting ? null : VoiceFab(householdId: householdId),
    );
  }
}
