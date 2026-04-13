import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../models/item.dart';
import '../../models/recipe.dart';
import '../../services/unit_converter.dart';

void _showCookThisDialog(
  BuildContext context,
  WidgetRef ref,
  Recipe recipe,
  String householdId,
  UnitSystem unitSystem, [
  int multiplier = 1,
]) {
  final pantryItems = ref.read(pantryProvider).value ?? [];
  final pantryNames = {for (final p in pantryItems) p.name.toLowerCase(): p};

  // Classify ingredients
  final inStock = <RecipeIngredient>[];
  final missing = <RecipeIngredient>[];
  for (final ing in recipe.ingredients) {
    final pantryItem = pantryNames[ing.name.toLowerCase()];
    final needed = ing.quantity * multiplier;
    if (pantryItem != null && pantryItem.currentQuantity >= needed) {
      inStock.add(ing);
    } else {
      missing.add(ing);
    }
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Pantry check', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${inStock.length} in stock, ${missing.length} missing',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  if (missing.isNotEmpty) ...[
                    Text('Missing', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.error,
                    )),
                    const SizedBox(height: 4),
                    ...missing.map((ing) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cancel_outlined, color: Theme.of(ctx).colorScheme.error, size: 20),
                      title: Text(ing.name),
                      trailing: Text(formatQuantityUnit(ing.quantity * multiplier, ing.unit, unitSystem)),
                    )),
                    const Divider(),
                  ],
                  if (inStock.isNotEmpty) ...[
                    Text('In stock', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      color: Colors.green,
                    )),
                    const SizedBox(height: 4),
                    ...inStock.map((ing) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                      title: Text(ing.name),
                      trailing: Text(formatQuantityUnit(ing.quantity * multiplier, ing.unit, unitSystem)),
                    )),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                if (missing.isNotEmpty)
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final user = ref.read(authStateProvider).value;
                        final itemsService = ref.read(itemsServiceProvider);

                        for (final ing in missing) {
                          await itemsService.addItem(
                            householdId: householdId,
                            name: ing.name,
                            categoryId: ing.categoryId ?? 'uncategorised',
                            preferredStores: [],
                            pantryItemId: null,
                            quantity: ing.quantity * multiplier,
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
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Added ${missing.length} missing items to list'),
                          ));
                        }
                      },
                      icon: const Icon(Icons.add_shopping_cart),
                      label: Text('Add ${missing.length} missing to list'),
                    ),
                  ),
                if (missing.isEmpty)
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('All in stock!'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class RecipeDetailScreen extends ConsumerStatefulWidget {
  final String recipeId;
  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  int _multiplier = 1;

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipesProvider).value ?? [];
    final recipe = recipes.where((r) => r.id == widget.recipeId).firstOrNull;
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

          // Multiplier control
          Row(
            children: [
              Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: _multiplier > 1 ? () => setState(() => _multiplier--) : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${_multiplier}x',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: _multiplier < 10 ? () => setState(() => _multiplier++) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recipe.ingredients.map((ing) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(ing.name),
            trailing: Text(formatQuantityUnit(ing.quantity * _multiplier, ing.unit, unitSystem)),
          )),
          if (recipe.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              children: recipe.tags.map((t) => Chip(
                label: Text(t),
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          ],
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
            onPressed: () => _showCookThisDialog(context, ref, recipe, householdId, unitSystem, _multiplier),
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
