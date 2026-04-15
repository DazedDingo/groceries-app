import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/item.dart';
import '../../models/pantry_item.dart';
import '../../providers/items_provider.dart';
import '../../providers/pantry_provider.dart';

/// Snapshot of what changed when a shopping item was carted or deleted, so the
/// action can be undone.
class CartReceipt {
  final ShoppingItem originalItem;

  /// If we created a new pantry entry as part of carting (item was unlinked),
  /// this is its id so undo can remove it.
  final String? createdPantryItemId;

  const CartReceipt({required this.originalItem, this.createdPantryItemId});
}

/// Cart a shopping item using a [ProviderContainer] rather than a widget [Ref],
/// so the work survives screen disposal. Applies immediately and returns a
/// receipt the caller can pass to [undoCartDetached].
Future<CartReceipt> cartItemDetached(
  ProviderContainer container,
  String householdId,
  ShoppingItem item,
) async {
  String? createdPantryId;
  PantryItem? pantryItem;
  try {
    final pantryList = container.read(pantryProvider).value ?? [];
    if (item.pantryItemId != null) {
      // Explicitly linked — look up by ID. Don't create a new entry even if
      // the pantry stream hasn't loaded yet (item.pantryItemId is the link).
      pantryItem = pantryList.where((p) => p.id == item.pantryItemId).firstOrNull;
    } else {
      // No ID link — try name match first to avoid duplicates when units differ
      // (e.g. "cheese 1g" on the list vs "cheese 2x" already in pantry).
      pantryItem = pantryList
          .where((p) => p.name.toLowerCase() == item.name.toLowerCase())
          .firstOrNull;

      if (pantryItem == null) {
        // Genuinely new item — create a pantry entry. Optimal is only set when
        // the shopping item was flagged recurring; otherwise leave it 0 so the
        // restocker doesn't fire for one-off purchases.
        createdPantryId = await container.read(pantryServiceProvider).addItem(
          householdId: householdId,
          name: item.name,
          categoryId: item.categoryId,
          preferredStores: item.preferredStores,
          optimalQuantity: item.isRecurring ? item.quantity : 0,
          currentQuantity: item.quantity,
          unit: item.unit,
        );
      }
    }

    await container.read(itemsServiceProvider).checkOff(
      householdId: householdId,
      item: item,
      pantryItem: pantryItem,
    );
  } catch (_) {
    // Caller may already be disposed; nothing to surface.
  }
  return CartReceipt(originalItem: item, createdPantryItemId: createdPantryId);
}

/// Delete a shopping item in the same disposal-safe way; receipt lets the
/// caller undo by re-adding it.
Future<CartReceipt> deleteItemDetached(
  ProviderContainer container,
  String householdId,
  ShoppingItem item,
) async {
  try {
    await container.read(itemsServiceProvider).deleteItem(
      householdId: householdId,
      item: item,
    );
  } catch (_) {}
  return CartReceipt(originalItem: item);
}

/// Reverse a cart or delete: drop any pantry entry we created, re-add the
/// original shopping item.
Future<void> undoDetached(
  ProviderContainer container,
  String householdId,
  CartReceipt receipt,
) async {
  try {
    if (receipt.createdPantryItemId != null) {
      await container.read(pantryServiceProvider).deleteItem(
        householdId,
        receipt.createdPantryItemId!,
      );
    }
    final item = receipt.originalItem;
    await container.read(itemsServiceProvider).addItem(
      householdId: householdId,
      name: item.name,
      categoryId: item.categoryId,
      preferredStores: item.preferredStores,
      pantryItemId: item.pantryItemId,
      quantity: item.quantity,
      unit: item.unit,
      note: item.note,
      addedBy: item.addedBy,
    );
  } catch (_) {}
}
