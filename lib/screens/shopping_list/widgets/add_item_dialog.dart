import 'package:flutter/material.dart';
import '../../../models/category.dart';
import '../../../services/category_guesser.dart';

class AddItemResult {
  final String name;
  final GroceryCategory? category;
  final int quantity;
  final String? unit;
  AddItemResult({required this.name, required this.category, required this.quantity, this.unit});
}

class AddItemDialog extends StatefulWidget {
  final String initialName;
  final List<GroceryCategory> categories;
  final GroceryCategory? initialCategory;

  const AddItemDialog({
    super.key,
    this.initialName = '',
    required this.categories,
    this.initialCategory,
  });

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  GroceryCategory? _category;
  int _quantity = 1;
  String? _unit;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _qtyCtrl = TextEditingController(text: '1');
    _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
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
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'Item name'),
          autofocus: widget.initialName.isEmpty,
          onChanged: _onNameChanged,
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
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameCtrl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    AddItemResult(
                      name: _nameCtrl.text.trim(),
                      category: _category,
                      quantity: _quantity,
                      unit: _unit,
                    ),
                  ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
