import '../models/item.dart';
import '../models/pantry_item.dart';

/// Grace period between a "running low" tap and the item being auto-added to
/// the shopping list. Keeps accidental taps recoverable via the undo snackbar
/// while still being short enough that a single press meaningfully replaces
/// the "tap again later to add" workflow.
const Duration runningLowDelay = Duration(days: 2);

/// Returns the pantry items whose `runningLowAt` flag is ready to be promoted
/// to the shopping list: flagged ≥ [delay] ago and not already linked to a
/// shopping-list entry. Called on pantry screen open, so the promotion happens
/// lazily without a scheduled backend job.
List<PantryItem> itemsDueForPromotion({
  required List<PantryItem> pantry,
  required List<ShoppingItem> shoppingList,
  required DateTime now,
  Duration delay = runningLowDelay,
}) {
  final linkedIds = shoppingList
      .where((i) => i.pantryItemId != null)
      .map((i) => i.pantryItemId!)
      .toSet();
  return pantry.where((p) {
    final flagged = p.runningLowAt;
    if (flagged == null) return false;
    if (linkedIds.contains(p.id)) return false;
    return now.difference(flagged) >= delay;
  }).toList();
}
