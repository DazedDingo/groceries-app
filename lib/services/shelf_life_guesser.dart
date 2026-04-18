/// Default shelf life in days by category name.
/// Used as a fallback when no per-item match is found.
const _shelfLifeByCategory = <String, int>{
  'meats': 3,
  'dairy': 10,
  'produce': 7,
  'bakery': 5,
  'frozen': 90,
  'drinks': 30,
  'spices': 365,
  'household': 365,
};

/// Per-item-name shelf life overrides (days). Checked before category fallback
/// so e.g. "milk" resolves to 7 instead of dairy's 10. Keywords match as
/// substrings of the lower-cased item name; longest key wins.
const _shelfLifeByItemName = <String, int>{
  // Meats subdivision
  'chicken breast': 2, 'chicken thigh': 3, 'chicken': 3,
  'ground beef': 2, 'ground turkey': 2, 'ground pork': 2,
  'steak': 3, 'beef': 3, 'pork': 3, 'lamb': 3,
  'bacon': 7, 'sausage': 3, 'deli meat': 5, 'ham': 5,
  'fish': 2, 'salmon': 2, 'tuna': 2, 'shrimp': 2, 'prawn': 2,
  // Dairy subdivision
  'milk': 7, 'heavy cream': 5, 'cream': 7,
  'yogurt': 21, 'yoghurt': 21, 'butter': 60,
  'hard cheese': 60, 'cheddar': 60, 'parmesan': 60,
  'cream cheese': 14, 'sour cream': 14, 'cottage cheese': 10,
  'cheese': 21, 'eggs': 28, 'egg': 28,
  // Produce — fruit
  'strawberries': 5, 'blueberries': 7, 'raspberries': 3, 'berries': 4,
  'banana': 5, 'apple': 21, 'orange': 14, 'lemon': 21, 'lime': 21,
  'avocado': 4, 'grape': 10, 'pear': 7, 'peach': 5, 'melon': 7,
  // Produce — veg
  'lettuce': 7, 'spinach': 5, 'kale': 7, 'arugula': 5, 'rocket': 5,
  'tomato': 7, 'cucumber': 7, 'bell pepper': 10,
  'carrot': 21, 'celery': 14, 'broccoli': 7, 'cauliflower': 7,
  'sweet potato': 21, 'potato': 30, 'onion': 30, 'garlic': 30,
  'mushroom': 5, 'cilantro': 5, 'coriander': 5, 'parsley': 7,
  // Bakery
  'bread': 5, 'bagel': 5, 'tortilla': 14, 'pita': 7, 'pitta': 7,
  'muffin': 4, 'croissant': 3,
  // Drinks
  'juice': 7, 'soda': 180, 'cola': 180, 'coffee': 60, 'tea': 365,
  'beer': 120, 'wine': 7,
};

final List<MapEntry<String, int>> _sortedNameKeywords = () {
  final list = _shelfLifeByItemName.entries.toList();
  final indexOf = <String, int>{
    for (var i = 0; i < list.length; i++) list[i].key: i,
  };
  list.sort((a, b) {
    final byLen = b.key.length.compareTo(a.key.length);
    if (byLen != 0) return byLen;
    return indexOf[a.key]!.compareTo(indexOf[b.key]!);
  });
  return list;
}();

/// Returns an estimated shelf life in days.
///
/// If [itemName] is provided, it is checked against a per-item keyword table
/// first (longest match wins) before falling back to [categoryName]. Returns
/// null if neither produces a match.
int? guessShelfLifeDays(String categoryName, {String? itemName}) {
  if (itemName != null && itemName.isNotEmpty) {
    final lower = itemName.toLowerCase();
    for (final entry in _sortedNameKeywords) {
      if (lower.contains(entry.key)) return entry.value;
    }
  }
  return _shelfLifeByCategory[categoryName.toLowerCase()];
}
