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
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RunningLowToggle(
                  flagged: item.runningLowAt != null,
                  onMark: onMarkRunningLow,
                  onClear: onClearRunningLow,
                ),
                _CompactIconButton(
                  icon: Icons.remove,
                  tooltip: 'Use one',
                  onPressed:
                      item.currentQuantity > 0 ? onDecrement : null,
                ),
                _CompactIconButton(
                  icon: Icons.add,
                  tooltip: 'Add one',
                  onPressed: onIncrement,
                ),
              ],
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

/// Tight 32×32 icon button used three times in the trailing row. The
/// stock IconButton's default 48×48 hit-target was the bulk of the
/// pre-compaction tile height; these constraints keep tap reliability
/// while letting three buttons line up under a 100 px-wide trailing
/// slot on a 360 dp phone.
class _CompactIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  const _CompactIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

/// Two-state running-low toggle for the pantry tile's trailing row.
/// Outline + neutral when not flagged (tap → mark); filled-secondary
/// + tinted when flagged (tap → clear). Same 32×32 footprint as the
/// inc/dec siblings so the trailing row stays uniform; the colour
/// flip is what communicates "this is queued to land on the list".
class _RunningLowToggle extends StatelessWidget {
  final bool flagged;
  final VoidCallback onMark;
  final VoidCallback onClear;
  const _RunningLowToggle({
    required this.flagged,
    required this.onMark,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CompactIconButton(
      icon: Icons.trending_down,
      tooltip: flagged
          ? 'Cancel running-low'
          : 'Running low — adds to list in 2 days',
      color: flagged ? scheme.onSecondaryContainer : null,
      onPressed: flagged ? onClear : onMark,
    );
  }
}

