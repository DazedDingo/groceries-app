import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/recipes_provider.dart';

final _selectedTagProvider = StateProvider<String?>((ref) => null);

class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider);
    final selectedTag = ref.watch(_selectedTagProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      body: recipes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No recipes yet. Tap + to create one.'));
          }

          // Collect all unique tags
          final allTags = list.expand((r) => r.tags).toSet().toList()..sort();
          final filtered = selectedTag == null
              ? list
              : list.where((r) => r.tags.contains(selectedTag)).toList();

          return Column(
            children: [
              if (allTags.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                child: ListView.builder(
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
