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
          if (item.isHighPriority) ...[
            const SizedBox(width: 6),
            const Icon(Icons.star, size: 16, color: Colors.amber),
          ],
          if (item.isBelowOptimal) ...[
            const SizedBox(width: 6),
            Icon(Icons.warning_amber, size: 16, color: scheme.error),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${item.currentQuantity} / ${item.optimalQuantity} optimal'),
              if (item.location != null) ...[
                const SizedBox(width: 8),
                Icon(_iconForLocation(item.location),
                    size: 12, color: scheme.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(_labelForLocation(item.location),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
              ],
            ],
          ),
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

  IconData _iconForLocation(String? location) {
    switch (PantryLocation.fromId(location)) {
      case PantryLocation.fridge:
        return Icons.kitchen;
      case PantryLocation.freezer:
        return Icons.ac_unit;
      case PantryLocation.pantry:
        return Icons.shelves;
      case PantryLocation.counter:
        return Icons.countertops;
      case PantryLocation.other:
      case null:
        return Icons.place_outlined;
    }
  }

  String _labelForLocation(String? location) {
    if (location == null) return '';
    return PantryLocation.fromId(location)?.label ?? location;
  }
}
