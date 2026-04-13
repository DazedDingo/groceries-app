import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../models/item.dart';
import '../../services/unit_converter.dart';

class RecipeDetailScreen extends ConsumerWidget {
  final String recipeId;
  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider).value ?? [];
    final recipe = recipes.where((r) => r.id == recipeId).firstOrNull;
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final unitSystem = ref.watch(unitSystemProvider);

    if (recipe == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Recipe not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.name),
        actions: [
          TextButton(
            onPressed: () => ref.read(unitSystemProvider.notifier).toggle(),
            child: Text(
              unitSystem == UnitSystem.metric ? 'METRIC' : 'US',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.go('/recipes/${recipe.id}/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete recipe?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(recipesServiceProvider).deleteRecipe(
                  householdId: householdId,
                  recipeId: recipe.id,
                );
                if (context.mounted) context.go('/recipes');
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (recipe.notes != null && recipe.notes!.isNotEmpty) ...[
            Text(recipe.notes!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
          ],
          if (recipe.sourceUrl != null && recipe.sourceUrl!.isNotEmpty) ...[
            InkWell(
              onTap: () => launchUrl(Uri.parse(recipe.sourceUrl!)),
              child: Row(
                children: [
                  Icon(Icons.link, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      recipe.sourceUrl!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...recipe.ingredients.map((ing) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(ing.name),
            trailing: Text(formatQuantityUnit(ing.quantity, ing.unit, unitSystem)),
          )),
          if (recipe.instructions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...recipe.instructions.asMap().entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${entry.key + 1}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(entry.value, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
              ),
            )),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              final user = ref.read(authStateProvider).value;
              final itemsService = ref.read(itemsServiceProvider);

              for (final ing in recipe.ingredients) {
                await itemsService.addItem(
                  householdId: householdId,
                  name: ing.name,
                  categoryId: ing.categoryId ?? 'uncategorised',
                  preferredStores: [],
                  pantryItemId: null,
                  quantity: ing.quantity,
                  unit: ing.unit,
                  recipeSource: recipe.name,
                  addedBy: AddedBy(
                    uid: user?.uid,
                    displayName: user?.displayName ?? 'Unknown',
                    source: ItemSource.app,
                  ),
                );
              }

              if (context.mounted) {
                // Check for duplicates and mention in snackbar
                final existingItems = ref.read(itemsProvider).value ?? [];
                final counts = <String, int>{};
                for (final item in existingItems) {
                  counts[item.name.toLowerCase()] = (counts[item.name.toLowerCase()] ?? 0) + 1;
                }
                final dupes = counts.entries
                    .where((e) => e.value > 1)
                    .map((e) => e.key)
                    .toList();

                final msg = dupes.isEmpty
                    ? 'Added ${recipe.ingredients.length} items to shopping list'
                    : 'Added ${recipe.ingredients.length} items (${dupes.join(", ")} already on list)';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              }
            },
            icon: const Icon(Icons.restaurant),
            label: const Text('Cook this'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}
