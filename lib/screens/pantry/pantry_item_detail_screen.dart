import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/pantry_item.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/household_provider.dart';
import '../../services/shelf_life_guesser.dart';
import '../../providers/categories_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _optimalController = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _optimalController.dispose();
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
      // Auto-guess shelf life if not set, and persist it
      if (_selectedShelfLife == null) {
        final categories = ref.read(categoriesProvider).value ?? [];
        final catName = categories
            .where((c) => c.id == item.categoryId)
            .map((c) => c.name)
            .firstOrNull;
        if (catName != null) {
          _selectedShelfLife = guessShelfLifeDays(catName);
          if (_selectedShelfLife != null) {
            final hId = ref.read(householdIdProvider).value ?? '';
            if (hId.isNotEmpty) {
              ref.read(pantryServiceProvider).updateItem(
                  hId, item.id, {'shelfLifeDays': _selectedShelfLife});
            }
          }
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
                  Text('Location', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButton<PantryLocation?>(
                    value: item.location,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<PantryLocation?>(
                          value: null, child: Text('Not set')),
                      ...PantryLocation.values.map((loc) => DropdownMenuItem(
                            value: loc,
                            child: Text(loc.label),
                          )),
                    ],
                    onChanged: (val) {
                      ref.read(pantryServiceProvider).updateItem(
                          householdId, widget.itemId, {'location': val?.id});
                    },
                  ),
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
