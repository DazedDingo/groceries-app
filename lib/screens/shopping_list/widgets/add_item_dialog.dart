import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/category.dart';
import '../../../services/category_guesser.dart';
import '../../../services/suggestion_ranker.dart';

class AddItemResult {
  final String name;
  final GroceryCategory? category;
  final int quantity;
  final String? unit;
  final String? note;
  final bool categoryOverridden;
  final bool isRecurring;
  AddItemResult({required this.name, required this.category, required this.quantity, this.unit, this.note, this.categoryOverridden = false, this.isRecurring = false});
}

class AddItemDialog extends StatefulWidget {
  final String initialName;
  final List<GroceryCategory> categories;
  final GroceryCategory? initialCategory;
  /// Ranker-scored candidates. Replaces the old split currentList/history/
  /// pantry lists — callers assemble one unified list and the ranker orders it.
  final List<SuggestionItem> suggestions;
  final Map<String, String> categoryOverrides;

  const AddItemDialog({
    super.key,
    this.initialName = '',
    required this.categories,
    this.initialCategory,
    this.suggestions = const [],
    this.categoryOverrides = const {},
  });

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _noteCtrl;
  GroceryCategory? _category;
  bool _categoryManuallyChanged = false;
  int _quantity = 1;
  String? _unit;
  bool _isRecurring = false;
  late String _nameText;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '1');
    _noteCtrl = TextEditingController();
    _category = widget.initialCategory;
    _nameText = widget.initialName;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _setQuantity(int val) {
    final clamped = val.clamp(1, 9999);
    HapticFeedback.selectionClick();
    setState(() => _quantity = clamped);
    if (_qtyCtrl.text != '$clamped') _qtyCtrl.text = '$clamped';
  }

  void _onNameChanged(String val) {
    final guess = guessCategory(val, widget.categories, widget.categoryOverrides);
    setState(() {
      _nameText = val;
      if (guess != null && !_categoryManuallyChanged) _category = guess;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add item'),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Autocomplete<String>(
          initialValue: TextEditingValue(text: widget.initialName),
          optionsViewOpenDirection: OptionsViewOpenDirection.up,
          optionsBuilder: (textEditingValue) {
            final raw = textEditingValue.text;
            if (raw.isEmpty) return const Iterable.empty();
            return rankSuggestions(
              widget.suggestions,
              raw,
              DateTime.now(),
            );
          },
          onSelected: _onNameChanged,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(labelText: 'Item name', isDense: true),
              autofocus: widget.initialName.isEmpty,
              onChanged: _onNameChanged,
            );
          },
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Category'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<GroceryCategory>(
              value: _category,
              isExpanded: true,
              hint: const Text('Uncategorised'),
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                  .toList(),
              onChanged: (c) => setState(() {
                _category = c;
                _categoryManuallyChanged = true;
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Quantity'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: _quantity > 1 ? () => _setQuantity(_quantity - 1) : null,
            ),
            SizedBox(
              width: 56,
              child: TextField(
                controller: _qtyCtrl,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: Theme.of(context).textTheme.titleMedium,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  final n = int.tryParse(val);
                  if (n != null && n >= 1) setState(() => _quantity = n);
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _setQuantity(_quantity + 1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: _unit,
          decoration: const InputDecoration(labelText: 'Unit (optional)', isDense: true),
          items: const [
            DropdownMenuItem(value: null, child: Text('None (qty)')),
            DropdownMenuItem(value: 'g', child: Text('g')),
            DropdownMenuItem(value: 'kg', child: Text('kg')),
            DropdownMenuItem(value: 'ml', child: Text('ml')),
            DropdownMenuItem(value: 'L', child: Text('L')),
            DropdownMenuItem(value: 'oz', child: Text('oz')),
            DropdownMenuItem(value: 'lb', child: Text('lb')),
            DropdownMenuItem(value: 'cups', child: Text('cups')),
            DropdownMenuItem(value: 'packs', child: Text('packs')),
            DropdownMenuItem(value: 'bags', child: Text('bags')),
            DropdownMenuItem(value: 'bottles', child: Text('bottles')),
            DropdownMenuItem(value: 'cans', child: Text('cans')),
            DropdownMenuItem(value: 'dozen', child: Text('dozen')),
            DropdownMenuItem(value: 'loaves', child: Text('loaves')),
            DropdownMenuItem(value: 'bunches', child: Text('bunches')),
          ],
          onChanged: (v) => setState(() => _unit = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'e.g. brand, size, type',
            isDense: true,
          ),
          maxLines: 1,
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _isRecurring,
          onChanged: (v) => setState(() => _isRecurring = v),
          title: const Text('Is recurring?'),
          subtitle: const Text('Sets optimal quantity for restock alerts'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameText.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    AddItemResult(
                      name: _nameText.trim(),
                      category: _category,
                      quantity: _quantity,
                      unit: _unit,
                      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                      categoryOverridden: _categoryManuallyChanged,
                      isRecurring: _isRecurring,
                    ),
                  ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
