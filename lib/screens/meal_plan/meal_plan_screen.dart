import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/meal_plan.dart';
import '../../models/recipe.dart';
import '../../models/item.dart';
import '../../providers/meal_plan_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/auth_provider.dart';
import '../shared/empty_state.dart';
import '../shared/list_skeleton.dart';

final _dayFormat = DateFormat('EEE d');
final _weekdayFormat = DateFormat('E'); // Mon, Tue
final _dayNumFormat = DateFormat('d');

class MealPlanScreen extends ConsumerWidget {
  const MealPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(selectedWeekStartProvider);
    final mealPlanAsync = ref.watch(mealPlanProvider);
    final householdId = ref.watch(householdIdProvider).value ?? '';

    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart),
            tooltip: 'Add all ingredients to list',
            onPressed: (mealPlanAsync.value ?? []).isEmpty ? null : () => _addAllToList(context, ref, mealPlanAsync.value!, householdId),
          ),
        ],
      ),
      body: Column(
        children: [
          // Week navigation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => ref.read(selectedWeekStartProvider.notifier).state =
                      weekStart.subtract(const Duration(days: 7)),
                ),
                TextButton(
                  onPressed: () {
                    final now = DateTime.now();
                    ref.read(selectedWeekStartProvider.notifier).state =
                        now.subtract(Duration(days: now.weekday - 1));
                  },
                  child: Text(
                    '${_dayFormat.format(weekStart)} – ${_dayFormat.format(weekStart.add(const Duration(days: 6)))}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => ref.read(selectedWeekStartProvider.notifier).state =
                      weekStart.add(const Duration(days: 7)),
                ),
              ],
            ),
          ),
          // Week calendar strip — one cell per day, tap to add a meal,
          // dot count shows how many meals are planned for that day.
          mealPlanAsync.maybeWhen(
            data: (entries) => _WeekStrip(
              days: days,
              entries: entries,
              onTapDay: (day) => _showAddMealDialog(context, ref, householdId, day),
            ),
            orElse: () => _WeekStrip(
              days: days,
              entries: const [],
              onTapDay: (day) => _showAddMealDialog(context, ref, householdId, day),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: mealPlanAsync.when(
              loading: () => const ListSkeleton(),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load meal plan',
                subtitle: '$e',
              ),
              data: (entries) => ListView(
                    children: days.map((day) {
                      final dayEntries = entries.where((e) =>
                          e.date.year == day.year &&
                          e.date.month == day.month &&
                          e.date.day == day.day).toList();
                      final isToday = _isToday(day);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Row(
                              children: [
                                if (isToday)
                                  Container(
                                    width: 8, height: 8,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text(
                                  _dayFormat.format(day),
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: isToday ? FontWeight.bold : null,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 20),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _showAddMealDialog(context, ref, householdId, day),
                                ),
                              ],
                            ),
                          ),
                          if (dayEntries.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, bottom: 8),
                              child: Text(
                                'No meals',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ...dayEntries.map((entry) => Dismissible(
                            key: Key(entry.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => ref.read(mealPlanServiceProvider)
                                .removeEntry(householdId, entry.id),
                            child: ListTile(
                              dense: true,
                              leading: Icon(_mealIcon(entry.meal), size: 20),
                              title: Text(entry.recipeName),
                              subtitle: Text('${entry.meal}${entry.servings > 1 ? ' · ${entry.servings}x' : ''}'),
                            ),
                          )),
                          const Divider(height: 1),
                        ],
                      );
                    }).toList(),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  IconData _mealIcon(String meal) => switch (meal) {
    'breakfast' => Icons.free_breakfast,
    'lunch' => Icons.lunch_dining,
    'dinner' => Icons.dinner_dining,
    _ => Icons.restaurant,
  };

  Future<void> _showAddMealDialog(
    BuildContext context,
    WidgetRef ref,
    String householdId,
    DateTime day,
  ) async {
    final recipes = ref.read(recipesProvider).value ?? [];
    if (recipes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some recipes first')),
      );
      return;
    }

    String meal = 'dinner';
    Recipe? selected;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Add meal – ${_dayFormat.format(day)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'breakfast', label: Text('B')),
                  ButtonSegment(value: 'lunch', label: Text('L')),
                  ButtonSegment(value: 'dinner', label: Text('D')),
                ],
                selected: {meal},
                onSelectionChanged: (s) => setDialogState(() => meal = s.first),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Recipe>(
                decoration: const InputDecoration(labelText: 'Recipe'),
                items: recipes.map((r) => DropdownMenuItem(
                  value: r,
                  child: Text(r.name),
                )).toList(),
                onChanged: (r) => setDialogState(() => selected = r),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: selected == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && selected != null) {
      await ref.read(mealPlanServiceProvider).addEntry(
        householdId: householdId,
        date: day,
        meal: meal,
        recipeId: selected!.id,
        recipeName: selected!.name,
      );
    }
  }

  Future<void> _addAllToList(
    BuildContext context,
    WidgetRef ref,
    List<MealPlanEntry> entries,
    String householdId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add all ingredients?'),
        content: Text('Add ingredients from ${entries.length} meal${entries.length == 1 ? '' : 's'} to your shopping list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add all')),
        ],
      ),
    );
    if (confirm != true) return;

    final recipes = ref.read(recipesProvider).value ?? [];
    final user = ref.read(authStateProvider).value;
    final itemsService = ref.read(itemsServiceProvider);

    int count = 0;
    for (final entry in entries) {
      final recipe = recipes.where((r) => r.id == entry.recipeId).firstOrNull;
      if (recipe == null) continue;
      for (final ing in recipe.ingredients) {
        await itemsService.addItem(
          householdId: householdId,
          name: ing.name,
          categoryId: ing.categoryId ?? 'uncategorised',
          preferredStores: [],
          pantryItemId: null,
          quantity: ing.quantity * entry.servings,
          unit: ing.unit,
          recipeSource: recipe.name,
          addedBy: AddedBy(
            uid: user?.uid,
            displayName: user?.displayName ?? 'Unknown',
            source: ItemSource.app,
          ),
        );
        count++;
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $count ingredients to shopping list')),
      );
    }
  }
}

class _WeekStrip extends StatelessWidget {
  final List<DateTime> days;
  final List<MealPlanEntry> entries;
  final void Function(DateTime day) onTapDay;

  const _WeekStrip({
    required this.days,
    required this.entries,
    required this.onTapDay,
  });

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: days.map((day) {
          final count = entries.where((e) => _sameDay(e.date, day)).length;
          final isToday = _sameDay(day, today);
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onTapDay(day),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Column(
                  children: [
                    Text(
                      _weekdayFormat.format(day),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday ? theme.colorScheme.primary : Colors.transparent,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _dayNumFormat.format(day),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: isToday ? theme.colorScheme.onPrimary : null,
                          fontWeight: isToday ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 6,
                      child: count == 0
                          ? null
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                count.clamp(1, 3),
                                (_) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  width: 4, height: 4,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
