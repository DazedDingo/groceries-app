import '../models/pantry_item.dart';
import '../models/recipe.dart';

/// Returns the pantry item that matches [ingredientName] by lenient name
/// comparison (case-insensitive, substring either direction), or null.
/// Quantity is NOT considered — presence is enough.
PantryItem? findLenientPantryMatch(
    String ingredientName, List<PantryItem> pantry) {
  final needle = ingredientName.toLowerCase().trim();
  if (needle.isEmpty) return null;
  // Exact match wins.
  for (final p in pantry) {
    if (p.name.toLowerCase().trim() == needle) return p;
  }
  // Fall back to substring either direction.
  for (final p in pantry) {
    final n = p.name.toLowerCase().trim();
    if (n.isEmpty) continue;
    if (n.contains(needle) || needle.contains(n)) return p;
  }
  return null;
}

/// True when every ingredient of [recipe] has a lenient match in [pantry].
/// Quantity is ignored (lenient mode).
bool canMakeFromPantry(Recipe recipe, List<PantryItem> pantry) {
  if (recipe.ingredients.isEmpty) return false;
  for (final ing in recipe.ingredients) {
    if (findLenientPantryMatch(ing.name, pantry) == null) return false;
  }
  return true;
}
