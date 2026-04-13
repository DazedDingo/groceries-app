/// Default shelf life in days by category name.
/// Used to auto-set expiry when an item is purchased.
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

/// Returns an estimated shelf life in days for [categoryName],
/// or null if no estimate is available.
int? guessShelfLifeDays(String categoryName) {
  return _shelfLifeByCategory[categoryName.toLowerCase()];
}
