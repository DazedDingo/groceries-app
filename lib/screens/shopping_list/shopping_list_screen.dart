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
import '../../services/fuzzy_match.dart';

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final Set<String> _selectedIds = {};
  bool _selecting = false;
  bool _restockChecked = false;
  Set<String> _knownItemIds = {};

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

    // Suggestions: current list first (highest priority), then history, then pantry.
    final currentListItems =
        (ref.read(itemsProvider).value ?? []).map((i) => i.name).toList();
    final historySuggestions = history
        .where((h) => h.action == HistoryAction.bought)
        .map((h) => h.itemName)
        .toSet()
        .toList();
    final pantryItemNames =
        (ref.read(pantryProvider).value ?? []).map((p) => p.name).toList();

    final result = await showDialog<AddItemResult>(
      context: context,
      builder: (ctx) => AddItemDialog(
        categories: categories,
        currentListItems: currentListItems,
        historySuggestions: historySuggestions,
        pantryItemNames: pantryItemNames,
        categoryOverrides: overrides,
      ),
    );
    if (result == null || !mounted) return;

    // Save category override if user manually changed it.
    if (result.categoryOverridden && result.category != null) {
      ref.read(categoryOverrideServiceProvider).saveOverride(
        householdId: householdId,
        itemName: result.name,
        categoryId: result.category!.id,
      );
    }

    // Re-read items after the dialog so we see any concurrent additions.
    final allItems = ref.read(itemsProvider).value ?? [];

    // ── Exact-match duplicate check ────────────────────────────────────────
    final exactMatches = allItems
        .where((i) => i.name.toLowerCase() == result.name.toLowerCase())
        .toList();
    if (exactMatches.isNotEmpty && mounted) {
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
        final target = exactMatches.first;
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

    // ── Fuzzy-match warning (only when no exact match found) ───────────────
    if (exactMatches.isEmpty && mounted) {
      final fuzzyHits = allItems
          .where((i) =>
              i.name.toLowerCase() != result.name.toLowerCase() &&
              isFuzzyMatch(result.name, i.name))
          .toList();
      if (fuzzyHits.isNotEmpty && mounted) {
        final match = fuzzyHits.first;
        final fuzzyChoice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              const Expanded(child: Text('Similar item on list')),
            ]),
            content: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(ctx).style,
                children: [
                  TextSpan(
                    text: '"${match.name}"',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' is already on your list. Is '),
                  TextSpan(
                    text: '"${result.name}"',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const TextSpan(text: ' a different item, or did you mean to add to it?'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'add'),
                child: const Text('Add separately'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'merge'),
                child: Text('Add to "${match.name}"'),
              ),
            ],
          ),
        );
        if (fuzzyChoice == 'cancel' || fuzzyChoice == null || !mounted) return;
        if (fuzzyChoice == 'merge') {
          await ref.read(itemsServiceProvider).updateItem(
            householdId: householdId,
            itemId: match.id,
            name: match.name,
            quantity: match.quantity + result.quantity,
            unit: result.unit ?? match.unit,
            note: result.note ?? match.note,
            categoryId: match.categoryId,
          );
          return;
        }
        // fuzzyChoice == 'add': fall through to add as new item.
        if (!mounted) return;
      }
    }

    // ── Add new item ───────────────────────────────────────────────────────
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
            unit: item.unit,
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

    // Detect items removed externally (by a partner) and show a brief toast.
    ref.listen(itemsProvider, (prev, next) {
      final prevIds = prev?.value?.map((i) => i.id).toSet() ?? {};
      final nextIds = next.value?.map((i) => i.id).toSet() ?? {};
      final removed = prevIds.difference(nextIds);
      // Only show toast for items we didn't remove ourselves (_knownItemIds
      // is updated in onCheckOff/onDelete before the stream fires).
      final externallyRemoved = removed.difference(_knownItemIds);
      if (externallyRemoved.isNotEmpty && prevIds.isNotEmpty && mounted) {
        final removedItems = prev!.value!
            .where((i) => externallyRemoved.contains(i.id))
            .toList();
        final names = removedItems.map((i) => i.name).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Partner checked off: $names'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _knownItemIds = _knownItemIds.intersection(nextIds);
    });

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

    // High-priority items: linked (by ID or name) to a high-priority pantry item
    // that is below optimal. Name fallback handles manually-added list items.
    PantryItem? pantryFor(ShoppingItem item) {
      if (item.pantryItemId != null) {
        final byId = pantryItems.where((p) => p.id == item.pantryItemId).firstOrNull;
        if (byId != null) return byId;
      }
      return pantryItems
          .where((p) => p.name.toLowerCase() == item.name.toLowerCase())
          .firstOrNull;
    }

    // Star badge: shows whenever the linked pantry item is high priority.
    bool isHighPriority(ShoppingItem item) {
      final pantry = pantryFor(item);
      return pantry != null && pantry.isHighPriority;
    }

    // Priority section (floats to top): high priority AND currently low stock.
    bool isUrgentPriority(ShoppingItem item) {
      final pantry = pantryFor(item);
      return pantry != null && pantry.isHighPriority && pantry.isBelowOptimal;
    }

    final priorityItems = items.where(isUrgentPriority).toList();
    final regularItems = items.where((i) => !isUrgentPriority(i)).toList();

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
                    isHighPriority: isHighPriority(item),
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
                    onCheckOff: () {
                      _knownItemIds.add(item.id);
                      return cartItemDetached(
                        ProviderScope.containerOf(context, listen: false),
                        householdId,
                        item,
                      );
                    },
                    onDelete: () {
                      _knownItemIds.add(item.id);
                      return deleteItemDetached(
                        ProviderScope.containerOf(context, listen: false),
                        householdId,
                        item,
                      );
                    },
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
                    isHighPriority: isHighPriority(item),
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
                    onCheckOff: () {
                      _knownItemIds.add(item.id);
                      return cartItemDetached(
                        ProviderScope.containerOf(context, listen: false),
                        householdId,
                        item,
                      );
                    },
                    onDelete: () {
                      _knownItemIds.add(item.id);
                      return deleteItemDetached(
                        ProviderScope.containerOf(context, listen: false),
                        householdId,
                        item,
                      );
                    },
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
