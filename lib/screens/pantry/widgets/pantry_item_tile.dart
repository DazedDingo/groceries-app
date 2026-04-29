import 'package:flutter/material.dart';
import '../../../models/pantry_item.dart';

/// Single-line, dense pantry row.
///
/// Earlier revisions used a ListTile with title + subtitle + button row +
/// inc/dec trailing — three visual rows per item, ~88 px each. That made
/// a typical pantry of 30+ items feel like a long scroll. Compacted to a
/// single-line tile (~40 px): name, status icons, qty, and a single +
/// button for the most common interaction. The detail screen still has
/// the full set of actions (decrement, mark running-low, add to list,
/// per-container info, location picker) — tap the row to open it.
class PantryItemTile extends StatelessWidget {
  final PantryItem item;

  /// Kept on the API for parity with the screen call site, but no longer
  /// rendered — the pantry screen already groups by category, so a
  /// per-row chip was duplicating context.
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
    super.key,
    required this.item,
    required this.categoryName,
    required this.onDecrement,
    required this.onIncrement,
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
    final theme = Theme.of(context);
    final qtyColor =
        item.isBelowOptimal ? scheme.error : scheme.onSurfaceVariant;
    // Hairline bottom border so consecutive dense tiles don't blur into
    // a single visual blob. outlineVariant is Material 3's spec-defined
    // hue for "minimal-prominence dividers" — it reads as a separator
    // without competing with the section-header text above each block.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
      ),
      child: ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: isSelected,
      dense: true,
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      minVerticalPadding: 0,
      leading: isSelecting
          ? Checkbox(value: isSelected, onChanged: (_) => onTap())
          : null,
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (item.isHighPriority) ...[
            const SizedBox(width: 4),
            const Icon(Icons.star, size: 14, color: Colors.amber),
          ],
          if (item.runningLowAt != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.trending_down,
                size: 14, color: scheme.onSecondaryContainer),
          ],
          if (item.location != null) ...[
            const SizedBox(width: 4),
            Icon(_iconForLocation(item.location),
                size: 14, color: scheme.onSurfaceVariant),
          ],
          const SizedBox(width: 8),
          Text(
            '${item.currentQuantity}/${item.optimalQuantity}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: qtyColor,
              fontWeight:
                  item.isBelowOptimal ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
      trailing: isSelecting
          ? null
          : IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'Add one',
              onPressed: onIncrement,
              visualDensity:
                  const VisualDensity(horizontal: -2, vertical: -2),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
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
}

