import '../models/history_entry.dart';

/// Collects the timestamps of 'bought' events in [history] whose item name
/// matches [itemName] (case-insensitive, trimmed).
List<DateTime> purchaseDatesFor(List<HistoryEntry> history, String itemName) {
  final needle = itemName.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  return history
      .where((h) =>
          h.action == HistoryAction.bought &&
          h.itemName.trim().toLowerCase() == needle)
      .map((h) => h.at)
      .toList();
}

/// Median days between consecutive purchases in [purchaseDates], or null if
/// fewer than 3 purchases are present (need ≥2 gaps for a stable median).
///
/// Rationale: days-between-repurchases is a household-specific proxy for how
/// fast an item actually gets consumed — more trustworthy than a generic
/// category/name default once enough data exists.
int? learnedShelfLifeDays(List<DateTime> purchaseDates) {
  if (purchaseDates.length < 3) return null;
  final sorted = [...purchaseDates]..sort();
  final gaps = <int>[];
  for (var i = 1; i < sorted.length; i++) {
    final days = sorted[i].difference(sorted[i - 1]).inDays;
    if (days > 0) gaps.add(days);
  }
  if (gaps.length < 2) return null;
  gaps.sort();
  final mid = gaps.length ~/ 2;
  final median = gaps.length.isOdd
      ? gaps[mid]
      : ((gaps[mid - 1] + gaps[mid]) / 2).round();
  return median > 0 ? median : null;
}
