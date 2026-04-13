import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/categories_provider.dart';
import '../../models/recipe.dart';
import '../../services/category_guesser.dart';
import '../../services/text_item_parser.dart';
import '../../services/recipe_import_service.dart';

class AddRecipeScreen extends ConsumerStatefulWidget {
  final String? recipeId;
  final bool autoImport;
  const AddRecipeScreen({super.key, this.recipeId, this.autoImport = false});

  @override
  ConsumerState<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends ConsumerState<AddRecipeScreen> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _sourceUrlCtrl = TextEditingController();
  final List<_IngredientEntry> _ingredients = [];
  final List<TextEditingController> _instructions = [];
  bool _initialized = false;
  bool _importing = false;
  bool _autoImportTriggered = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoImport) {
      // Schedule import dialog after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_autoImportTriggered) {
          _autoImportTriggered = true;
          _importFromUrl();
        }
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _sourceUrlCtrl.dispose();
    for (final e in _ingredients) { e.nameCtrl.dispose(); e.qtyCtrl.dispose(); }
    for (final c in _instructions) { c.dispose(); }
    super.dispose();
  }

  void _initFromRecipe(Recipe recipe) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = recipe.name;
    _notesCtrl.text = recipe.notes ?? '';
    _sourceUrlCtrl.text = recipe.sourceUrl ?? '';
    for (final ing in recipe.ingredients) {
      _ingredients.add(_IngredientEntry(
        nameCtrl: TextEditingController(text: ing.name),
        quantity: ing.quantity,
        unit: ing.unit,
        categoryId: ing.categoryId,
      ));
    }
    for (final step in recipe.instructions) {
      _instructions.add(TextEditingController(text: step));
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

  void _addInstruction() {
    setState(() {
      _instructions.add(TextEditingController());
    });
  }

  void _removeInstruction(int index) {
    setState(() {
      _instructions[index].dispose();
      _instructions.removeAt(index);
    });
  }

  Future<void> _bulkAddIngredients() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste ingredients'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'One per line, e.g.:\n2 kg chicken\n200 g pasta\n1 can tomatoes',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.trim().isEmpty) return;

    final categories = ref.read(categoriesProvider).value ?? [];
    final parsed = parseTextLines(text);
    setState(() {
      for (final item in parsed) {
        final cat = guessCategory(item.name, categories);
        _ingredients.add(_IngredientEntry(
          nameCtrl: TextEditingController(text: item.name),
          quantity: item.quantity,
          unit: item.unit,
          categoryId: cat?.id,
        ));
      }
    });
  }

  Future<void> _bulkAddInstructions() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste instructions'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'One step per line:\nPreheat oven to 180C\nChop the onions\nMix everything together',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.trim().isEmpty) return;

    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    setState(() {
      for (final line in lines) {
        _instructions.add(TextEditingController(text: line));
      }
    });
  }

  Future<void> _importFromUrl() async {
    final urlCtrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import recipe from URL'),
        content: TextField(
          controller: urlCtrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://www.example.com/recipe/...',
            prefixIcon: Icon(Icons.link),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, urlCtrl.text), child: const Text('Import')),
        ],
      ),
    );
    urlCtrl.dispose();
    if (url == null || url.trim().isEmpty) return;

    setState(() => _importing = true);
    try {
      final imported = await RecipeImportService().importFromUrl(url.trim());
      final categories = ref.read(categoriesProvider).value ?? [];

      setState(() {
        _nameCtrl.text = imported.name;
        if (imported.notes != null && imported.notes!.isNotEmpty) {
          _notesCtrl.text = imported.notes!;
        }
        _sourceUrlCtrl.text = imported.sourceUrl ?? url.trim();

        // Clear existing and populate
        for (final e in _ingredients) { e.nameCtrl.dispose(); e.qtyCtrl.dispose(); }
        _ingredients.clear();
        for (final ing in imported.ingredients) {
          final cat = guessCategory(ing.name, categories);
          _ingredients.add(_IngredientEntry(
            nameCtrl: TextEditingController(text: ing.name),
            quantity: ing.quantity,
            unit: ing.unit,
            categoryId: cat?.id ?? ing.categoryId,
          ));
        }

        for (final c in _instructions) { c.dispose(); }
        _instructions.clear();
        for (final step in imported.instructions) {
          _instructions.add(TextEditingController(text: step));
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Imported "${imported.name}" with '
              '${imported.ingredients.length} ingredients and '
              '${imported.instructions.length} steps'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      setState(() => _importing = false);
    }
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

    final instructions = _instructions
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    final sourceUrl = _sourceUrlCtrl.text.trim().isEmpty ? null : _sourceUrlCtrl.text.trim();

    if (widget.recipeId != null) {
      await service.updateRecipe(
        householdId: householdId,
        recipeId: widget.recipeId!,
        name: name,
        ingredients: ingredients,
        instructions: instructions,
        notes: notes,
        sourceUrl: sourceUrl,
      );
    } else {
      await service.addRecipe(
        householdId: householdId,
        name: name,
        ingredients: ingredients,
        instructions: instructions,
        notes: notes,
        sourceUrl: sourceUrl,
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
          if (widget.recipeId == null)
            IconButton(
              icon: const Icon(Icons.link),
              onPressed: _importing ? null : _importFromUrl,
              tooltip: 'Import from URL',
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: _importing
          ? const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Importing recipe...'),
              ],
            ))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Recipe name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Description (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Ingredients section
                Row(
                  children: [
                    Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _bulkAddIngredients,
                      icon: const Icon(Icons.content_paste, size: 18),
                      label: const Text('Paste'),
                    ),
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
                      child: Text('Tap "Add" or "Paste" to add ingredients',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ),

                const SizedBox(height: 24),

                // Instructions section
                Row(
                  children: [
                    Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _bulkAddInstructions,
                      icon: const Icon(Icons.content_paste, size: 18),
                      label: const Text('Paste'),
                    ),
                    TextButton.icon(
                      onPressed: _addInstruction,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                ..._instructions.asMap().entries.map((entry) {
                  final i = entry.key;
                  final ctrl = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, right: 8),
                          child: Text(
                            '${i + 1}.',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            maxLines: null,
                            decoration: InputDecoration(
                              hintText: 'Step ${i + 1}',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _removeInstruction(i),
                        ),
                      ],
                    ),
                  );
                }),
                if (_instructions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('Tap "Add" or "Paste" to add steps (optional)',
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
