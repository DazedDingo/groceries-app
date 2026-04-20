import '../models/category.dart';
import '../models/pantry_item.dart';

/// Pure helpers for grouping pantry items on the Pantry tab. Extracted so the
/// "by category" / "by location" views can be unit-tested without spinning up
/// Firestore or widget trees.

/// Severity rank used to sort items within a group so the things that need
/// attention float to the top of every Category / Location section.
int statusRank(PantryItem p) {
  if (p.isExpired) return 0;
  if (p.isExpiringSoon) return 1;
  if (p.isBelowOptimal) return 2;
  if (p.isStale) return 3;
  return 4;
}

int _byStatusThenName(PantryItem a, PantryItem b) {
  final r = statusRank(a).compareTo(statusRank(b));
  if (r != 0) return r;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// A single group rendered as a section on the Pantry tab. [label] is the
/// header, [items] is already sorted for display.
class PantryGroup {
  final String label;
  final List<PantryItem> items;
  const PantryGroup({required this.label, required this.items});
}

/// Group by category. Sections follow the user's category order; items
/// without a matching category land in a trailing "Uncategorised" bucket so
/// nothing disappears when a category is deleted.
List<PantryGroup> groupByCategory(
  List<PantryItem> pantry,
  List<GroceryCategory> categories,
) {
  final byCat = <String, List<PantryItem>>{};
  final catIds = categories.map((c) => c.id).toSet();
  for (final p in pantry) {
    final key = catIds.contains(p.categoryId) ? p.categoryId : '__uncat__';
    byCat.putIfAbsent(key, () => []).add(p);
  }
  final groups = <PantryGroup>[];
  for (final c in categories) {
    final g = byCat[c.id];
    if (g == null || g.isEmpty) continue;
    g.sort(_byStatusThenName);
    groups.add(PantryGroup(label: c.name, items: g));
  }
  final uncat = byCat['__uncat__'];
  if (uncat != null && uncat.isNotEmpty) {
    uncat.sort(_byStatusThenName);
    groups.add(PantryGroup(label: 'Uncategorised', items: uncat));
  }
  return groups;
}

/// Group by location. Built-in [PantryLocation] values come first in their
/// declared order, then any custom labels, then a "Not set" bucket for items
/// without a location.
List<PantryGroup> groupByLocation(
  List<PantryItem> pantry,
  List<String> customLocations,
) {
  final byLoc = <String, List<PantryItem>>{};
  for (final p in pantry) {
    final key = p.location ?? '__not_set__';
    byLoc.putIfAbsent(key, () => []).add(p);
  }
  final groups = <PantryGroup>[];
  for (final loc in PantryLocation.values) {
    final g = byLoc[loc.id];
    if (g == null || g.isEmpty) continue;
    g.sort(_byStatusThenName);
    groups.add(PantryGroup(label: loc.label, items: g));
  }
  for (final label in customLocations) {
    final g = byLoc[label];
    if (g == null || g.isEmpty) continue;
    g.sort(_byStatusThenName);
    groups.add(PantryGroup(label: label, items: g));
  }
  final unsorted = byLoc['__not_set__'];
  if (unsorted != null && unsorted.isNotEmpty) {
    unsorted.sort(_byStatusThenName);
    groups.add(PantryGroup(label: 'Not set', items: unsorted));
  }
  return groups;
}
