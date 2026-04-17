import 'dart:math';
import '../models/history_entry.dart';
import '../models/item.dart';
import '../models/pantry_item.dart';
import 'fuzzy_match.dart';

/// Origin of a suggestion candidate — used for tie-break weighting.
enum SuggestionSource { onList, history, pantry }

/// A candidate the user might be typing. Ranker consumes this;
/// providers assemble it from items + history + pantry.
class SuggestionItem {
  final String name;
  final DateTime? lastUsed;
  final int frequency;
  final SuggestionSource source;
  final bool isOnList;
  final bool isHighPriority;

  const SuggestionItem({
    required this.name,
    this.lastUsed,
    this.frequency = 0,
    required this.source,
    this.isOnList = false,
    this.isHighPriority = false,
  });
}

/// Internal scored row kept around just long enough to sort by score.
class _Scored {
  final SuggestionItem item;
  final double score;
  const _Scored(this.item, this.score);
}

/// Pure ranker. Returns up to [limit] names, de-duped (case-insensitive),
/// ordered by a hand-tuned blend of match quality, recency, frequency,
/// priority, and source. See the score breakdown below.
///
/// * Match quality — exact prefix (100) > substring (60) > fuzzy (25).
///   Empty query returns the high-frequency / recent defaults.
/// * Recency — exponential decay, half-life 14 days, max +30.
/// * Frequency — log1p(frequency) * 8, max effect ~+40 at freq ~= 150.
/// * High-priority pantry items get +25 (out-of-stock / running low).
/// * Items already on the list get -40 (don't suggest re-adding).
/// * Tie-break by source: onList < history < pantry (so pantry wins ties).
List<String> rankSuggestions(
  List<SuggestionItem> candidates,
  String query,
  DateTime now, {
  int limit = 10,
}) {
  final q = query.toLowerCase().trim();

  final seen = <String>{};
  final scored = <_Scored>[];

  for (final c in candidates) {
    final lower = c.name.toLowerCase().trim();
    if (lower.isEmpty) continue;
    if (!seen.add(lower)) continue;

    double score = 0;

    if (q.isEmpty) {
      // Default ordering (no query): recency + frequency drive.
      score = 10;
    } else if (lower == q) {
      score = 130;
    } else if (lower.startsWith(q)) {
      score = 100;
    } else if (lower.contains(q)) {
      score = 60;
    } else if (isFuzzyMatch(q, lower)) {
      score = 25;
    } else {
      continue; // doesn't match at all
    }

    // Recency: e^(-ageDays / 14) * 30. A fresh buy (<1 day) → ~+30;
    // 2-week-old buy → ~+11; 8-week-old → ~+1.3.
    final lastUsed = c.lastUsed;
    if (lastUsed != null) {
      final ageDays = now.difference(lastUsed).inMilliseconds / 86_400_000.0;
      if (ageDays >= 0) {
        score += 30.0 * exp(-ageDays / 14.0);
      }
    }

    if (c.frequency > 0) {
      score += 8.0 * (log(c.frequency + 1) / ln10);
    }

    if (c.isHighPriority) score += 25;
    if (c.isOnList) score -= 40;

    // Source tie-break (tiny): pantry 0.3, history 0.2, onList 0.1.
    switch (c.source) {
      case SuggestionSource.pantry:
        score += 0.3;
        break;
      case SuggestionSource.history:
        score += 0.2;
        break;
      case SuggestionSource.onList:
        score += 0.1;
        break;
    }

    scored.add(_Scored(c, score));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));

  return scored.take(limit).map((s) => s.item.name).toList();
}

/// Assembles a unified [SuggestionItem] list from the three Riverpod sources.
/// Merges entries by case-insensitive name so the same item doesn't appear
/// three times — each merged row keeps the best recency / frequency / flags
/// across sources, and source defaults to whichever is most informative
/// (pantry > history > onList).
List<SuggestionItem> buildSuggestions({
  required List<ShoppingItem> currentListItems,
  required List<HistoryEntry> history,
  required List<PantryItem> pantryItems,
}) {
  final byName = <String, SuggestionItem>{};

  SuggestionItem merge(SuggestionItem a, SuggestionItem b) {
    DateTime? newer(DateTime? x, DateTime? y) {
      if (x == null) return y;
      if (y == null) return x;
      return x.isAfter(y) ? x : y;
    }

    // Source precedence: keep the more informative of the two.
    SuggestionSource mergedSource() {
      if (a.source == SuggestionSource.pantry ||
          b.source == SuggestionSource.pantry) {
        return SuggestionSource.pantry;
      }
      if (a.source == SuggestionSource.history ||
          b.source == SuggestionSource.history) {
        return SuggestionSource.history;
      }
      return SuggestionSource.onList;
    }

    return SuggestionItem(
      name: a.name, // preserve first casing encountered
      lastUsed: newer(a.lastUsed, b.lastUsed),
      frequency: a.frequency + b.frequency,
      source: mergedSource(),
      isOnList: a.isOnList || b.isOnList,
      isHighPriority: a.isHighPriority || b.isHighPriority,
    );
  }

  void add(SuggestionItem s) {
    final key = s.name.toLowerCase().trim();
    if (key.isEmpty) return;
    final existing = byName[key];
    byName[key] = existing == null ? s : merge(existing, s);
  }

  // On-list.
  for (final i in currentListItems) {
    add(SuggestionItem(
      name: i.name,
      lastUsed: i.addedAt,
      source: SuggestionSource.onList,
      isOnList: true,
    ));
  }

  // History — count bought frequency, take most recent timestamp.
  final historyFreq = <String, int>{};
  final historyLatest = <String, DateTime>{};
  for (final h in history) {
    if (h.action != HistoryAction.bought) continue;
    final key = h.itemName.toLowerCase().trim();
    if (key.isEmpty) continue;
    historyFreq[key] = (historyFreq[key] ?? 0) + 1;
    final prev = historyLatest[key];
    if (prev == null || h.at.isAfter(prev)) historyLatest[key] = h.at;
  }
  for (final entry in historyFreq.entries) {
    // Re-find a representative display name (case from history).
    final displayName = history
        .firstWhere((h) => h.itemName.toLowerCase().trim() == entry.key)
        .itemName;
    add(SuggestionItem(
      name: displayName,
      lastUsed: historyLatest[entry.key],
      frequency: entry.value,
      source: SuggestionSource.history,
    ));
  }

  // Pantry.
  for (final p in pantryItems) {
    add(SuggestionItem(
      name: p.name,
      lastUsed: p.lastPurchasedAt,
      source: SuggestionSource.pantry,
      isHighPriority: p.isHighPriority || p.isBelowOptimal,
    ));
  }

  return byName.values.toList();
}
