import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipe_rating_provider.dart';
import '../../models/item.dart';
import '../../models/recipe.dart';
import '../../services/pantry_match.dart';
import '../../services/recipe_rating_service.dart';
import '../../services/unit_converter.dart';
import 'widgets/star_rating.dart';

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
  final listItems = ref.read(itemsProvider).value ?? [];
  final listNames = {for (final i in listItems) i.name.toLowerCase().trim()};

  // Classify ingredients into three buckets: in pantry, already on list, missing.
  final inStock = <RecipeIngredient>[];
  final onList = <RecipeIngredient>[];
  final missing = <RecipeIngredient>[];
  for (final ing in recipe.ingredients) {
    final pantryItem = pantryNames[ing.name.toLowerCase()];
    final needed = ing.quantity * multiplier;
    final pantryCovers = pantryItem != null &&
        hasEnough(pantryItem.currentQuantity, pantryItem.unit, needed, ing.unit);
    if (pantryCovers) {
      inStock.add(ing);
    } else if (listNames.contains(ing.name.toLowerCase().trim())) {
      onList.add(ing);
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
              [
                if (inStock.isNotEmpty) '${inStock.length} in stock',
                if (onList.isNotEmpty) '${onList.length} on list',
                if (missing.isNotEmpty) '${missing.length} missing',
              ].join(', '),
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
                  if (onList.isNotEmpty) ...[
                    Text('Already on list', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.primary,
                    )),
                    const SizedBox(height: 4),
                    ...onList.map((ing) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.shopping_cart_outlined, color: Theme.of(ctx).colorScheme.primary, size: 20),
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
                      label: Text(onList.isEmpty ? 'All in stock!' : 'Ready to cook'),
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
    final recipesAsync = ref.watch(recipesProvider);
    final householdAsync = ref.watch(householdIdProvider);
    final unitSystem = ref.watch(unitSystemProvider);
    final recipes = recipesAsync.value ?? const [];
    final recipe = recipes.where((r) => r.id == widget.recipeId).firstOrNull;
    final householdId = householdAsync.value ?? '';

    // Only treat a missing recipe as "not found" once we're sure the list has
    // actually been fetched and populated. An empty list can appear transiently
    // during auth-token refresh and must not collapse to the white-screen
    // "not found" fallback.
    if (recipe == null) {
      final stillResolving = recipesAsync.isLoading ||
          householdAsync.isLoading ||
          recipes.isEmpty;
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: stillResolving
              ? const CircularProgressIndicator()
              : const Text('Recipe not found'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit recipe',
            onPressed: () => context.go('/recipes/${recipe.id}/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete recipe',
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
          _RecipeHeader(recipe: recipe, householdId: householdId),
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
                onPressed: _multiplier > 1 ? () {
                  HapticFeedback.selectionClick();
                  setState(() => _multiplier--);
                } : null,
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
                onPressed: _multiplier < 10 ? () {
                  HapticFeedback.selectionClick();
                  setState(() => _multiplier++);
                } : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recipe.ingredients.map((ing) {
            final pantryList = ref.watch(pantryProvider).value ?? const [];
            final match = findLenientPantryMatch(ing.name, pantryList);
            final inStock = match != null;
            final color = inStock
                ? Colors.green
                : Theme.of(context).colorScheme.error;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                inStock
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                color: color,
                size: 20,
              ),
              title: Text(ing.name, style: TextStyle(color: color)),
              subtitle: inStock
                  ? Text('In pantry: ${match.currentQuantity}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ))
                  : null,
              trailing: Text(
                  formatQuantityUnit(ing.quantity * _multiplier, ing.unit, unitSystem)),
            );
          }),
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

String _relativeAdded(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}y ago';
  if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
  if (diff.inDays >= 1) return '${diff.inDays}d ago';
  if (diff.inHours >= 1) return '${diff.inHours}h ago';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
  return 'just now';
}

class _RecipeHeader extends ConsumerWidget {
  final Recipe recipe;
  final String householdId;
  const _RecipeHeader({required this.recipe, required this.householdId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).valueOrNull;
    final ratingsAsync = ref.watch(recipeRatingsProvider(recipe.id));
    final ratings = ratingsAsync.value ?? const <String, int>{};
    final summary = RecipeRatingSummary.from(ratings);
    final myRating = user == null ? 0 : (ratings[user.uid] ?? 0);

    final byline = <String>[
      if (recipe.addedByDisplayName != null && recipe.addedByDisplayName!.isNotEmpty)
        'Added by ${recipe.addedByDisplayName}',
      if (recipe.addedAt != null) _relativeAdded(recipe.addedAt!),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (byline.isNotEmpty)
            Text(byline,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          const SizedBox(height: 8),
          Row(
            children: [
              StarRating(
                value: myRating.toDouble(),
                onChanged: user == null
                    ? null
                    : (r) {
                        ref.read(recipeRatingServiceProvider).setRating(
                              householdId: householdId,
                              recipeId: recipe.id,
                              uid: user.uid,
                              rating: r,
                            );
                      },
              ),
              const SizedBox(width: 12),
              if (summary.count > 0)
                Text(
                  '${summary.average.toStringAsFixed(1)} (${summary.count})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Text(
                  'Tap a star to rate',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (myRating > 0) ...[
                const Spacer(),
                TextButton(
                  onPressed: user == null
                      ? null
                      : () => ref.read(recipeRatingServiceProvider).clearRating(
                            householdId: householdId,
                            recipeId: recipe.id,
                            uid: user.uid,
                          ),
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
