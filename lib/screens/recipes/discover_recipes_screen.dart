import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/recipe_search_provider.dart';
import '../../services/recipe_import_service.dart';
import '../../services/recipe_search_service.dart';

class DiscoverRecipesScreen extends ConsumerStatefulWidget {
  const DiscoverRecipesScreen({super.key});

  @override
  ConsumerState<DiscoverRecipesScreen> createState() =>
      _DiscoverRecipesScreenState();
}

class _DiscoverRecipesScreenState extends ConsumerState<DiscoverRecipesScreen> {
  final _searchCtrl = TextEditingController();
  RecipeSource _source = RecipeSource.mealdb;
  bool _loading = false;
  String? _error;
  String? _loadingPreviewId;
  bool _saving = false;
  List<RecipeSearchResult> _results = const [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
    });
    try {
      final service = ref.read(recipeSearchServiceProvider);
      final results = _source == RecipeSource.mealdb
          ? await service.searchMealDb(q)
          : await service.searchSpoonacular(
              q, ref.read(spoonacularKeyProvider));
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPreview(RecipeSearchResult r) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loadingPreviewId = r.id);
    try {
      final service = ref.read(recipeSearchServiceProvider);
      final imported = r.source == RecipeSource.mealdb
          ? await service.fetchMealDb(r.id)
          : await service.fetchSpoonacular(
              r.id, ref.read(spoonacularKeyProvider));
      if (!mounted) return;
      _showPreviewSheet(imported, r);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Could not load recipe: ${e.toString().replaceFirst('Exception: ', '')}'),
      ));
    } finally {
      if (mounted) setState(() => _loadingPreviewId = null);
    }
  }

  void _showPreviewSheet(ImportedRecipe imported, RecipeSearchResult r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(imported.name, style: Theme.of(sheetCtx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${imported.ingredients.length} ingredients · ${imported.instructions.length} steps',
                style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    if (r.thumbUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            r.thumbUrl!,
                            height: 160,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    Text('Ingredients',
                        style: Theme.of(sheetCtx).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    ...imported.ingredients.map((ing) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${ing.quantity}${ing.unit != null ? ' ${ing.unit}' : ''} ${ing.name}'),
                        )),
                    if (imported.instructions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Instructions',
                          style: Theme.of(sheetCtx).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      ...imported.instructions.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text('${e.key + 1}. ${e.value}'),
                          )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(builder: (ctx, setSheet) {
                return Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.pop(sheetCtx),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.bookmark_add),
                        label: Text(_saving ? 'Saving…' : 'Save to my recipes'),
                        onPressed: _saving
                            ? null
                            : () async {
                                setSheet(() {});
                                await _saveRecipe(imported);
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              },
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveRecipe(ImportedRecipe imported) async {
    final messenger = ScaffoldMessenger.of(context);

    // Read auth synchronously from FirebaseAuth.currentUser — reliable once
    // the app has booted, unlike the async auth provider which may not have
    // emitted by the time the user taps Save.
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Please sign in to save recipes')));
      return;
    }

    setState(() => _saving = true);
    try {
      // Go direct to the service rather than trusting a cached provider.
      final householdId = await ref
          .read(householdServiceProvider)
          .getHouseholdIdForUser(user.uid);

      if (householdId == null || householdId.isEmpty) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(
            content: Text('No household set up — check Settings')));
        return;
      }

      await ref.read(recipesServiceProvider).addRecipe(
            householdId: householdId,
            name: imported.name,
            ingredients: imported.ingredients,
            instructions: imported.instructions,
            notes: imported.notes,
            sourceUrl: imported.sourceUrl,
            addedByUid: user.uid,
            addedByDisplayName: user.displayName ?? 'Unknown',
          );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Saved "${imported.name}" to your recipes'),
        duration: const Duration(seconds: 2),
      ));
      if (context.mounted) context.go('/recipes');
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Could not save: $e'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spoonKey = ref.watch(spoonacularKeyProvider);
    // Warm auth + household so they're resolved by the time the user taps Save.
    ref.watch(authStateProvider);
    ref.watch(householdIdProvider);
    final needsKey = _source == RecipeSource.spoonacular && spoonKey.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Discover recipes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<RecipeSource>(
                  segments: const [
                    ButtonSegment(
                      value: RecipeSource.mealdb,
                      label: Text('TheMealDB'),
                      icon: Icon(Icons.public),
                    ),
                    ButtonSegment(
                      value: RecipeSource.spoonacular,
                      label: Text('Spoonacular'),
                      icon: Icon(Icons.restaurant),
                    ),
                  ],
                  selected: {_source},
                  onSelectionChanged: (s) => setState(() {
                    _source = s.first;
                    _results = const [];
                    _error = null;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search recipes…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _results = const []);
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _runSearch(),
                ),
                if (needsKey)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Add your free Spoonacular API key in Settings.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.go('/settings'),
                          child: const Text('Settings'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isEmpty
                              ? 'Search for a recipe to get started'
                              : 'No results',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final r = _results[i];
                          return ListTile(
                            leading: r.thumbUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      r.thumbUrl!,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.restaurant),
                                    ),
                                  )
                                : const Icon(Icons.restaurant),
                            title: Text(r.title),
                            subtitle: Text(r.source == RecipeSource.mealdb
                                ? 'TheMealDB'
                                : 'Spoonacular'),
                            trailing: _loadingPreviewId == r.id
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: _loadingPreviewId == null
                                ? () => _openPreview(r)
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
