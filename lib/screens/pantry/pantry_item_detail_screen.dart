import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/history_entry.dart';
import '../../models/pantry_item.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/household_provider.dart';
import '../../services/shelf_life_resolver.dart';
import '../../providers/categories_provider.dart';
import '../../providers/history_provider.dart';
import '../../models/category.dart';
import '../shared/help_button.dart';

class PantryItemDetailScreen extends ConsumerStatefulWidget {
  final String itemId;
  const PantryItemDetailScreen({super.key, required this.itemId});
  @override
  ConsumerState<PantryItemDetailScreen> createState() => _PantryItemDetailScreenState();
}

class _PantryItemDetailScreenState extends ConsumerState<PantryItemDetailScreen> {
  int? _selectedDays;
  int? _selectedShelfLife;
  int _optimalQuantity = 0;
  bool _isHighPriority = false;
  bool _initialized = false;
  late final TextEditingController _optimalController;
  late final TextEditingController _unitAmountController;
  late final TextEditingController _unitController;

  @override
  void initState() {
    super.initState();
    _optimalController = TextEditingController(text: '0');
    _unitAmountController = TextEditingController();
    _unitController = TextEditingController();
  }

  @override
  void dispose() {
    _optimalController.dispose();
    _unitAmountController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pantry = ref.watch(pantryProvider).value ?? [];
    final item = pantry.where((p) => p.id == widget.itemId).firstOrNull;
    if (item == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (!_initialized) {
      _initialized = true;
      _selectedDays = item.restockAfterDays;
      _selectedShelfLife = item.shelfLifeDays;
      _optimalQuantity = item.optimalQuantity;
      _isHighPriority = item.isHighPriority;
      _optimalController.text = '$_optimalQuantity';
      _unitAmountController.text = _formatUnitAmount(item.unitAmount);
      _unitController.text = item.unit ?? '';
      // Auto-guess shelf life if not set, and persist it. The resolver ladder
      // (learned-from-history → per-item keyword → category fallback) matches
      // what the shopping-list check-off path uses.
      if (_selectedShelfLife == null) {
        final hId = ref.read(householdIdProvider).value ?? '';
        final history = hId.isEmpty
            ? const <HistoryEntry>[]
            : ref.read(historyProvider(hId)).value ?? const <HistoryEntry>[];
        final categories = ref.read(categoriesProvider).value ?? [];
        final catName = categories
            .where((c) => c.id == item.categoryId)
            .map((c) => c.name)
            .firstOrNull;
        _selectedShelfLife = resolveShelfLifeDays(
          itemName: item.name,
          categoryName: catName,
          history: history,
        );
        if (_selectedShelfLife != null && hId.isNotEmpty) {
          ref.read(pantryServiceProvider).updateItem(
              hId, item.id, {'shelfLifeDays': _selectedShelfLife});
        }
      }
    }
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          const HelpButton(
            screenTitle: 'Pantry Item',
            sections: [
              HelpSection(icon: Icons.straighten, title: 'Optimal quantity',
                  body: 'The target amount you want on hand. You\'ll get a restock nudge when current stock drops below this. Use +/- or type the number directly.'),
              HelpSection(icon: Icons.star, title: 'High priority',
                  body: 'When toggled on, this item floats to the top of your shopping list as soon as it goes below optimal, and restock nudges fire immediately.'),
              HelpSection(icon: Icons.calendar_today, title: 'Shelf life',
                  body: 'How long this item lasts after purchase. When you check it off the shopping list, an expiry date is calculated automatically.'),
              HelpSection(icon: Icons.place, title: 'Location',
                  body: 'Where this item lives at home (Fridge, Freezer, Pantry, Counter, Other). Shown on the tile as a small icon.'),
              HelpSection(icon: Icons.notifications, title: 'Restock nudge',
                  body: 'Set an interval (e.g. every 7 days) to get a nudge on the shopping list even if you haven\'t bought it recently.'),
              HelpSection(icon: Icons.category, title: 'Category',
                  body: 'Which section this item falls under. Change it here if the guesser got it wrong — the correction is saved so future items with the same name land in the right place.'),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final router = GoRouter.of(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete pantry item?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (confirm != true || !mounted) return;
              // Use go_router's pop so we return to /pantry via the same
              // router that pushed us here (context.push in pantry_screen).
              // Fire delete after popping so the stream update never rebuilds
              // this screen.
              router.pop();
              ref.read(pantryServiceProvider).deleteItem(householdId, widget.itemId);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Category — first so re-bucketing an item is a one-tap action.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(builder: (ctx) {
                final categories =
                    ref.watch(categoriesProvider).value ?? const <GroceryCategory>[];
                final overrides =
                    ref.watch(categoryOverridesProvider).value ??
                        const <String, String>{};
                final overrideKey = item.name.trim().toLowerCase();
                final hasOverride = overrides.containsKey(overrideKey);
                final knownIds = categories.map((c) => c.id).toSet();
                final currentValue =
                    knownIds.contains(item.categoryId) ? item.categoryId : null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Category', style: theme.textTheme.titleSmall),
                        const Spacer(),
                        if (hasOverride)
                          Tooltip(
                            message:
                                'Clear saved correction and let the guesser decide next time',
                            child: TextButton.icon(
                              onPressed: () async {
                                await ref
                                    .read(categoryOverrideServiceProvider)
                                    .clearOverride(
                                      householdId: householdId,
                                      itemName: item.name,
                                    );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Cleared — future items will use the guesser'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.restart_alt, size: 14),
                              label: const Text('Reset'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String?>(
                      value: currentValue,
                      isExpanded: true,
                      hint: const Text('Uncategorised'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Uncategorised'),
                        ),
                        ...categories.map((c) => DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text(c.name),
                            )),
                      ],
                      onChanged: (val) async {
                        final newId = val ?? 'uncategorised';
                        if (newId == item.categoryId) return;
                        await ref.read(pantryServiceProvider).updateItem(
                            householdId, widget.itemId, {'categoryId': newId});
                        // Picking Uncategorised = fall back to guesser, not
                        // a permanent "stick at uncategorised" override.
                        if (newId == 'uncategorised') {
                          await ref.read(categoryOverrideServiceProvider)
                              .clearOverride(
                                householdId: householdId,
                                itemName: item.name,
                              );
                        } else {
                          await ref.read(categoryOverrideServiceProvider)
                              .saveOverride(
                                householdId: householdId,
                                itemName: item.name,
                                categoryId: newId,
                              );
                        }
                        if (!context.mounted) return;
                        final catName = categories
                            .where((c) => c.id == newId)
                            .map((c) => c.name)
                            .firstOrNull ??
                            'Uncategorised';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Saved — future "${item.name}" items will be $catName'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stock', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Current: ${item.currentQuantity}', style: theme.textTheme.bodyLarge),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Optimal:', style: theme.textTheme.bodyLarge),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove),
                        visualDensity: VisualDensity.compact,
                        onPressed: _optimalQuantity > 0
                            ? () {
                                setState(() {
                                  _optimalQuantity--;
                                  _optimalController.text = '$_optimalQuantity';
                                });
                                ref.read(pantryServiceProvider).updateItem(
                                    householdId, widget.itemId, {'optimalQuantity': _optimalQuantity});
                              }
                            : null,
                      ),
                      SizedBox(
                        width: 56,
                        child: TextField(
                          controller: _optimalController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          ),
                          onSubmitted: (val) {
                            final n = int.tryParse(val) ?? 0;
                            setState(() => _optimalQuantity = n);
                            ref.read(pantryServiceProvider).updateItem(
                                householdId, widget.itemId, {'optimalQuantity': n});
                          },
                          onEditingComplete: () {
                            final n = int.tryParse(_optimalController.text) ?? 0;
                            setState(() => _optimalQuantity = n);
                            ref.read(pantryServiceProvider).updateItem(
                                householdId, widget.itemId, {'optimalQuantity': n});
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _optimalQuantity++;
                            _optimalController.text = '$_optimalQuantity';
                          });
                          ref.read(pantryServiceProvider).updateItem(
                              householdId, widget.itemId, {'optimalQuantity': _optimalQuantity});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Per container', style: theme.textTheme.bodyLarge),
                            Text(
                              'Describes one container (e.g. 500 g). Separate from the count above.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: _unitAmountController,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '500',
                            border: OutlineInputBorder(),
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          ),
                          onSubmitted: (val) {
                            final parsed = double.tryParse(val.trim());
                            ref.read(pantryServiceProvider).updateItem(
                                householdId, widget.itemId, {
                              'unitAmount': parsed,
                            });
                          },
                          onEditingComplete: () {
                            final parsed =
                                double.tryParse(_unitAmountController.text.trim());
                            ref.read(pantryServiceProvider).updateItem(
                                householdId, widget.itemId, {
                              'unitAmount': parsed,
                            });
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _unitController,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'g',
                            border: OutlineInputBorder(),
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          ),
                          onSubmitted: (val) {
                            final trimmed = val.trim();
                            ref.read(pantryServiceProvider).updateItem(
                                householdId, widget.itemId, {
                              'unit': trimmed.isEmpty ? null : trimmed,
                            });
                          },
                          onEditingComplete: () {
                            final trimmed = _unitController.text.trim();
                            ref.read(pantryServiceProvider).updateItem(
                                householdId, widget.itemId, {
                              'unit': trimmed.isEmpty ? null : trimmed,
                            });
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    value: _isHighPriority,
                    onChanged: (v) {
                      setState(() => _isHighPriority = v);
                      ref.read(pantryServiceProvider).updateItem(
                          householdId, widget.itemId, {'isHighPriority': v});
                    },
                    title: const Text('High priority'),
                    subtitle: const Text('Floats to top of list when low, nudge fires immediately'),
                    secondary: Icon(
                      Icons.star,
                      color: _isHighPriority ? Colors.amber : theme.colorScheme.outlineVariant,
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (item.isBelowOptimal)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, size: 16, color: theme.colorScheme.error),
                          const SizedBox(width: 4),
                          Text('Below optimal', style: TextStyle(color: theme.colorScheme.error)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Expiry section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expiry', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (item.expiresAt != null) ...[
                    Row(
                      children: [
                        Icon(
                          item.isExpired ? Icons.error : item.isExpiringSoon ? Icons.warning_amber : Icons.check_circle,
                          size: 16,
                          color: item.isExpired ? theme.colorScheme.error : item.isExpiringSoon ? Colors.orange : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.isExpired
                              ? 'Expired ${_formatDate(item.expiresAt!)}'
                              : 'Expires ${_formatDate(item.expiresAt!)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text('Shelf life', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  DropdownButton<int?>(
                    value: _selectedShelfLife,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Not set')),
                      DropdownMenuItem(value: 3, child: Text('3 days')),
                      DropdownMenuItem(value: 5, child: Text('5 days')),
                      DropdownMenuItem(value: 7, child: Text('7 days')),
                      DropdownMenuItem(value: 10, child: Text('10 days')),
                      DropdownMenuItem(value: 14, child: Text('14 days')),
                      DropdownMenuItem(value: 30, child: Text('30 days')),
                      DropdownMenuItem(value: 90, child: Text('90 days')),
                      DropdownMenuItem(value: 180, child: Text('180 days')),
                      DropdownMenuItem(value: 365, child: Text('1 year')),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedShelfLife = val);
                      ref.read(pantryServiceProvider).updateItem(
                          householdId, widget.itemId, {'shelfLifeDays': val});
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Location
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Location', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => context.push('/settings/locations'),
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text('Manage'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Builder(builder: (ctx) {
                    final customLocations =
                        ref.watch(customLocationsProvider).value ?? [];
                    return DropdownButton<String?>(
                      value: item.location,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Not set')),
                        ...PantryLocation.values.map((loc) =>
                            DropdownMenuItem<String?>(
                              value: loc.id,
                              child: Text(loc.label),
                            )),
                        if (customLocations.isNotEmpty) ...[
                          const DropdownMenuItem<String?>(
                            enabled: false,
                            value: '__divider__',
                            child: Divider(height: 1),
                          ),
                          ...customLocations.map((label) =>
                              DropdownMenuItem<String?>(
                                value: label,
                                child: Text(label),
                              )),
                        ],
                      ],
                      onChanged: (val) {
                        if (val == '__divider__') return;
                        ref.read(pantryServiceProvider).updateItem(
                            householdId, widget.itemId, {'location': val});
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Restock nudge
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Restock nudge', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButton<int?>(
                    value: _selectedDays,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Off')),
                      DropdownMenuItem(value: 3, child: Text('Every 3 days')),
                      DropdownMenuItem(value: 7, child: Text('Every 7 days')),
                      DropdownMenuItem(value: 14, child: Text('Every 14 days')),
                      DropdownMenuItem(value: 30, child: Text('Every 30 days')),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedDays = val);
                      ref.read(pantryServiceProvider).updateItem(
                          householdId, widget.itemId, {'restockAfterDays': val});
                    },
                  ),
                  if (item.lastPurchasedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Last purchased: ${_formatDate(item.lastPurchasedAt!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatUnitAmount(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    if (diff == -1) return 'yesterday';
    if (diff > 0) return 'in $diff days';
    return '${-diff} days ago';
  }
}
