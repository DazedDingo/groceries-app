import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/recipes_provider.dart';

class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      body: recipes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No recipes yet. Tap + to create one.'));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              return ListTile(
                title: Text(r.name),
                subtitle: Text('${r.ingredients.length} ingredients'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/recipes/${r.id}'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/recipes/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
