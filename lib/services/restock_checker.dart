import '../models/pantry_item.dart';

/// Returns pantry items that are due for restocking based on their
/// [restockAfterDays] interval and [lastPurchasedAt] date.
List<PantryItem> findOverdueRestocks(List<PantryItem> pantryItems) {
  final now = DateTime.now();
  return pantryItems.where((item) {
    if (item.restockAfterDays == null) return false;
    if (!item.isBelowOptimal) return false;
    if (item.lastPurchasedAt == null) return true; // never purchased, below optimal
    final daysSince = now.difference(item.lastPurchasedAt!).inDays;
    return daysSince >= item.restockAfterDays!;
  }).toList();
}
