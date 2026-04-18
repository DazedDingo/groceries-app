import '../models/pantry_item.dart';

/// Pantry items flagged for the launch-time expiry banner: currently below
/// optimal AND either already expired or within the "expiring soon" window.
///
/// Sub-optimal filter keeps the banner actionable — you can only really
/// respond by buying more, and restocking a fully-stocked item makes no sense.
List<PantryItem> findExpiringBelowOptimal(
  List<PantryItem> pantryItems, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  return pantryItems.where((p) {
    if (!p.isBelowOptimal) return false;
    final expires = p.expiresAt;
    if (expires == null) return false;
    if (ref.isAfter(expires)) return true;
    return expires.difference(ref).inDays <= 2;
  }).toList();
}

/// Stable fingerprint of the flagged set. Used by the dismiss-until-changes
/// logic: we remember the fingerprint the user last dismissed and only
/// re-surface the banner when the fingerprint differs (new item flagged,
/// an item's expiry moved, an item left or re-entered the set).
String expiringFingerprint(List<PantryItem> flagged) {
  final parts = flagged
      .map((p) =>
          '${p.id}|${p.expiresAt?.toIso8601String() ?? ''}|${p.currentQuantity}|${p.optimalQuantity}')
      .toList()
    ..sort();
  return parts.join(';');
}
