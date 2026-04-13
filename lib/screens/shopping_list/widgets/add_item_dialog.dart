import 'package:flutter/material.dart';
import '../../../models/category.dart';
import '../../../services/category_guesser.dart';

class AddItemResult {
  final String name;
  final GroceryCategory? category;
  final int quantity;
  final String? unit;
  final String? note;
  AddItemResult({required this.name, required this.category, required this.quantity, this.unit, this.note});
}

class AddItemDialog extends StatefulWidget {
  final String initialName;
  final List<GroceryCategory> categories;
  final GroceryCategory? initialCategory;
  final List<String> historySuggestions;

  const AddItemDialog({
    super.key,
    this.initialName = '',
    required this.categories,
    this.initialCategory,
    this.historySuggestions = const [],
  });

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  // Autocomplete manages its own controller; we only keep a reference to read from it.
  TextEditingController? _autocompleteCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _noteCtrl;
  GroceryCategory? _category;
  int _quantity = 1;
  String? _unit;

  String get _nameText => _autocompleteCtrl?.text ?? '';

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '1');
    _noteCtrl = TextEditingController();
    _category = widget.initialCategory;
  }

  @override
  void dispose() {
    // Do NOT dispose _autocompleteCtrl — Autocomplete owns it.
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _setQuantity(int val) {
    final clamped = val.clamp(1, 9999);
    setState(() => _quantity = clamped);
    if (_qtyCtrl.text != '$clamped') _qtyCtrl.text = '$clamped';
  }

  void _onNameChanged(String val) {
    final guess = guessCategory(val, widget.categories);
    setState(() {
      if (guess != null && guess != _category) _category = guess;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add item'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Autocomplete<String>(
          initialValue: TextEditingValue(text: widget.initialName),
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) return const Iterable.empty();
            final query = textEditingValue.text.toLowerCase();
            return widget.historySuggestions
                .where((s) => s.toLowerCase().contains(query));
          },
          onSelected: (selection) {
            _onNameChanged(selection);
            setState(() {});
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            _autocompleteCtrl = controller;
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(labelText: 'Item name'),
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
              onChanged: (c) => setState(() => _category = c),
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
                    ),
                  ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
