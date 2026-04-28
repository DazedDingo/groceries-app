import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/item.dart';
import '../../../services/unit_converter.dart';
import '../cart_action.dart';

class ItemTile extends StatefulWidget {
  final ShoppingItem item;
  final Future<CartReceipt> Function() onCheckOff;
  final Future<CartReceipt> Function() onDelete;
  final Future<void> Function(CartReceipt receipt) onUndo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelecting;
  final bool isSelected;
  final bool isHighPriority;
  final UnitSystem unitSystem;

  const ItemTile({
    super.key,
    required this.item,
    required this.onCheckOff,
    required this.onDelete,
    required this.onUndo,
    required this.onTap,
    required this.onLongPress,
    this.isSelecting = false,
    this.isSelected = false,
    this.isHighPriority = false,
    this.unitSystem = UnitSystem.metric,
  });

  @override
  State<ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends State<ItemTile> {
  bool _pendingAction = false;

  ShoppingItem get item => widget.item;

  IconData _sourceIcon() => switch (item.addedBy.source) {
    ItemSource.googleHome => Icons.home,
    ItemSource.voiceInApp => Icons.mic,
    ItemSource.app => Icons.phone_android,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qtyLabel = formatQuantityUnit(item.quantity, item.unit, widget.unitSystem);

    final hasNote = item.note != null && item.note!.isNotEmpty;
    final hasRecipe = item.recipeSource != null;
    final metaLine = qtyLabel.isEmpty
        ? item.addedBy.displayName
        : '${item.addedBy.displayName} · $qtyLabel';

    final tile = ListTile(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      selected: widget.isSelected,
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 0,
      leading: widget.isSelecting
          ? Checkbox(value: widget.isSelected, onChanged: (_) => widget.onTap())
          : null,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text.rich(
        TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(text: metaLine),
            if (hasNote) TextSpan(text: ' · ${item.note!}'),
            if (hasRecipe)
              TextSpan(
                text: ' · from ${item.recipeSource}',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isHighPriority)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.star, size: 14, color: Colors.amber),
            ),
          if (item.fromRunningLow)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Auto-added: pantry was running low',
                child: Icon(
                  Icons.trending_down,
                  size: 14,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
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

    if (widget.isSelecting) return tile;

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
      confirmDismiss: (dir) async {
        if (_pendingAction) return false;
        HapticFeedback.mediumImpact();
        setState(() => _pendingAction = true);

        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();

        final isCart = dir == DismissDirection.startToEnd;
        final receipt = isCart ? await widget.onCheckOff() : await widget.onDelete();

        // Short secondary confirm haptic on successful check-off —
        // pairs with the initial mediumImpact for a "tick" feel.
        if (isCart) HapticFeedback.selectionClick();

        if (mounted) setState(() => _pendingAction = false);

        final action = isCart ? 'Marked as bought' : 'Deleted';
        messenger.showSnackBar(SnackBar(
          content: Text('$action "${item.name}"'),
          duration: const Duration(milliseconds: 1500),
          // Material 3 keeps action-bearing snackbars open indefinitely
          // by default — we want auto-dismiss here.
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.onUndo(receipt),
          ),
        ));

        return true;
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        scale: _pendingAction ? 0.96 : 1.0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _pendingAction ? 0.6 : 1.0,
          child: tile,
        ),
      ),
    );
  }
}
