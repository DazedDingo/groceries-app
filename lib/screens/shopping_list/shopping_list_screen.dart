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
import 'cart_action.dart';
import 'widgets/item_tile.dart';
import 'widgets/filter_bar.dart';
import 'widgets/voice_fab.dart';
import 'widgets/add_item_dialog.dart';
import 'widgets/barcode_scanner_dialog.dart';
import '../../services/unit_converter.dart';
import '../../services/category_guesser.dart';
import '../shared/bulk_add_dialog.dart';
import '../shared/empty_state.dart';
import '../../services/text_item_parser.dart';
import '../../providers/history_provider.dart';
import '../../models/history_entry.dart';
import '../../services/restock_checker.dart';

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final Set<String> _selectedIds = {};
  bool _selecting = false;
  bool _restockChecked = false;

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
    final overrides = ref.read(categoryOverridesProvider).value ?? {};
    final history = ref.read(historyProvider(householdId)).value ?? [];
    final suggestions = history
        .where((h) => h.action == HistoryAction.bought)
        .map((h) => h.itemName)
        .toSet()
        .toList();
    final result = await showDialog<AddItemResult>(
      context: context,
      builder: (ctx) => AddItemDialog(
        categories: categories,
        historySuggestions: suggestions,
        categoryOverrides: overrides,
      ),
    );
    if (result == null || !mounted) return;

    // Save category override if user manually changed it
    if (result.categoryOverridden && result.category != null) {
      ref.read(categoryOverrideServiceProvider).saveOverride(
        householdId: householdId,
        itemName: result.name,
        categoryId: result.category!.id,
      );
    }

    // Check for duplicate — offer to merge by bumping quantity
    final allItems = ref.read(itemsProvider).value ?? [];
    final existing = allItems.where(
      (item) => item.name.toLowerCase() == result.name.toLowerCase(),
    ).toList();
    if (existing.isNotEmpty && mounted) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Item already on list'),
          content: Text('"${result.name}" is already on your shopping list.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'add'), child: const Text('Add separately')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('Add to quantity')),
          ],
        ),
      );
      if (choice == 'merge') {
        final target = existing.first;
        await ref.read(itemsServiceProvider).updateItem(
          householdId: householdId,
          itemId: target.id,
          name: target.name,
          quantity: target.quantity + result.quantity,
          unit: result.unit ?? target.unit,
          note: result.note ?? target.note,
          categoryId: target.categoryId,
        );
        return;
      }
      if (choice != 'add' || !mounted) return;
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
        note: result.note,
        isRecurring: result.isRecurring,
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

  Future<void> _scanBarcode(String householdId) async {
    final productName = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerDialog()),
    );
    if (productName == null || !mounted) return;

    // Open the add item dialog pre-filled with the scanned product name
    final categories = ref.read(categoriesProvider).value ?? [];
    final overrides = ref.read(categoryOverridesProvider).value ?? {};
    final guessed = guessCategory(productName, categories, overrides);

    final result = await showDialog<AddItemResult>(
      context: context,
      builder: (ctx) => AddItemDialog(
        initialName: productName,
        categories: categories,
        initialCategory: guessed,
        categoryOverrides: overrides,
      ),
    );
    if (result == null || !mounted) return;

    if (result.categoryOverridden && result.category != null) {
      ref.read(categoryOverrideServiceProvider).saveOverride(
        householdId: householdId,
        itemName: result.name,
        categoryId: result.category!.id,
      );
    }

    final user = ref.read(authStateProvider).valueOrNull;
    await ref.read(itemsServiceProvider).addItem(
      householdId: householdId,
      name: result.name,
      categoryId: result.category?.id ?? 'uncategorised',
      preferredStores: [],
      pantryItemId: null,
      quantity: result.quantity,
      unit: result.unit,
      note: result.note,
      isRecurring: result.isRecurring,
      addedBy: AddedBy(
        uid: user?.uid,
        displayName: user?.displayName ?? 'Unknown',
        source: ItemSource.app,
      ),
    );
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

  Future<void> _confirmBought(String householdId, List<ShoppingItem> allItems) async {
    final selected = allItems.where((i) => _selectedIds.contains(i.id)).toList();
    if (selected.isEmpty) return;

    final pantryList = ref.read(pantryProvider).value ?? [];
    final pantryMap = {for (final p in pantryList) p.id: p};

    try {
      // Create pantry items for shopping items not already linked to pantry
      for (final item in selected) {
        if (item.pantryItemId == null) {
          await ref.read(pantryServiceProvider).addItem(
            householdId: householdId,
            name: item.name,
            categoryId: item.categoryId,
            preferredStores: item.preferredStores,
            optimalQuantity: item.isRecurring ? item.quantity : 0,
            currentQuantity: item.quantity,
          );
        }
      }

      await ref.read(itemsServiceProvider).confirmBought(
        householdId: householdId,
        items: selected,
        pantryItems: pantryMap,
      );
      if (mounted) {
        setState(() {
          _selecting = false;
          _selectedIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm: $e')),
        );
      }
    }
  }

  Future<void> _showRestockNudge(String householdId, List<PantryItem> overdue) async {
    final selected = Set<String>.from(overdue.map((p) => p.id));

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Restock reminder'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'These items are due for restocking:',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                ...overdue.map((item) => CheckboxListTile(
                  title: Text(item.name),
                  subtitle: Text('${item.currentQuantity}/${item.optimalQuantity} in stock'),
                  value: selected.contains(item.id),
                  onChanged: (v) => setD(() {
                    if (v == true) {
                      selected.add(item.id);
                    } else {
                      selected.remove(item.id);
                    }
                  }),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Dismiss')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: Text('Add ${selected.length} to list'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;

    final user = ref.read(authStateProvider).valueOrNull;
    final addedBy = AddedBy(
      uid: user?.uid,
      displayName: user?.displayName ?? 'Unknown',
      source: ItemSource.app,
    );

    for (final item in overdue.where((p) => result.contains(p.id))) {
      final qty = (item.optimalQuantity - item.currentQuantity).clamp(1, 999);
      await ref.read(itemsServiceProvider).addItem(
        householdId: householdId,
        name: item.name,
        categoryId: item.categoryId,
        preferredStores: item.preferredStores,
        pantryItemId: item.id,
        quantity: qty,
        addedBy: addedBy,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${result.length} restock items')),
      );
    }
  }

  Future<void> _showReorderLastTrip(String householdId) async {
    final history = ref.read(historyProvider(householdId)).value ?? [];
    final bought = history.where((h) => h.action == HistoryAction.bought).toList();
    if (bought.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No purchase history yet')),
        );
      }
      return;
    }

    // Group by "trip" — items bought within 2 hours of the most recent
    final latest = bought.first.at;
    final tripItems = bought
        .where((h) => latest.difference(h.at).inHours.abs() < 2)
        .map((h) => h.itemName)
        .toSet()
        .toList();

    final selected = Set<String>.from(tripItems);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Reorder last trip'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: tripItems.map((name) => CheckboxListTile(
                title: Text(name),
                value: selected.contains(name),
                onChanged: (v) => setD(() {
                  if (v == true) {
                    selected.add(name);
                  } else {
                    selected.remove(name);
                  }
                }),
              )).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: Text('Add ${selected.length} items'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;

    final user = ref.read(authStateProvider).valueOrNull;
    final categories = ref.read(categoriesProvider).value ?? [];
    final addedBy = AddedBy(
      uid: user?.uid,
      displayName: user?.displayName ?? 'Unknown',
      source: ItemSource.app,
    );

    for (final name in result) {
      // Find the history entry to get the category and quantity
      final entry = bought.firstWhere((h) => h.itemName == name);
      final cat = guessCategory(name, categories);
      await ref.read(itemsServiceProvider).addItem(
        householdId: householdId,
        name: name,
        categoryId: cat?.id ?? entry.categoryId,
        preferredStores: [],
        pantryItemId: null,
        quantity: entry.quantity,
        addedBy: addedBy,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${result.length} items from last trip')),
      );
    }
  }

  Future<void> _showEditDialog(ShoppingItem item, String householdId,
      List<GroceryCategory> categories) async {
    final nameCtrl = TextEditingController(text: item.name);
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final noteCtrl = TextEditingController(text: item.note ?? '');
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
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. brand, size, type',
                isDense: true,
              ),
              maxLines: 1,
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
              onPressed: () async {
                Navigator.pop(ctx);
                final noteText = noteCtrl.text.trim();
                try {
                  await ref.read(itemsServiceProvider).updateItem(
                    householdId: householdId,
                    itemId: item.id,
                    name: nameCtrl.text.trim(),
                    quantity: int.tryParse(qtyCtrl.text) ?? item.quantity,
                    unit: unit,
                    note: noteText.isEmpty ? null : noteText,
                    categoryId: categoryId,
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update: $e')),
                    );
                  }
                }
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

    final pantryItems = ref.watch(pantryProvider).value ?? [];

    // Check for overdue restocks once pantry data loads
    ref.listen(pantryProvider, (prev, next) {
      if (_restockChecked) return;
      final pantryList = next.value;
      if (pantryList == null) return; // still loading
      _restockChecked = true;
      final overdue = findOverdueRestocks(pantryList);
      if (overdue.isNotEmpty && householdId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showRestockNudge(householdId, overdue);
        });
      }
    });

    // High-priority items: linked to a high-priority pantry item that is below optimal
    bool isHighPriorityItem(ShoppingItem item) {
      if (item.pantryItemId == null) return false;
      final pantry = pantryItems.where((p) => p.id == item.pantryItemId).firstOrNull;
      return pantry != null && pantry.isHighPriority && pantry.isBelowOptimal;
    }

    final priorityItems = items.where(isHighPriorityItem).toList();
    final regularItems = items.where((i) => !isHighPriorityItem(i)).toList();

    final grouped = <String, List<ShoppingItem>>{};
    for (final item in regularItems) {
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
              icon: const Icon(Icons.playlist_add),
              onPressed: () => _showBulkAddDialog(householdId),
              tooltip: 'Bulk add',
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) {
                if (val == 'history') context.go('/list/history');
                if (val == 'templates') context.go('/list/templates');
                if (val == 'reorder') _showReorderLastTrip(householdId);
                if (val == 'scan') _scanBarcode(householdId);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'scan', child: Text('Scan barcode')),
                PopupMenuItem(value: 'reorder', child: Text('Reorder last trip')),
                PopupMenuItem(value: 'templates', child: Text('Templates')),
                PopupMenuItem(value: 'history', child: Text('History')),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          FilterBar(categories: categories),
          Expanded(
            child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  title: 'Your list is empty',
                  subtitle: 'Tap the microphone button or long-press to add items',
                )
              : ListView(
              children: [
                if (priorityItems.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text('Priority', style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.amber.shade700,
                        )),
                        const SizedBox(width: 8),
                        Text('(${priorityItems.length})', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.amber.shade400,
                        )),
                      ],
                    ),
                  ),
                  ...priorityItems.map((item) => ItemTile(
                    key: ValueKey(item.id),
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
                    onCheckOff: () => cartItemDetached(
                      ProviderScope.containerOf(context, listen: false),
                      householdId,
                      item,
                    ),
                    onDelete: () => deleteItemDetached(
                      ProviderScope.containerOf(context, listen: false),
                      householdId,
                      item,
                    ),
                    onUndo: (receipt) => undoDetached(
                      ProviderScope.containerOf(context, listen: false),
                      householdId,
                      receipt,
                    ),
                  )),
                  const Divider(),
                ],
                ...sortedGroups.expand((entry) {
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
                    key: ValueKey(item.id),
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
                    onCheckOff: () => cartItemDetached(
                      ProviderScope.containerOf(context, listen: false),
                      householdId,
                      item,
                    ),
                    onDelete: () => deleteItemDetached(
                      ProviderScope.containerOf(context, listen: false),
                      householdId,
                      item,
                    ),
                    onUndo: (receipt) => undoDetached(
                      ProviderScope.containerOf(context, listen: false),
                      householdId,
                      receipt,
                    ),
                  )),
                ];
              }),
              ],
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
      floatingActionButton: _selecting
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'add-manual',
                  onPressed: () => _showManualAddDialog(householdId),
                  tooltip: 'Add item',
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                VoiceFab(householdId: householdId),
              ],
            ),
    );
  }
}
