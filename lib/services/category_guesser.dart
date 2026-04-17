import '../models/category.dart';

const _keywords = <String, String>{
  // Meats
  'meat': 'Meats', 'chicken': 'Meats', 'beef': 'Meats', 'pork': 'Meats',
  'lamb': 'Meats', 'mince': 'Meats', 'steak': 'Meats', 'bacon': 'Meats',
  'sausage': 'Meats', 'ham': 'Meats', 'turkey': 'Meats', 'fish': 'Meats',
  'salmon': 'Meats', 'tuna': 'Meats', 'prawn': 'Meats', 'shrimp': 'Meats',
  // Dairy
  'milk': 'Dairy', 'cheese': 'Dairy', 'butter': 'Dairy', 'yogurt': 'Dairy',
  'yoghurt': 'Dairy', 'cream': 'Dairy', 'egg': 'Dairy', 'eggs': 'Dairy',
  'margarine': 'Dairy', 'cheddar': 'Dairy',
  // Produce
  'apple': 'Produce', 'banana': 'Produce', 'orange': 'Produce', 'grape': 'Produce',
  'strawberry': 'Produce', 'carrot': 'Produce', 'potato': 'Produce',
  'onion': 'Produce', 'tomato': 'Produce', 'lettuce': 'Produce',
  'spinach': 'Produce', 'broccoli': 'Produce', 'pepper': 'Produce',
  'cucumber': 'Produce', 'mushroom': 'Produce', 'courgette': 'Produce',
  'avocado': 'Produce', 'lemon': 'Produce', 'lime': 'Produce', 'garlic': 'Produce',
  'fruit': 'Produce', 'veg': 'Produce', 'vegetable': 'Produce', 'salad': 'Produce',
  // Bakery
  'bread': 'Bakery', 'roll': 'Bakery', 'bun': 'Bakery', 'cake': 'Bakery',
  'pastry': 'Bakery', 'croissant': 'Bakery', 'muffin': 'Bakery', 'flour': 'Bakery',
  'bagel': 'Bakery', 'wrap': 'Bakery', 'pitta': 'Bakery', 'loaf': 'Bakery',
  // Spices
  'salt': 'Spices', 'spice': 'Spices', 'herb': 'Spices', 'cumin': 'Spices',
  'paprika': 'Spices', 'oregano': 'Spices', 'thyme': 'Spices', 'basil': 'Spices',
  'cinnamon': 'Spices', 'turmeric': 'Spices', 'ginger': 'Spices',
  // Frozen
  'frozen': 'Frozen', 'ice cream': 'Frozen', 'chips': 'Frozen',
  // Drinks
  'water': 'Drinks', 'juice': 'Drinks', 'beer': 'Drinks', 'wine': 'Drinks',
  'coffee': 'Drinks', 'tea': 'Drinks', 'soda': 'Drinks', 'cola': 'Drinks',
  'squash': 'Drinks', 'lemonade': 'Drinks', 'smoothie': 'Drinks',
  'orange juice': 'Drinks',
  // Household
  'soap': 'Household', 'shampoo': 'Household', 'detergent': 'Household',
  'cleaner': 'Household', 'tissue': 'Household', 'toilet': 'Household',
  'bleach': 'Household', 'sponge': 'Household', 'bin bag': 'Household',
  'washing up': 'Household', 'toothpaste': 'Household', 'deodorant': 'Household',
};

// Longest keyword first so multi-word keys ("orange juice") match before
// shorter substrings ("orange"). Mirrors functions/src/categoryGuesser.ts.
final List<MapEntry<String, String>> _sortedKeywords =
    _keywords.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

/// Returns the matching [GroceryCategory] from [categories] for [itemName],
/// or null if no match found.
///
/// If [overrides] is provided, user corrections are checked first.
GroceryCategory? guessCategory(
  String itemName,
  List<GroceryCategory> categories, [
  Map<String, String> overrides = const {},
]) {
  final lower = itemName.toLowerCase();

  // Check user overrides first
  final overrideId = overrides[lower];
  if (overrideId != null) {
    try {
      return categories.firstWhere((c) => c.id == overrideId);
    } catch (_) {}
  }

  for (final entry in _sortedKeywords) {
    if (lower.contains(entry.key)) {
      try {
        return categories.firstWhere(
          (c) => c.name.toLowerCase() == entry.value.toLowerCase(),
        );
      } catch (_) {}
    }
  }
  return null;
}
