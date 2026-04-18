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
  // Meats — subdivision
  'chicken breast': 2, 'chicken thigh': 3, 'chicken wing': 2, 'chicken': 3,
  'ground beef': 2, 'ground turkey': 2, 'ground pork': 2, 'ground chicken': 2,
  'steak': 3, 'beef': 3, 'pork chop': 3, 'pork': 3, 'lamb chop': 3, 'lamb': 3,
  'veal': 3, 'turkey': 3, 'duck': 3, 'ribs': 3, 'liver': 2,
  'bacon': 7, 'sausage': 3, 'hot dog': 7, 'deli meat': 5, 'ham': 5, 'prosciutto': 14,
  'salami': 21, 'pepperoni': 21,
  // Meats — seafood
  'fish': 2, 'salmon': 2, 'tuna': 2, 'shrimp': 2, 'prawn': 2,
  'scallop': 2, 'lobster': 2, 'crab': 2, 'mussel': 2, 'clam': 2, 'oyster': 2,
  'cod': 2, 'tilapia': 2, 'halibut': 2, 'sardine': 2,
  // Dairy
  'milk': 7, 'heavy cream': 5, 'whipping cream': 5, 'half and half': 7, 'cream': 7,
  'yogurt': 21, 'yoghurt': 21, 'kefir': 14, 'buttermilk': 14,
  'butter': 60, 'margarine': 90,
  'hard cheese': 60, 'cheddar': 60, 'parmesan': 60, 'gouda': 60, 'gruyere': 60,
  'cream cheese': 14, 'sour cream': 14, 'cottage cheese': 10,
  'mozzarella': 14, 'feta': 21, 'ricotta': 7, 'goat cheese': 14,
  'blue cheese': 21, 'brie': 14, 'camembert': 14,
  'cheese': 21, 'eggs': 28, 'egg': 28,
  // Plant-based "dairy"
  'almond milk': 14, 'oat milk': 14, 'soy milk': 14, 'coconut milk': 365,
  // Produce — fruit
  'strawberries': 5, 'strawberry': 5,
  'blueberries': 7, 'blueberry': 7,
  'raspberries': 3, 'raspberry': 3,
  'blackberries': 4, 'blackberry': 4, 'berries': 4, 'berry': 4,
  'banana': 5, 'apple': 21, 'orange': 14,
  'lemon': 21, 'lime': 21, 'grapefruit': 14,
  'tangerine': 10, 'clementine': 10, 'mandarin': 10,
  'avocado': 4, 'grape': 10, 'pear': 7, 'peach': 5, 'nectarine': 5,
  'apricot': 5, 'plum': 5, 'cherry': 4, 'cherries': 4,
  'watermelon': 7, 'cantaloupe': 5, 'honeydew': 7, 'melon': 7,
  'kiwi': 7, 'mango': 5, 'pineapple': 5, 'papaya': 5, 'passionfruit': 7,
  'pomegranate': 14, 'fig': 3, 'date': 180, 'raisin': 365,
  // Produce — veg (greens + leafy)
  'lettuce': 7, 'romaine': 7, 'spinach': 5, 'kale': 7,
  'arugula': 5, 'rocket': 5, 'chard': 5, 'bok choy': 5,
  'cabbage': 14, 'brussels sprout': 7,
  // Produce — veg (fruiting/pod)
  'tomato': 7, 'cucumber': 7, 'bell pepper': 10, 'pepper': 10,
  'zucchini': 7, 'squash': 30, 'pumpkin': 60, 'eggplant': 7, 'aubergine': 7,
  'okra': 5, 'green bean': 7, 'snap pea': 5, 'pea pod': 5, 'edamame': 5,
  'corn': 5, 'asparagus': 5, 'artichoke': 7,
  // Produce — veg (root/bulb)
  'carrot': 21, 'beet': 21, 'turnip': 21, 'radish': 10, 'parsnip': 21,
  'ginger': 21, 'sweet potato': 21, 'potato': 30,
  'onion': 30, 'shallot': 30, 'leek': 10, 'scallion': 7, 'green onion': 7,
  'garlic': 30,
  // Produce — veg (other)
  'broccoli': 7, 'cauliflower': 7, 'celery': 14,
  'mushroom': 5,
  // Produce — herbs
  'cilantro': 5, 'coriander': 5, 'parsley': 7, 'basil': 4, 'mint': 7,
  'dill': 4, 'chive': 5, 'rosemary': 10, 'thyme': 10, 'sage': 10, 'oregano': 10,
  // Bakery
  'bread': 5, 'sourdough': 5, 'baguette': 2, 'bagel': 5, 'english muffin': 7,
  'tortilla': 14, 'pita': 7, 'pitta': 7, 'naan': 5,
  'muffin': 4, 'croissant': 3, 'scone': 3, 'donut': 3, 'doughnut': 3,
  'cake': 3, 'pie': 3, 'pastry': 3, 'cupcake': 3,
  // Drinks
  'juice': 7, 'orange juice': 7, 'apple juice': 14, 'lemonade': 14,
  'soda': 180, 'cola': 180, 'seltzer': 365, 'sparkling water': 365,
  'water': 365, 'coconut water': 14, 'sports drink': 180, 'energy drink': 180,
  'coffee bean': 180, 'coffee': 60, 'tea': 365,
  'beer': 120, 'wine': 7, 'liquor': 730, 'spirits': 730,
  // Grains / pasta / rice
  'white rice': 365, 'brown rice': 180, 'rice': 365,
  'pasta': 365, 'spaghetti': 365, 'penne': 365, 'macaroni': 365, 'noodle': 365,
  'couscous': 365, 'quinoa': 365, 'barley': 365, 'farro': 365, 'bulgur': 365,
  'oatmeal': 180, 'oats': 180, 'oat': 180,
  'cereal': 90, 'granola': 60, 'muesli': 90,
  'flour': 180, 'bread crumb': 180, 'breadcrumb': 180,
  // Legumes (dried) + canned
  'lentil': 365, 'dried bean': 365, 'chickpea': 365, 'garbanzo': 365,
  'split pea': 365, 'black bean': 365, 'kidney bean': 365, 'pinto bean': 365,
  'canned bean': 365, 'canned corn': 365, 'canned tomato': 365,
  'canned tuna': 365, 'canned salmon': 365, 'canned fish': 365,
  'canned soup': 365, 'canned vegetable': 365, 'canned': 365,
  'tomato paste': 180, 'tomato sauce': 180, 'pasta sauce': 180,
  'marinara': 180, 'pesto': 7, 'salsa': 30, 'hummus': 7,
  // Oils / vinegars / condiments
  'olive oil': 180, 'sesame oil': 365, 'coconut oil': 365,
  'vegetable oil': 365, 'canola oil': 365, 'avocado oil': 180, 'oil': 180,
  'balsamic vinegar': 365, 'vinegar': 365,
  'ketchup': 180, 'mustard': 180, 'mayo': 60, 'mayonnaise': 60,
  'ranch': 60, 'vinaigrette': 60, 'dressing': 60,
  'hot sauce': 365, 'soy sauce': 365, 'sriracha': 365,
  'worcestershire': 365, 'bbq sauce': 180, 'barbecue sauce': 180,
  'honey': 730, 'maple syrup': 365, 'syrup': 365,
  'jam': 90, 'jelly': 90, 'preserve': 90, 'marmalade': 90,
  'peanut butter': 180, 'almond butter': 180, 'nutella': 90,
  'pickle': 90, 'relish': 180, 'capers': 365, 'olives': 30,
  // Baking
  'sugar': 730, 'brown sugar': 365, 'powdered sugar': 730,
  'baking soda': 365, 'baking powder': 365, 'yeast': 90,
  'vanilla extract': 365, 'cocoa': 365, 'chocolate chip': 180,
  'chocolate': 365,
  // Spices (table already covers via category, but common specifics)
  'black pepper': 730, 'salt': 1095, 'cinnamon': 730, 'paprika': 730,
  'garlic powder': 730, 'onion powder': 730, 'cumin': 730, 'turmeric': 730,
  'chili powder': 730, 'curry powder': 730, 'bay leaf': 730,
  // Nuts / seeds
  'almond': 90, 'cashew': 90, 'walnut': 90, 'pecan': 90, 'pistachio': 90,
  'peanut': 120, 'hazelnut': 90, 'nut': 90,
  'sunflower seed': 90, 'pumpkin seed': 90, 'chia seed': 365, 'flax seed': 180,
  'sesame seed': 180, 'seed': 90,
  // Snacks
  'chip': 30, 'crisp': 30, 'cracker': 60, 'cookie': 30,
  'pretzel': 60, 'popcorn': 60, 'granola bar': 90, 'protein bar': 120,
  // Tofu / plant proteins
  'tofu': 7, 'tempeh': 10, 'seitan': 10,
  // Frozen
  'ice cream': 60, 'frozen pizza': 90, 'frozen meal': 90,
  'frozen vegetable': 180, 'frozen fruit': 180, 'frozen berry': 180,
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
