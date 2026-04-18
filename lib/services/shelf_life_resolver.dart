import '../models/history_entry.dart';
import 'shelf_life_guesser.dart';
import 'shelf_life_learner.dart';

/// Resolve a shelf-life in days using the most specific signal available,
/// in this order:
/// 1. Household-learned median (needs ≥3 recorded purchases of [itemName]).
/// 2. Per-item keyword table (e.g. "cheddar" → 60).
/// 3. Category fallback (e.g. "Dairy" → 10).
///
/// Returns null when none of the layers produces a value.
int? resolveShelfLifeDays({
  required String itemName,
  required String? categoryName,
  required List<HistoryEntry> history,
}) {
  final learned = learnedShelfLifeDays(purchaseDatesFor(history, itemName));
  if (learned != null) return learned;
  return guessShelfLifeDays(categoryName ?? '', itemName: itemName);
}
