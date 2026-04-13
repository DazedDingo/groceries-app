import 'package:flutter/material.dart';
import '../../../models/item.dart';
import '../../../services/unit_converter.dart';

class ItemTile extends StatelessWidget {
  final ShoppingItem item;
  final VoidCallback onCheckOff;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelecting;
  final bool isSelected;
  final UnitSystem unitSystem;

  const ItemTile({
    super.key,
    required this.item,
    required this.onCheckOff,
    required this.onDelete,
    required this.onTap,
    required this.onLongPress,
    this.isSelecting = false,
    this.isSelected = false,
    this.unitSystem = UnitSystem.metric,
  });

  IconData _sourceIcon() => switch (item.addedBy.source) {
    ItemSource.googleHome => Icons.home,
    ItemSource.voiceInApp => Icons.mic,
    ItemSource.app => Icons.phone_android,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qtyLabel = formatQuantityUnit(item.quantity, item.unit, unitSystem);

    final tile = ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: isSelected,
      leading: isSelecting
          ? Checkbox(value: isSelected, onChanged: (_) => onTap())
          : null,
      title: Text(item.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(qtyLabel.isEmpty
              ? item.addedBy.displayName
              : '${item.addedBy.displayName} · $qtyLabel'),
          if (item.recipeSource != null)
            Text(
              'from ${item.recipeSource}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.pantryItemId != null)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Linked to pantry',
                child: Icon(Icons.kitchen, size: 14),
              ),
            ),
          Icon(_sourceIcon(), size: 16),
        ],
      ),
    );

    if (isSelecting) return tile;

    return Dismissible(
      key: Key(item.id),
      background: Container(
        color: Colors.green, alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.add_shopping_cart, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red, alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (dir) => dir == DismissDirection.startToEnd ? onCheckOff() : onDelete(),
      child: tile,
    );
  }
}
