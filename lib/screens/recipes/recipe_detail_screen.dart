import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../models/item.dart';

class RecipeDetailScreen extends ConsumerWidget {
  final String recipeId;
  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider).value ?? [];
    final recipe = recipes.where((r) => r.id == recipeId).firstOrNull;
    final householdId = ref.watch(householdIdProvider).value ?? '';

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
          Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...recipe.ingredients.map((ing) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(ing.name),
            trailing: Text('x${ing.quantity}'),
          )),
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
                  addedBy: AddedBy(
                    uid: user?.uid,
                    displayName: user?.displayName ?? 'Unknown',
                    source: ItemSource.app,
                  ),
                );
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added ${recipe.ingredients.length} items to shopping list')),
                );
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
