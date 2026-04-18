import 'package:flutter/material.dart';
import '../../../models/pantry_item.dart';
import '../../../services/running_low_promoter.dart';

class PantryItemTile extends StatelessWidget {
  final PantryItem item;
  final String categoryName;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onAddToList;
  final VoidCallback onMarkRunningLow;
  final VoidCallback onClearRunningLow;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelecting;
  final bool isSelected;

  const PantryItemTile({
    super.key, required this.item, required this.categoryName,
    required this.onDecrement, required this.onIncrement,
    required this.onAddToList,
    required this.onMarkRunningLow,
    required this.onClearRunningLow,
    required this.onTap,
    this.onLongPress,
    this.isSelecting = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: isSelected,
      leading: isSelecting
          ? Checkbox(value: isSelected, onChanged: (_) => onTap())
          : null,
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
              if (_formatPerContainer(item).isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('· ${_formatPerContainer(item)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
              ],
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
          Wrap(
            spacing: 8,
            children: [
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
              if (item.runningLowAt == null)
                Tooltip(
                  message:
                      'Adds to list in 2 days and drops this count by 1',
                  child: TextButton.icon(
                    onPressed: onMarkRunningLow,
                    icon: const Icon(Icons.trending_down, size: 16),
                    label: const Text('Running low'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                )
              else
                _RunningLowChip(
                  flaggedAt: item.runningLowAt!,
                  onClear: onClearRunningLow,
                ),
            ],
          ),
        ],
      ),
      trailing: isSelecting
          ? null
          : Row(
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

  String _formatPerContainer(PantryItem p) {
    final amt = p.unitAmount;
    final u = p.unit?.trim();
    if (amt != null && amt > 0 && u != null && u.isNotEmpty) {
      final n = amt == amt.roundToDouble() ? amt.toInt().toString() : amt.toString();
      return '$n$u';
    }
    if (amt != null && amt > 0) {
      return amt == amt.roundToDouble() ? amt.toInt().toString() : amt.toString();
    }
    if (u != null && u.isNotEmpty) return u;
    return '';
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

class _RunningLowChip extends StatelessWidget {
  final DateTime flaggedAt;
  final VoidCallback onClear;
  const _RunningLowChip({required this.flaggedAt, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dueAt = flaggedAt.add(runningLowDelay);
    final daysLeft = dueAt.difference(DateTime.now()).inDays;
    final label = daysLeft <= 0
        ? 'Running low — adding next open'
        : 'Running low — adds in ${daysLeft + 1}d';
    return InputChip(
      avatar: Icon(Icons.trending_down, size: 14, color: scheme.onSecondaryContainer),
      label: Text(label, style: Theme.of(context).textTheme.labelSmall),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 14),
      deleteButtonTooltipMessage: 'Cancel running-low',
      backgroundColor: scheme.secondaryContainer,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
