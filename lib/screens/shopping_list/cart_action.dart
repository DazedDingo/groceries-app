import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/item.dart';
import '../../models/pantry_item.dart';
import '../../providers/items_provider.dart';
import '../../providers/pantry_provider.dart';

/// Cart a shopping item using a [ProviderContainer] rather than a widget [Ref],
/// so the work survives screen disposal (e.g. user navigates away during the
/// snackbar undo window).
Future<void> cartItemDetached(
  ProviderContainer container,
  String householdId,
  ShoppingItem item,
) async {
  try {
    final pantryList = container.read(pantryProvider).value ?? [];
    PantryItem? pantryItem;

    if (item.pantryItemId != null) {
      try {
        pantryItem = pantryList.firstWhere((p) => p.id == item.pantryItemId);
      } catch (_) {}
    } else {
      await container.read(pantryServiceProvider).addItem(
        householdId: householdId,
        name: item.name,
        categoryId: item.categoryId,
        preferredStores: item.preferredStores,
        optimalQuantity: item.quantity,
        currentQuantity: item.quantity,
      );
    }

    await container.read(itemsServiceProvider).checkOff(
      householdId: householdId,
      item: item,
      pantryItem: pantryItem,
    );
  } catch (_) {
    // Caller may already be disposed; nothing to surface.
  }
}
