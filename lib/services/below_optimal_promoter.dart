import '../models/pantry_item.dart';
import '../models/item.dart';

/// Result of [decideBelowOptimalAutoAdd]. When [shouldAdd] is true, the
/// caller should add a shopping-list item with the given [qtyToAdd].
class BelowOptimalDecision {
  final bool shouldAdd;
  final int qtyToAdd;
  final String reasonSkipped;
  const BelowOptimalDecision._({
    required this.shouldAdd,
    required this.qtyToAdd,
    this.reasonSkipped = '',
  });

  static BelowOptimalDecision skip(String why) =>
      BelowOptimalDecision._(shouldAdd: false, qtyToAdd: 0, reasonSkipped: why);

  static BelowOptimalDecision add(int qty) =>
      BelowOptimalDecision._(shouldAdd: true, qtyToAdd: qty);
}

/// Pure decision: should the just-decremented [item] be auto-added to the
/// shopping list, and at what quantity?
///
/// Fires when:
///   - `priorCurrent` was at-or-above optimalQuantity, AND
///   - decrementing dropped it below optimalQuantity, AND
///   - the item isn't already on the shopping list (matched by either
///     `pantryItemId` OR a case-insensitive name match — manual adds
///     don't always carry pantryItemId, so we cover both).
///
/// Quantity = clamp(optimal − newCurrent, 1, 999) so the buy refills to
/// optimal exactly.
BelowOptimalDecision decideBelowOptimalAutoAdd({
  required PantryItem item,
  required int priorCurrent,
  required List<ShoppingItem> shoppingList,
}) {
  final optimal = item.optimalQuantity;
  if (optimal <= 0) return BelowOptimalDecision.skip('optimal is zero');
  final newCurrent = priorCurrent - 1;
  // "Crossed below optimal on this decrement" — was at-or-above before,
  // strictly below after. The earlier `priorCurrent == optimal` was
  // mathematically correct for integers (priorCurrent >= optimal &&
  // newCurrent < optimal collapses to priorCurrent == optimal), but the
  // explicit form makes the intent obvious and catches non-integer drift
  // if the type ever widens.
  final crossed = priorCurrent >= optimal && newCurrent < optimal;
  if (!crossed) return BelowOptimalDecision.skip('did not cross threshold');

  final lowerName = item.name.toLowerCase().trim();
  final alreadyOnList = shoppingList.any((s) =>
      s.pantryItemId == item.id ||
      s.name.toLowerCase().trim() == lowerName);
  if (alreadyOnList) return BelowOptimalDecision.skip('already on list');

  final qty = (optimal - newCurrent).clamp(1, 999).toInt();
  return BelowOptimalDecision.add(qty);
}
