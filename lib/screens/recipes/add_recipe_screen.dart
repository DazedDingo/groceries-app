import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/categories_provider.dart';
import '../../models/recipe.dart';
import '../../services/category_guesser.dart';

class AddRecipeScreen extends ConsumerStatefulWidget {
  final String? recipeId;
  const AddRecipeScreen({super.key, this.recipeId});

  @override
  ConsumerState<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends ConsumerState<AddRecipeScreen> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<_IngredientEntry> _ingredients = [];
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    for (final e in _ingredients) { e.nameCtrl.dispose(); }
    super.dispose();
  }

  void _initFromRecipe(Recipe recipe) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = recipe.name;
    _notesCtrl.text = recipe.notes ?? '';
    for (final ing in recipe.ingredients) {
      _ingredients.add(_IngredientEntry(
        nameCtrl: TextEditingController(text: ing.name),
        quantity: ing.quantity,
        categoryId: ing.categoryId,
      ));
    }
  }

  void _addIngredient() {
    setState(() {
      _ingredients.add(_IngredientEntry(nameCtrl: TextEditingController()));
    });
  }

  void _removeIngredient(int index) {
    setState(() {
      _ingredients[index].nameCtrl.dispose();
      _ingredients.removeAt(index);
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _ingredients.isEmpty) return;

    final householdId = ref.read(householdIdProvider).value ?? '';
    final service = ref.read(recipesServiceProvider);
    final ingredients = _ingredients.map((e) => RecipeIngredient(
      name: e.nameCtrl.text.trim(),
      quantity: e.quantity,
      categoryId: e.categoryId,
    )).where((i) => i.name.isNotEmpty).toList();

    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    if (widget.recipeId != null) {
      await service.updateRecipe(
        householdId: householdId,
        recipeId: widget.recipeId!,
        name: name,
        ingredients: ingredients,
        notes: notes,
      );
    } else {
      await service.addRecipe(
        householdId: householdId,
        name: name,
        ingredients: ingredients,
        notes: notes,
      );
    }

    if (mounted) context.go('/recipes');
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? [];

    if (widget.recipeId != null) {
      final recipes = ref.watch(recipesProvider).value ?? [];
      final existing = recipes.where((r) => r.id == widget.recipeId).firstOrNull;
      if (existing != null) _initFromRecipe(existing);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipeId != null ? 'Edit Recipe' : 'New Recipe'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Recipe name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addIngredient,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          ..._ingredients.asMap().entries.map((entry) {
            final i = entry.key;
            final ing = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: ing.nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Ingredient ${i + 1}',
                        isDense: true,
                      ),
                      onChanged: (val) {
                        final guess = guessCategory(val, categories);
                        if (guess != null) {
                          setState(() => ing.categoryId = guess.id);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: Row(
                      children: [
                        InkWell(
                          onTap: ing.quantity > 1
                              ? () => setState(() => ing.quantity--)
                              : null,
                          child: const Icon(Icons.remove, size: 18),
                        ),
                        Expanded(
                          child: Text(
                            '${ing.quantity}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => ing.quantity++),
                          child: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeIngredient(i),
                  ),
                ],
              ),
            );
          }),
          if (_ingredients.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('Tap "Add" to add ingredients',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
        ],
      ),
    );
  }
}

class _IngredientEntry {
  final TextEditingController nameCtrl;
  int quantity;
  String? categoryId;

  _IngredientEntry({required this.nameCtrl, this.quantity = 1, this.categoryId});
}
