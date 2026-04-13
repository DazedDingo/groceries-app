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
    for (final e in _ingredients) { e.nameCtrl.dispose(); e.qtyCtrl.dispose(); }
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
        unit: ing.unit,
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
      _ingredients[index].qtyCtrl.dispose();
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
      unit: e.unit,
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
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 80,
                    child: Row(
                      children: [
                        InkWell(
                          onTap: ing.quantity > 1
                              ? () => setState(() { ing.quantity--; ing.qtyCtrl.text = '${ing.quantity}'; })
                              : null,
                          child: const Icon(Icons.remove, size: 18),
                        ),
                        Expanded(
                          child: TextField(
                            controller: ing.qtyCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                              border: InputBorder.none,
                            ),
                            onChanged: (val) {
                              final n = int.tryParse(val);
                              if (n != null && n >= 1) setState(() => ing.quantity = n);
                            },
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() { ing.quantity++; ing.qtyCtrl.text = '${ing.quantity}'; }),
                          child: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 64,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: ing.unit,
                        isDense: true,
                        hint: const Text('unit', style: TextStyle(fontSize: 12)),
                        style: Theme.of(context).textTheme.bodySmall,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('—')),
                          DropdownMenuItem(value: 'g', child: Text('g')),
                          DropdownMenuItem(value: 'kg', child: Text('kg')),
                          DropdownMenuItem(value: 'ml', child: Text('ml')),
                          DropdownMenuItem(value: 'L', child: Text('L')),
                          DropdownMenuItem(value: 'oz', child: Text('oz')),
                          DropdownMenuItem(value: 'lb', child: Text('lb')),
                          DropdownMenuItem(value: 'cups', child: Text('cups')),
                          DropdownMenuItem(value: 'packs', child: Text('packs')),
                        ],
                        onChanged: (v) => setState(() => ing.unit = v),
                      ),
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
  final TextEditingController qtyCtrl;
  int quantity;
  String? unit;
  String? categoryId;

  _IngredientEntry({required this.nameCtrl, this.quantity = 1, this.unit, this.categoryId})
    : qtyCtrl = TextEditingController(text: '$quantity');
}
