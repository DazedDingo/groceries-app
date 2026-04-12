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
          Text(item.name),
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
      subtitle: Text('${item.currentQuantity} / ${item.optimalQuantity} optimal'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.remove), onPressed: onDecrement),
          Text('${item.currentQuantity}', style: const TextStyle(fontSize: 16)),
          IconButton(icon: const Icon(Icons.add), onPressed: onIncrement),
          if (item.isBelowOptimal)
            Flexible(
              child: TextButton(onPressed: onAddToList, child: const Text('Add to list')),
            ),
        ],
      ),
    );
  }
}
