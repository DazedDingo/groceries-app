import 'package:flutter/material.dart';
import '../../../models/pantry_item.dart';

class PantryItemTile extends StatelessWidget {
  final PantryItem item;
  final String categoryName;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onAddToList;
  final VoidCallback onTap;

  const PantryItemTile({
    super.key, required this.item, required this.categoryName,
    required this.onDecrement, required this.onIncrement,
    required this.onAddToList, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Expanded(child: Text(item.name)),
          const SizedBox(width: 8),
          Chip(
            label: Text(categoryName,
                style: Theme.of(context).textTheme.labelSmall),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          if (item.isBelowOptimal) ...[
            const SizedBox(width: 6),
            Icon(Icons.warning_amber, size: 16, color: scheme.error),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${item.currentQuantity} / ${item.optimalQuantity} optimal'),
          if (item.isBelowOptimal)
            TextButton.icon(
              onPressed: onAddToList,
              icon: const Icon(Icons.add_shopping_cart, size: 16),
              label: const Text('Add to list'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: onDecrement,
            visualDensity: VisualDensity.compact,
          ),
          Text('${item.currentQuantity}', style: const TextStyle(fontSize: 16)),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: onIncrement,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
