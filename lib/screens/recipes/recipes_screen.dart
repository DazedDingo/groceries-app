import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../services/pantry_match.dart';
import '../shared/empty_state.dart';
import '../shared/list_skeleton.dart';
import '../shared/help_button.dart';

final _selectedTagProvider = StateProvider<String?>((ref) => null);
final _canMakeNowProvider = StateProvider<bool>((ref) => false);

class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider);
    final selectedTag = ref.watch(_selectedTagProvider);
    final canMakeNow = ref.watch(_canMakeNowProvider);
    final pantry = ref.watch(pantryProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
        actions: const [
          HelpButton(
            screenTitle: 'Recipes',
            sections: [
              HelpSection(icon: Icons.add, title: 'Adding recipes',
                  body: 'Tap + to add a recipe manually. Use Discover (top-right) to search TheMealDB or Spoonacular and import recipes automatically.'),
              HelpSection(icon: Icons.touch_app, title: 'Viewing a recipe',
                  body: 'Tap a recipe card to see ingredients and instructions.'),
              HelpSection(icon: Icons.add_shopping_cart, title: 'Cook This',
                  body: 'On a recipe detail screen, tap "Cook This" to add scaled ingredients directly to your shopping list.'),
              HelpSection(icon: Icons.calendar_month, title: 'Meal plan',
                  body: 'Tap the calendar icon on a recipe to add it to a day in your meal plan.'),
              HelpSection(icon: Icons.filter_list, title: 'Filtering',
                  body: 'Use the tag chips to filter by cuisine or type. Toggle "Can make now" to show only recipes you have all the ingredients for.'),
            ],
          ),
        ],
      ),
      body: recipes.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => const EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          subtitle: 'Could not load recipes. Pull down to retry.',
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.restaurant_menu,
              title: 'No recipes yet',
              subtitle: 'Save your favourite recipes and quickly add ingredients to your shopping list',
              action: FilledButton.icon(
                onPressed: () => context.go('/recipes/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add recipe'),
              ),
            );
          }

          // Collect all unique tags
          final allTags = list.expand((r) => r.tags).toSet().toList()..sort();
          var filtered = selectedTag == null
              ? list
              : list.where((r) => r.tags.contains(selectedTag)).toList();
          if (canMakeNow) {
            filtered = filtered.where((r) => canMakeFromPantry(r, pantry)).toList();
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    FilterChip(
                      avatar: Icon(
                        canMakeNow ? Icons.check_circle : Icons.kitchen,
                        size: 18,
                        color: canMakeNow ? Colors.green : null,
                      ),
                      label: const Text('Can make now'),
                      selected: canMakeNow,
                      onSelected: (v) =>
                          ref.read(_canMakeNowProvider.notifier).state = v,
                    ),
                  ],
                ),
              ),
              if (allTags.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: allTags.map((tag) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(tag),
                        selected: selectedTag == tag,
                        onSelected: (_) => ref.read(_selectedTagProvider.notifier).state =
                            selectedTag == tag ? null : tag,
                      ),
                    )).toList(),
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            canMakeNow
                                ? "Nothing you can make right now — pantry's a bit light."
                                : 'No matching recipes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final r = filtered[i];
                    return ListTile(
                      title: Text(r.name),
                      subtitle: Text([
                        '${r.ingredients.length} ingredients',
                        if (r.tags.isNotEmpty) r.tags.join(', '),
                      ].join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/recipes/${r.id}'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'discover',
            onPressed: () => context.go('/recipes/discover'),
            tooltip: 'Discover recipes',
            child: const Icon(Icons.search),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'import',
            onPressed: () => context.go('/recipes/new?import=true'),
            tooltip: 'Import from URL',
            child: const Icon(Icons.link),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () => context.go('/recipes/new'),
            tooltip: 'New recipe',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
